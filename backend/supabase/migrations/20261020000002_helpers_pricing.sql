-- Helpers, integrity guards, server-side pricing and catalogue reads.
set check_function_bodies = off;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin');
$$;

create function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

-- Canonical Bangladeshi mobile number 01XXXXXXXXX, or null when invalid.
create function public.normalize_phone(p text) returns text language sql immutable as $$
  select case
    when regexp_replace(coalesce(p,''), '[\s-]', '', 'g') ~ '^(\+?88)?01[3-9][0-9]{8}$'
    then '0' || right(regexp_replace(regexp_replace(coalesce(p,''), '[\s-]', '', 'g'), '^\+?88', ''), 10)
  end;
$$;

-- Allowed measurement fields and sanity ranges (cm). Mirrors the app.
create function public.validate_measurements(p_values jsonb) returns jsonb
language plpgsql immutable as $$
declare
  k text; v numeric; lo numeric; hi numeric; cleaned jsonb := '{}'::jsonb;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then return '{}'::jsonb; end if;
  for k in select jsonb_object_keys(p_values) loop
    lo := null; hi := null;
    select r.lo, r.hi into lo, hi from (values
      ('neck',25,60),('chest',60,160),('shoulder',30,70),('sleeveLength',40,90),('armhole',30,80),
      ('waist',50,160),('hip',60,180),('shirtLength',40,110),('trouserWaist',50,160),
      ('inseam',50,110),('trouserLength',70,140)) as r(name, lo, hi) where r.name = k;
    if lo is null then
      raise exception 'Unknown measurement field "%".', k using errcode = 'P0001', hint = 'MEASUREMENT_INVALID';
    end if;
    if jsonb_typeof(p_values -> k) = 'null' then continue; end if;
    if jsonb_typeof(p_values -> k) <> 'number' then
      raise exception '% must be a number.', k using errcode = 'P0001', hint = 'MEASUREMENT_INVALID';
    end if;
    v := (p_values ->> k)::numeric;
    if v < lo or v > hi then
      raise exception '% must be between % and % cm.', k, lo, hi using errcode = 'P0001', hint = 'MEASUREMENT_INVALID';
    end if;
    cleaned := cleaned || jsonb_build_object(k, v);
  end loop;
  return cleaned;
end $$;

-- Simple per-user rate limiter (used to stop voucher-code guessing).
create function public.check_rate_limit(p_bucket text, p_limit integer, p_window interval default interval '1 minute')
returns void language plpgsql security definer set search_path = public as $$
declare
  w timestamptz := date_bin(p_window, now(), timestamptz 'epoch'); n integer;
begin
  if auth.uid() is null then return; end if;
  insert into rate_limits(user_id, bucket, window_start, hits) values (auth.uid(), p_bucket, w, 1)
  on conflict (user_id, bucket, window_start) do update set hits = rate_limits.hits + 1
  returning hits into n;
  if n > p_limit then
    raise exception 'Too many attempts. Please wait a minute and try again.' using errcode = 'P0001', hint = 'RATE_LIMITED';
  end if;
  delete from rate_limits where window_start < now() - interval '1 day';
end $$;

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_name text := btrim(coalesce(meta ->> 'name', ''));
  v_phone text := coalesce(meta ->> 'phone', '');
  v_addr text := btrim(coalesce(meta ->> 'address', ''));
  v_canon text;
  v_meas jsonb;
begin
  if v_name = '' then v_name := initcap(split_part(new.email, '@', 1)); end if;
  if char_length(v_name) < 2 then v_name := 'Customer'; end if;
  v_canon := public.normalize_phone(v_phone);
  if btrim(v_phone) <> '' and v_canon is null then
    raise exception 'Enter a valid mobile number (e.g. 01712345678).' using errcode = 'P0001';
  end if;
  -- The role is ALWAYS customer here; client metadata can never grant admin.
  insert into public.profiles(id, name, email, phone, address, role)
  values (new.id, v_name, lower(new.email), coalesce(v_canon, ''), v_addr, 'customer');
  v_meas := public.validate_measurements(meta -> 'measurements');
  if v_meas <> '{}'::jsonb then
    insert into public.customer_measurements(user_id, "values") values (new.id, v_meas);
  end if;
  insert into public.notifications(user_id, title, body)
  values (new.id, 'Welcome to Top Tailers & Fabrics', 'Your account is ready. Start browsing our collection.');
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.profiles_guard() returns trigger language plpgsql as $$
begin
  if new.role is distinct from old.role and current_user not in ('postgres','service_role','supabase_admin') then
    raise exception 'Role changes are not allowed.' using errcode = '42501', hint = 'FORBIDDEN';
  end if;
  if new.email is distinct from old.email or new.id is distinct from old.id or new.created_at is distinct from old.created_at then
    raise exception 'Email and account identity cannot be changed here.' using errcode = 'P0001';
  end if;
  if new.phone is distinct from old.phone then
    new.phone := coalesce(public.normalize_phone(new.phone), '');
    if new.phone = '' then
      raise exception 'Enter a valid mobile number (e.g. 01712345678).' using errcode = 'P0001';
    end if;
  end if;
  if char_length(btrim(new.name)) < 2 then
    raise exception 'Name must be at least 2 characters.' using errcode = 'P0001';
  end if;
  if char_length(btrim(new.address)) between 1 and 7 then
    raise exception 'Please enter a more complete address.' using errcode = 'P0001';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger profiles_guard_trg before update on public.profiles
  for each row execute function public.profiles_guard();

-- Queue Cloudinary assets that lose their last reference.
create function public.queue_cloudinary_cleanup() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'product_images' and tg_op = 'DELETE' then
    insert into image_cleanup_queue(public_id) values (old.public_id) on conflict do nothing;
  elsif tg_table_name = 'profiles' and old.profile_image_public_id is not null
        and new.profile_image_public_id is distinct from old.profile_image_public_id then
    insert into image_cleanup_queue(public_id) values (old.profile_image_public_id) on conflict do nothing;
  end if;
  return null;
end $$;
create trigger product_images_cleanup after delete on public.product_images
  for each row execute function public.queue_cloudinary_cleanup();
create trigger profiles_image_cleanup after update of profile_image_public_id on public.profiles
  for each row execute function public.queue_cloudinary_cleanup();

create function public.products_normalize() returns trigger language plpgsql as $$
begin
  new.code := upper(btrim(new.code));
  new.updated_at := now();
  return new;
end $$;
create trigger products_normalize_trg before insert or update on public.products
  for each row execute function public.products_normalize();

create function public.forbid_mutation() returns trigger language plpgsql as $$
begin
  raise exception '% is append-only; existing rows cannot be changed or deleted.', tg_table_name
    using errcode = 'P0001', hint = 'IMMUTABLE_RECORD';
end $$;
create trigger order_items_immutable before update or delete on public.order_items
  for each row execute function public.forbid_mutation();
create trigger order_measurements_immutable before update or delete on public.order_measurements
  for each row execute function public.forbid_mutation();
create trigger order_events_immutable before update or delete on public.order_events
  for each row execute function public.forbid_mutation();
create trigger cancellations_immutable before update or delete on public.cancellations
  for each row execute function public.forbid_mutation();
create trigger orders_no_delete before delete on public.orders
  for each row execute function public.forbid_mutation();
create trigger payments_no_delete before delete on public.payments
  for each row execute function public.forbid_mutation();

create function public.status_label(s text) returns text language sql immutable as $$
  select initcap(s);
$$;

create function public.orders_guard() returns trigger language plpgsql as $$
begin
  if (to_jsonb(new) - 'status' - 'updated_at') is distinct from (to_jsonb(old) - 'status' - 'updated_at') then
    raise exception 'Order details are a snapshot and cannot be changed.' using errcode = 'P0001', hint = 'IMMUTABLE_RECORD';
  end if;
  if new.status is distinct from old.status then
    if not ((old.status = 'pending' and new.status in ('confirmed','cancelled'))
         or (old.status = 'confirmed' and new.status in ('processing','cancelled'))
         or (old.status = 'processing' and new.status = 'completed')) then
      raise exception 'An order cannot move from % to %.', public.status_label(old.status), public.status_label(new.status)
        using errcode = 'P0001', hint = 'ORDER_INVALID_TRANSITION';
    end if;
    if new.status = 'cancelled' and not exists (select 1 from public.cancellations c where c.order_id = new.id) then
      raise exception 'A cancellation record is required.' using errcode = 'P0001', hint = 'ORDER_INVALID_TRANSITION';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger orders_guard_trg before update on public.orders
  for each row execute function public.orders_guard();

create function public.orders_log_status() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_events(order_id, status, at) values (new.id, new.status, new.order_date);
  elsif new.status is distinct from old.status then
    insert into public.order_events(order_id, status, at) values (new.id, new.status, now());
  end if;
  return null;
end $$;
create trigger orders_log_status_trg after insert or update of status on public.orders
  for each row execute function public.orders_log_status();

create function public.payments_guard() returns trigger language plpgsql as $$
begin
  if new.order_id is distinct from old.order_id or new.method is distinct from old.method
     or new.amount_minor is distinct from old.amount_minor then
    raise exception 'Payment identity and amount cannot be changed.' using errcode = 'P0001', hint = 'IMMUTABLE_RECORD';
  end if;
  if old.status = 'successful' and new.status <> 'successful' then
    raise exception 'A successful payment cannot be reverted.' using errcode = 'P0001', hint = 'IMMUTABLE_RECORD';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger payments_guard_trg before update on public.payments
  for each row execute function public.payments_guard();

-- Integer maths, rounded down to the paisa. Mirrors lib/domain/discount.dart.
create function public.discount_amount(p_kind text, p_value bigint, p_basis bigint) returns bigint
language sql immutable as $$
  select case
    when p_basis is null or p_basis <= 0 or p_value is null or p_value <= 0 then 0::bigint
    else least(p_basis, case when p_kind = 'percent' then (p_basis * p_value) / 100 else p_value end)
  end
$$;

create function public.product_discount_minor(p public.products) returns bigint
language sql immutable as $$
  select case when p.discount_enabled then public.discount_amount(p.discount_kind, p.discount_value, p.price_minor) else 0 end
$$;

create function public.get_setting_bigint(p_key text) returns bigint language sql stable as $$
  select nullif(btrim(value), '')::bigint from public.app_settings where key = p_key
$$;

-- One calculation used by the cart quote AND order placement, so displayed and
-- charged totals cannot diverge. Stacking rules:
--  1. product discount lowers the line price
--  2. vouchers/customer discounts ignore lines with a product discount
--  3. customer discount and voucher never stack: the larger wins, tie -> customer
create function public.compute_pricing(p_lines jsonb, p_voucher text, p_customer uuid, p_now timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_count integer; v_resolved integer;
  v_subtotal bigint; v_after bigint; v_base_all bigint; v_base_voucher bigint;
  v_code text := upper(btrim(coalesce(p_voucher, '')));
  v_vou public.vouchers%rowtype; v_has_vou boolean := false;
  v_cust public.customer_discounts%rowtype; v_has_cust boolean := false;
  v_vou_amt bigint := 0; v_cust_amt bigint := 0; v_note text; v_issue text;
  v_source text := 'none'; v_applied_vou bigint := 0; v_applied_cust bigint := 0;
  v_flat bigint; v_free bigint; v_delivery bigint; v_cats text[]; v_scope text;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Your cart is empty.' using errcode = 'P0001', hint = 'CART_EMPTY';
  end if;
  v_count := jsonb_array_length(p_lines);

  if v_code <> '' then
    select * into v_vou from public.vouchers where code = v_code;
    v_has_vou := found;
  end if;
  v_cats := case when v_has_vou then v_vou.categories else '{}'::text[] end;

  select count(*),
         coalesce(sum(p.price_minor::bigint * s.qty), 0),
         coalesce(sum((p.price_minor - public.product_discount_minor(p))::bigint * s.qty), 0),
         coalesce(sum(p.price_minor::bigint * s.qty) filter (where public.product_discount_minor(p) = 0), 0),
         coalesce(sum(p.price_minor::bigint * s.qty) filter (where public.product_discount_minor(p) = 0
                   and (cardinality(v_cats) = 0 or p.category = any (v_cats))), 0)
    into v_resolved, v_subtotal, v_after, v_base_all, v_base_voucher
  from (select (l ->> 'productId')::uuid as pid, (l ->> 'quantity')::integer as qty
          from jsonb_array_elements(p_lines) l) s
  join public.products p on p.id = s.pid and p.deleted_at is null;

  if v_resolved <> v_count then
    raise exception 'An item in your cart is no longer available. Please update your cart.'
      using errcode = 'P0001', hint = 'PRODUCT_UNAVAILABLE';
  end if;

  if p_customer is not null then
    select * into v_cust from public.customer_discounts where customer_id = p_customer and active;
    v_has_cust := found;
    if v_has_cust then v_cust_amt := public.discount_amount(v_cust.kind, v_cust.value, v_base_all); end if;
  end if;

  if v_code <> '' then
    if not v_has_vou then
      v_issue := 'notFound'; v_note := 'This voucher code is not valid.';
    elsif not v_vou.is_active then
      v_issue := 'inactive'; v_note := 'This voucher is not active.';
    elsif v_vou.expires_at is not null and p_now >= v_vou.expires_at then
      v_issue := 'expired'; v_note := 'This voucher has expired.';
    elsif v_count = 0 then
      v_issue := 'emptyCart'; v_note := 'Add items to your cart before applying a voucher.';
    elsif v_base_voucher <= 0 then
      v_issue := 'notApplicable';
      v_scope := case when cardinality(v_vou.categories) = 0 then '' else ' in ' || array_to_string(v_vou.categories, ', ') end;
      v_note := 'No eligible items' || v_scope || '. Vouchers do not apply to items that already have a discount.';
    else
      v_vou_amt := public.discount_amount(v_vou.kind, v_vou.value, v_base_voucher);
    end if;
  end if;

  if v_vou_amt > v_cust_amt then
    v_source := 'voucher'; v_applied_vou := v_vou_amt;
  elsif v_cust_amt > 0 then
    v_source := 'customer'; v_applied_cust := v_cust_amt;
    if v_has_vou and v_issue is null then
      v_note := 'Voucher ' || v_vou.code || ' not applied: your customer discount is larger. Only one order-level discount can apply.';
    end if;
  end if;

  v_flat := coalesce(public.get_setting_bigint('delivery_flat_minor'), 0);
  v_free := public.get_setting_bigint('delivery_free_above_minor');
  v_delivery := case when v_free is not null and v_after >= v_free then 0 else v_flat end;

  return jsonb_build_object(
    'subtotalMinor', v_subtotal,
    'productDiscountMinor', v_subtotal - v_after,
    'customerDiscountMinor', v_applied_cust,
    'voucherDiscountMinor', v_applied_vou,
    'deliveryMinor', v_delivery,
    'totalMinor', greatest(0, v_subtotal - (v_subtotal - v_after) - v_applied_cust - v_applied_vou + v_delivery),
    'voucherCode', case when v_source = 'voucher' then v_vou.code end,
    'source', v_source,
    'voucherNote', v_note,
    'voucherIssue', v_issue
  );
end $$;

create function public.quote_pricing(p_lines jsonb, p_voucher text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in.' using errcode = '28000', hint = 'UNAUTHENTICATED';
  end if;
  if btrim(coalesce(p_voucher, '')) <> '' then
    perform public.check_rate_limit('voucher', 30);
  end if;
  return public.compute_pricing(p_lines, p_voucher, auth.uid());
end $$;

create function public.voucher_json(v public.vouchers) returns jsonb language sql stable as $$
  select jsonb_build_object('code', v.code, 'title', v.title, 'kind', v.kind, 'value', v.value,
    'expiresAt', v.expires_at, 'categories', to_jsonb(v.categories), 'isActive', v.is_active, 'isPublic', v.is_public)
$$;

create function public.get_voucher(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v public.vouchers%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Please sign in.' using errcode = '28000', hint = 'UNAUTHENTICATED';
  end if;
  perform public.check_rate_limit('voucher', 30);
  select * into v from public.vouchers where code = upper(btrim(coalesce(p_code, '')));
  if not found then return null; end if;
  return public.voucher_json(v);
end $$;

create function public.product_json(p public.products) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'code', p.code, 'productName', p.product_name, 'description', p.description,
    'priceMinor', p.price_minor, 'category', p.category, 'availability', p.availability,
    'imagePaths', coalesce((select jsonb_agg(i.url order by i.position) from public.product_images i where i.product_id = p.id), '[]'::jsonb),
    'imagePublicIds', coalesce((select jsonb_agg(i.public_id order by i.position) from public.product_images i where i.product_id = p.id), '[]'::jsonb),
    'colors', coalesce((select jsonb_agg(jsonb_build_object('name', v.name, 'argb', v.argb) order by v.position, v.name)
                         from public.product_variants v where v.product_id = p.id and v.type = 'color'), '[]'::jsonb),
    'sizes', coalesce((select jsonb_agg(v.name order by v.position, v.name)
                         from public.product_variants v where v.product_id = p.id and v.type = 'size'), '[]'::jsonb),
    'specs', p.specs, 'isFeatured', p.is_featured, 'popularity', p.popularity, 'unit', p.unit,
    'requiresMeasurements', p.requires_measurements,
    'discount', case when p.discount_kind is not null and p.discount_value is not null
                 then jsonb_build_object('enabled', p.discount_enabled, 'kind', p.discount_kind, 'value', p.discount_value) end,
    'createdAt', p.created_at)
$$;

create function public.escape_like(p text) returns text language sql immutable as $$
  select replace(replace(replace(coalesce(p, ''), '\', '\\'), '%', '\%'), '_', '\_')
$$;

create function public.search_products(
  p_text text default '', p_category text default null, p_sort text default 'featured',
  p_in_stock boolean default false, p_page integer default 1, p_page_size integer default 8
) returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_size integer := least(greatest(coalesce(p_page_size, 8), 1), 50);
  v_pat text := '%' || public.escape_like(btrim(coalesce(p_text, ''))) || '%';
  v_total integer; v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Please sign in.' using errcode = '28000', hint = 'UNAUTHENTICATED';
  end if;
  if p_category is not null and p_category not in ('Fabrics','Readymade','Tailoring','Accessories') then
    raise exception 'Unknown category.' using errcode = 'P0001';
  end if;
  if p_sort not in ('featured','newest','priceLow','priceHigh','nameAZ') then
    raise exception 'Unknown sort order.' using errcode = 'P0001';
  end if;

  select count(*) into v_total from public.products p
   where p.deleted_at is null and (p_category is null or p.category = p_category)
     and (not coalesce(p_in_stock, false) or p.availability)
     and (p.product_name ilike v_pat escape '\' or p.description ilike v_pat escape '\'
          or p.category ilike v_pat escape '\' or p.code ilike v_pat escape '\');

  select coalesce(jsonb_agg(public.product_json(pp) order by q.rn), '[]'::jsonb) into v_items
  from (
    select p.id, row_number() over (order by
        case when p_sort = 'featured' then (case when p.is_featured then 0 else 1 end) end,
        case when p_sort = 'featured' then -p.popularity end,
        case when p_sort = 'priceLow' then p.price_minor - public.product_discount_minor(p) end,
        case when p_sort = 'priceHigh' then -(p.price_minor - public.product_discount_minor(p)) end,
        case when p_sort = 'newest' then extract(epoch from p.created_at) * -1 end,
        case when p_sort in ('featured','nameAZ') then lower(p.product_name) end,
        p.id) as rn
    from public.products p
    where p.deleted_at is null and (p_category is null or p.category = p_category)
      and (not coalesce(p_in_stock, false) or p.availability)
      and (p.product_name ilike v_pat escape '\' or p.description ilike v_pat escape '\'
           or p.category ilike v_pat escape '\' or p.code ilike v_pat escape '\')
  ) q
  join public.products pp on pp.id = q.id
  where q.rn > (v_page - 1) * v_size and q.rn <= v_page * v_size;

  return jsonb_build_object('items', v_items, 'page', v_page, 'hasMore', v_page * v_size < v_total, 'total', v_total);
end $$;

create function public.get_products_by_ids(p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in.' using errcode = '28000', hint = 'UNAUTHENTICATED';
  end if;
  return coalesce((select jsonb_agg(public.product_json(p)) from public.products p
                    where p.id = any (p_ids) and p.deleted_at is null), '[]'::jsonb);
end $$;

create function public.get_home() returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in.' using errcode = '28000', hint = 'UNAUTHENTICATED';
  end if;
  return jsonb_build_object(
    'banners', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'title', b.title, 'subtitle', b.subtitle,
        'colorArgb', b.color_argb, 'category', b.category, 'voucherCode', b.voucher_code) order by b.position)
        from public.promo_banners b where b.active), '[]'::jsonb),
    'featured', coalesce((select jsonb_agg(public.product_json(x) order by x.popularity desc, lower(x.product_name))
        from (select * from public.products where deleted_at is null and availability and is_featured and category = 'Fabrics'
              order by popularity desc, lower(product_name) limit 8) x), '[]'::jsonb),
    'services', coalesce((select jsonb_agg(public.product_json(x) order by x.popularity desc, lower(x.product_name))
        from (select * from public.products where deleted_at is null and availability and category = 'Tailoring'
              order by popularity desc, lower(product_name) limit 8) x), '[]'::jsonb),
    'popular', coalesce((select jsonb_agg(public.product_json(x) order by x.popularity desc, lower(x.product_name))
        from (select * from public.products where deleted_at is null and availability
              order by popularity desc, lower(product_name) limit 8) x), '[]'::jsonb),
    'discounted', coalesce((select jsonb_agg(public.product_json(x) order by x.popularity desc, lower(x.product_name))
        from (select * from public.products p where p.deleted_at is null and p.availability and public.product_discount_minor(p) > 0
              order by popularity desc, lower(product_name) limit 8) x), '[]'::jsonb),
    'offers', coalesce((select jsonb_agg(public.voucher_json(v) order by v.code) from public.vouchers v
        where v.is_public and v.is_active and (v.expires_at is null or now() < v.expires_at)), '[]'::jsonb));
end $$;
