-- Profiles, measurements, discounts, product administration, feedback,
-- requests, notifications and Cloudinary cleanup.
set check_function_bodies = off;

create function public.user_json(p public.profiles) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email, 'phone', p.phone, 'address', p.address,
    'profileImage', p.profile_image_url, 'profileImagePublicId', p.profile_image_public_id,
    'role', p.role, 'createdAt', p.created_at,
    'measurements', coalesce((select m."values" from public.customer_measurements m where m.user_id = p.id), '{}'::jsonb))
$$;

create function public.my_profile() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles%rowtype;
begin
  select * into p from public.profiles where id = public.require_user();
  if not found then
    raise exception 'Account not found.' using errcode = 'P0001', hint = 'ACCOUNT_NOT_FOUND';
  end if;
  return public.user_json(p);
end $$;

-- Cloudinary assets must live under our cloud and our folders, so a customer
-- cannot point a profile or product at an arbitrary URL.
create function public.cloudinary_url_ok(p_url text, p_public_id text, p_prefix text) returns boolean
language sql stable set search_path = public as $$
  select p_url like 'https://res.cloudinary.com/' || (select value from public.app_settings where key = 'cloudinary_cloud_name') || '/%'
     and p_public_id like p_prefix || '%'
     and p_public_id ~ '^[A-Za-z0-9_/-]{1,160}$'
     and position(p_public_id in p_url) > 0
$$;

create function public.update_my_profile(p_name text, p_phone text, p_address text,
    p_image_url text default null, p_image_public_id text default null, p_clear_image boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public.require_user(); p public.profiles%rowtype;
begin
  if char_length(btrim(coalesce(p_address, ''))) = 0 then
    raise exception 'Delivery address is required' using errcode = 'P0001';
  end if;
  if p_image_url is not null then
    if not public.cloudinary_url_ok(p_image_url, p_image_public_id, 'toptailers/avatars/' || v_uid::text) then
      raise exception 'Invalid profile image.' using errcode = 'P0001', hint = 'IMAGE_INVALID';
    end if;
  end if;
  update public.profiles set name = btrim(p_name), phone = p_phone, address = btrim(p_address),
      profile_image_url = case when p_clear_image then null when p_image_url is not null then p_image_url else profile_image_url end,
      profile_image_public_id = case when p_clear_image then null when p_image_url is not null then p_image_public_id else profile_image_public_id end
   where id = v_uid returning * into p;
  return public.user_json(p);
end $$;

-- Customers set their own; the shop admin may set any customer's.
create function public.set_measurements(p_customer uuid, p_values jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public.require_user(); v_clean jsonb; p public.profiles%rowtype;
begin
  if p_customer <> v_uid and not public.is_admin() then
    raise exception 'You can only change your own measurements.' using errcode = '42501', hint = 'FORBIDDEN';
  end if;
  select * into p from public.profiles where id = p_customer and role = 'customer';
  if not found then
    raise exception 'Customer not found.' using errcode = 'P0001', hint = 'ACCOUNT_NOT_FOUND';
  end if;
  v_clean := public.validate_measurements(p_values);
  insert into public.customer_measurements(user_id, "values", updated_at) values (p_customer, v_clean, now())
  on conflict (user_id) do update set "values" = excluded."values", updated_at = now();
  return public.user_json(p);
end $$;

create function public.admin_list_customers() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return coalesce((
    select jsonb_agg(public.user_json(p) || jsonb_build_object(
        'orderCount', (select count(*) from public.orders o where o.user_id = p.id),
        -- Lifetime Spending: Completed orders with confirmed payment only.
        'lifetimeSpendingMinor', coalesce((select sum(o.total_minor) from public.orders o
            join public.payments pm on pm.order_id = o.id
           where o.user_id = p.id and o.status = 'completed' and pm.status = 'successful'), 0))
        order by p.created_at desc)
    from public.profiles p where p.role = 'customer'), '[]'::jsonb);
end $$;

create function public.customer_discount_json(d public.customer_discounts) returns jsonb language sql stable as $$
  select jsonb_build_object('customerId', d.customer_id, 'kind', d.kind, 'value', d.value, 'active', d.active,
                            'note', d.note, 'updatedAt', d.updated_at)
$$;

create function public.my_customer_discount() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.customer_discounts%rowtype;
begin
  select * into d from public.customer_discounts where customer_id = public.require_user();
  if not found then return null; end if;
  return public.customer_discount_json(d);
end $$;

create function public.admin_list_customer_discounts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return coalesce((select jsonb_agg(public.customer_discount_json(d)) from public.customer_discounts d), '[]'::jsonb);
end $$;

create function public.admin_save_customer_discount(p_customer uuid, p_kind text, p_value integer, p_active boolean, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.customer_discounts%rowtype;
begin
  perform public.require_admin();
  if not exists (select 1 from public.profiles where id = p_customer and role = 'customer') then
    raise exception 'Customer not found.' using errcode = 'P0001', hint = 'ACCOUNT_NOT_FOUND';
  end if;
  if p_kind not in ('percent', 'fixed') then
    raise exception 'Choose a percentage or a fixed amount.' using errcode = 'P0001';
  end if;
  if p_value is null or p_value <= 0 then
    raise exception 'Enter a value greater than 0' using errcode = 'P0001', hint = 'DISCOUNT_INVALID';
  end if;
  if p_kind = 'percent' and p_value > 99 then
    raise exception 'Percentage must be between 1 and 99' using errcode = 'P0001', hint = 'DISCOUNT_INVALID';
  end if;
  insert into public.customer_discounts(customer_id, kind, value, active, note, updated_at)
  values (p_customer, p_kind, p_value, coalesce(p_active, true), btrim(coalesce(p_note, '')), now())
  on conflict (customer_id) do update set kind = excluded.kind, value = excluded.value, active = excluded.active,
        note = excluded.note, updated_at = now()
  returning * into d;
  return public.customer_discount_json(d);
end $$;

create function public.admin_remove_customer_discount(p_customer uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  delete from public.customer_discounts where customer_id = p_customer;
end $$;

create function public.admin_is_code_taken(p_code text, p_except uuid default null) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return exists (select 1 from public.products where code = upper(btrim(coalesce(p_code, ''))) and id is distinct from p_except);
end $$;

create function public.admin_save_product(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_code text := upper(btrim(coalesce(p ->> 'code', '')));
  v_name text := btrim(coalesce(p ->> 'productName', ''));
  v_desc text := btrim(coalesce(p ->> 'description', ''));
  v_price bigint := nullif(p ->> 'priceMinor', '')::bigint;
  v_cat text := p ->> 'category';
  v_unit text; v_d jsonb := p -> 'discount'; v_d_on boolean := false; v_d_kind text; v_d_val integer;
  v_urls jsonb := coalesce(p -> 'imagePaths', '[]'::jsonb); v_pids jsonb := coalesce(p -> 'imagePublicIds', '[]'::jsonb);
  v_colors jsonb := coalesce(p -> 'colors', '[]'::jsonb); v_sizes jsonb := coalesce(p -> 'sizes', '[]'::jsonb);
  i integer; v_row public.products%rowtype; v_old_pop integer; r record;
begin
  perform public.require_admin();
  if v_code = '' then raise exception 'Product code is required' using errcode = 'P0001', hint = 'PRODUCT_INVALID'; end if;
  if char_length(v_code) not between 3 and 24 then raise exception 'Use 3-24 characters' using errcode = 'P0001', hint = 'PRODUCT_INVALID'; end if;
  if v_code !~ '^[A-Z0-9]+(-[A-Z0-9]+)*$' then raise exception 'Use letters, digits and single hyphens only' using errcode = 'P0001', hint = 'PRODUCT_INVALID'; end if;
  if v_name = '' then raise exception 'Product name is required' using errcode = 'P0001', hint = 'PRODUCT_INVALID'; end if;
  if v_desc = '' then raise exception 'Description is required' using errcode = 'P0001', hint = 'PRODUCT_INVALID'; end if;
  if v_price is null or v_price <= 0 then raise exception 'Price must be greater than 0' using errcode = 'P0001', hint = 'PRODUCT_INVALID'; end if;
  if v_price > 1000000000 then raise exception 'Price is too large' using errcode = 'P0001', hint = 'PRODUCT_INVALID'; end if;
  if v_cat is null or v_cat not in ('Fabrics','Readymade','Tailoring','Accessories') then
    raise exception 'Unknown category.' using errcode = 'P0001', hint = 'PRODUCT_INVALID';
  end if;
  v_unit := coalesce(nullif(p ->> 'unit', ''), case v_cat when 'Fabrics' then 'yard' when 'Tailoring' then 'service' else 'piece' end);
  if v_unit not in ('yard', 'piece', 'service') then raise exception 'Unknown unit.' using errcode = 'P0001', hint = 'PRODUCT_INVALID'; end if;

  if v_d is not null and jsonb_typeof(v_d) = 'object' then
    v_d_on := coalesce((v_d ->> 'enabled')::boolean, false);
    v_d_kind := v_d ->> 'kind';
    v_d_val := nullif(v_d ->> 'value', '')::integer;
    if v_d_on then
      if v_d_val is null or v_d_val <= 0 then raise exception 'Enter a value greater than 0' using errcode = 'P0001', hint = 'DISCOUNT_INVALID'; end if;
      if v_d_kind = 'percent' then
        if v_d_val > 99 then raise exception 'Percentage must be between 1 and 99' using errcode = 'P0001', hint = 'DISCOUNT_INVALID'; end if;
      elsif v_d_kind = 'fixed' then
        if v_d_val >= v_price then raise exception 'A fixed discount must be less than the price' using errcode = 'P0001', hint = 'DISCOUNT_INVALID'; end if;
      else
        raise exception 'Choose a percentage or a fixed amount.' using errcode = 'P0001', hint = 'DISCOUNT_INVALID';
      end if;
    elsif v_d_kind is null or v_d_val is null or v_d_val <= 0 or v_d_kind not in ('percent', 'fixed')
          or (v_d_kind = 'percent' and v_d_val > 99) then
      v_d_kind := null; v_d_val := null;    -- keep only sane saved-but-disabled settings
    end if;
  end if;

  if jsonb_typeof(v_urls) <> 'array' or jsonb_typeof(v_pids) <> 'array' or jsonb_array_length(v_urls) <> jsonb_array_length(v_pids) then
    raise exception 'Invalid images.' using errcode = 'P0001', hint = 'IMAGE_INVALID';
  end if;
  if jsonb_array_length(v_urls) > 4 then raise exception 'You can add up to 4 images.' using errcode = 'P0001', hint = 'IMAGE_INVALID'; end if;
  for i in 0..jsonb_array_length(v_urls) - 1 loop
    if not public.cloudinary_url_ok(v_urls ->> i, v_pids ->> i, 'toptailers/products/') then
      raise exception 'Invalid product image.' using errcode = 'P0001', hint = 'IMAGE_INVALID';
    end if;
    if exists (select 1 from public.product_images pi where pi.public_id = v_pids ->> i and pi.product_id is distinct from v_id) then
      raise exception 'An image is already used by another product.' using errcode = 'P0001', hint = 'IMAGE_INVALID';
    end if;
  end loop;

  begin
    if v_id is null then
      insert into public.products(code, product_name, description, price_minor, category, availability, unit,
          requires_measurements, is_featured, popularity, specs, discount_enabled, discount_kind, discount_value)
      values (v_code, v_name, v_desc, v_price, v_cat, coalesce((p ->> 'availability')::boolean, true), v_unit,
          coalesce((p ->> 'requiresMeasurements')::boolean, false), coalesce((p ->> 'isFeatured')::boolean, false),
          coalesce((p ->> 'popularity')::integer, 0), coalesce(p -> 'specs', '{}'::jsonb), v_d_on, v_d_kind, v_d_val)
      returning * into v_row;
    else
      select popularity into v_old_pop from public.products where id = v_id and deleted_at is null;
      if not found then raise exception 'This product no longer exists.' using errcode = 'P0001', hint = 'PRODUCT_NOT_FOUND'; end if;
      update public.products set code = v_code, product_name = v_name, description = v_desc, price_minor = v_price,
          category = v_cat, availability = coalesce((p ->> 'availability')::boolean, availability), unit = v_unit,
          requires_measurements = coalesce((p ->> 'requiresMeasurements')::boolean, requires_measurements),
          is_featured = coalesce((p ->> 'isFeatured')::boolean, is_featured),
          popularity = coalesce((p ->> 'popularity')::integer, v_old_pop),
          specs = coalesce(p -> 'specs', specs), discount_enabled = v_d_on, discount_kind = v_d_kind, discount_value = v_d_val
       where id = v_id returning * into v_row;
    end if;
  exception when unique_violation then
    raise exception 'Product code % is already used by another product.', v_code using errcode = 'P0001', hint = 'PRODUCT_CODE_TAKEN';
  end;

  -- images: replaced images are queued for Cloudinary cleanup by a trigger
  delete from public.product_images where product_id = v_row.id and public_id <> all (array(select jsonb_array_elements_text(v_pids)));
  update public.product_images set position = position + 10 where product_id = v_row.id;
  for i in 0..jsonb_array_length(v_urls) - 1 loop
    insert into public.product_images(product_id, url, public_id, position) values (v_row.id, v_urls ->> i, v_pids ->> i, i)
    on conflict (public_id) do update set position = excluded.position, url = excluded.url;
  end loop;

  delete from public.product_variants where product_id = v_row.id;
  i := 0;
  for r in select btrim(c ->> 'name') as name, (c ->> 'argb')::bigint as argb from jsonb_array_elements(v_colors) c loop
    if r.name is null or r.name = '' then continue; end if;
    insert into public.product_variants(product_id, type, name, argb, position) values (v_row.id, 'color', r.name, coalesce(r.argb, 10395294), i)
    on conflict do nothing;
    i := i + 1;
  end loop;
  i := 0;
  for r in select btrim(s) as name from jsonb_array_elements_text(v_sizes) s loop
    if r.name = '' then continue; end if;
    insert into public.product_variants(product_id, type, name, position) values (v_row.id, 'size', r.name, i) on conflict do nothing;
    i := i + 1;
  end loop;

  select * into v_row from public.products where id = v_row.id;
  return public.product_json(v_row);
end $$;

-- Soft delete: the code stays reserved and existing orders are untouched.
create function public.admin_delete_product(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.products set deleted_at = now() where id = p_id and deleted_at is null;
end $$;

create function public.admin_save_voucher(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_code text := upper(btrim(coalesce(p ->> 'code', ''))); v_kind text := p ->> 'kind';
  v_val integer := nullif(p ->> 'value', '')::integer; v_cats text[]; v public.vouchers%rowtype;
begin
  perform public.require_admin();
  if v_code !~ '^[A-Z0-9_-]{3,24}$' then raise exception 'Voucher codes use letters, numbers, - or _ only' using errcode = 'P0001'; end if;
  if v_kind not in ('percent', 'fixed') then raise exception 'Choose a percentage or a fixed amount.' using errcode = 'P0001'; end if;
  if v_val is null or v_val <= 0 then raise exception 'Enter a value greater than 0' using errcode = 'P0001'; end if;
  if v_kind = 'percent' and v_val > 99 then raise exception 'Percentage must be between 1 and 99' using errcode = 'P0001'; end if;
  v_cats := coalesce(array(select jsonb_array_elements_text(coalesce(p -> 'categories', '[]'::jsonb))), '{}');
  if exists (select 1 from unnest(v_cats) c where c not in ('Fabrics','Readymade','Tailoring','Accessories')) then
    raise exception 'Unknown category.' using errcode = 'P0001';
  end if;
  insert into public.vouchers(code, title, kind, value, expires_at, categories, is_active, is_public)
  values (v_code, coalesce(nullif(btrim(p ->> 'title'), ''), v_code), v_kind, v_val, nullif(p ->> 'expiresAt', '')::timestamptz, v_cats,
          coalesce((p ->> 'isActive')::boolean, true), coalesce((p ->> 'isPublic')::boolean, false))
  on conflict (code) do update set title = excluded.title, kind = excluded.kind, value = excluded.value,
        expires_at = excluded.expires_at, categories = excluded.categories, is_active = excluded.is_active, is_public = excluded.is_public
  returning * into v;
  return public.voucher_json(v);
end $$;

create function public.admin_set_voucher_active(p_code text, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.vouchers set is_active = p_active where code = upper(btrim(p_code));
end $$;

create function public.admin_list_vouchers() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return coalesce((select jsonb_agg(public.voucher_json(v) order by v.code) from public.vouchers v), '[]'::jsonb);
end $$;

create function public.feedback_json(f public.feedback, p_name text, p_user text) returns jsonb language sql stable as $$
  select jsonb_build_object('id', f.id, 'orderId', f.order_id, 'productId', f.product_id, 'productName', f.product_name,
    'userId', p_user, 'userName', p_name, 'rating', f.rating, 'comment', f.comment, 'createdAt', f.created_at)
$$;

create function public.submit_feedback(p_order_id uuid, p_product_id uuid, p_rating integer, p_comment text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public.require_user(); o public.orders%rowtype; it public.order_items%rowtype; f public.feedback%rowtype; v_name text;
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'Choose a rating from 1 to 5.' using errcode = 'P0001', hint = 'FEEDBACK_INVALID'; end if;
  if char_length(btrim(coalesce(p_comment, ''))) < 5 then raise exception 'Please write at least a few words of feedback.' using errcode = 'P0001', hint = 'FEEDBACK_INVALID'; end if;
  select * into o from public.orders where id = p_order_id;
  if not found then raise exception 'Order not found.' using errcode = 'P0001', hint = 'ORDER_NOT_FOUND'; end if;
  if o.user_id <> v_uid then raise exception 'This is not your order.' using errcode = '42501', hint = 'FORBIDDEN'; end if;
  if o.status <> 'completed' then raise exception 'You can leave feedback after the order is Completed.' using errcode = 'P0001', hint = 'FEEDBACK_NOT_ELIGIBLE'; end if;
  select * into it from public.order_items where order_id = o.id and product_id = p_product_id limit 1;
  if not found then raise exception 'This product is not part of that order.' using errcode = 'P0001', hint = 'FEEDBACK_NOT_ELIGIBLE'; end if;
  begin
    insert into public.feedback(order_id, product_id, product_name, user_id, rating, comment)
    values (o.id, p_product_id, it.product_name, v_uid, p_rating, btrim(p_comment)) returning * into f;
  exception when unique_violation then
    raise exception 'You have already reviewed this item.' using errcode = 'P0001', hint = 'FEEDBACK_DUPLICATE';
  end;
  select name into v_name from public.profiles where id = v_uid;
  return public.feedback_json(f, v_name, v_uid::text);
end $$;

create function public.feedback_for_product(p_product_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := public.require_user();
begin
  return coalesce((select jsonb_agg(public.feedback_json(f, split_part(pr.name, ' ', 1), case when f.user_id = v_uid then f.user_id::text else '' end)
                                     order by f.created_at desc)
                    from public.feedback f join public.profiles pr on pr.id = f.user_id where f.product_id = p_product_id), '[]'::jsonb);
end $$;

create function public.my_feedback() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := public.require_user();
begin
  return coalesce((select jsonb_agg(public.feedback_json(f, pr.name, f.user_id::text) order by f.created_at desc)
                    from public.feedback f join public.profiles pr on pr.id = f.user_id where f.user_id = v_uid), '[]'::jsonb);
end $$;

create function public.admin_all_feedback() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return coalesce((select jsonb_agg(public.feedback_json(f, pr.name, f.user_id::text) order by f.created_at desc)
                    from public.feedback f join public.profiles pr on pr.id = f.user_id), '[]'::jsonb);
end $$;

create function public.suggestion_json(s public.suggestions, p_name text) returns jsonb language sql stable as $$
  select jsonb_build_object('id', s.id, 'userId', s.user_id, 'userName', p_name, 'title', s.title, 'details', s.details,
                            'status', s.status, 'createdAt', s.created_at)
$$;
create function public.restock_json(r public.restock_requests, p_name text) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', r.id, 'userId', r.user_id, 'userName', p_name, 'productId', r.product_id,
    'productCode', (select code from public.products where id = r.product_id),
    'productName', (select product_name from public.products where id = r.product_id),
    'reason', r.reason, 'status', r.status, 'createdAt', r.created_at)
$$;

create function public.submit_suggestion(p_title text, p_details text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public.require_user(); s public.suggestions%rowtype; v_name text;
begin
  if char_length(btrim(coalesce(p_title, ''))) < 3 then
    raise exception 'Please enter what you would like us to stock.' using errcode = 'P0001', hint = 'REQUEST_INVALID';
  end if;
  insert into public.suggestions(user_id, title, details) values (v_uid, btrim(p_title), btrim(coalesce(p_details, ''))) returning * into s;
  select name into v_name from public.profiles where id = v_uid;
  return public.suggestion_json(s, v_name);
end $$;

create function public.submit_restock(p_product_id uuid, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := public.require_user(); r public.restock_requests%rowtype; v_name text;
begin
  if not exists (select 1 from public.products where id = p_product_id and deleted_at is null) then
    raise exception 'Product not found.' using errcode = 'P0001', hint = 'PRODUCT_NOT_FOUND';
  end if;
  begin
    insert into public.restock_requests(user_id, product_id, reason) values (v_uid, p_product_id, btrim(coalesce(p_reason, ''))) returning * into r;
  exception when unique_violation then
    raise exception 'You already have an open restock request for this product.' using errcode = 'P0001', hint = 'REQUEST_DUPLICATE';
  end;
  select name into v_name from public.profiles where id = v_uid;
  return public.restock_json(r, v_name);
end $$;

create function public.my_suggestions() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := public.require_user();
begin
  return coalesce((select jsonb_agg(public.suggestion_json(s, pr.name) order by s.created_at desc)
    from public.suggestions s join public.profiles pr on pr.id = s.user_id where s.user_id = v_uid), '[]'::jsonb);
end $$;
create function public.my_restocks() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := public.require_user();
begin
  return coalesce((select jsonb_agg(public.restock_json(r, pr.name) order by r.created_at desc)
    from public.restock_requests r join public.profiles pr on pr.id = r.user_id where r.user_id = v_uid), '[]'::jsonb);
end $$;
create function public.admin_all_suggestions() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return coalesce((select jsonb_agg(public.suggestion_json(s, pr.name) order by s.created_at desc)
    from public.suggestions s join public.profiles pr on pr.id = s.user_id), '[]'::jsonb);
end $$;
create function public.admin_all_restocks() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return coalesce((select jsonb_agg(public.restock_json(r, pr.name) order by r.created_at desc)
    from public.restock_requests r join public.profiles pr on pr.id = r.user_id), '[]'::jsonb);
end $$;
create function public.set_suggestion_status(p_id uuid, p_status text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if p_status not in ('received','underReview','planned','declined') then raise exception 'Unknown status.' using errcode = 'P0001'; end if;
  update public.suggestions set status = p_status where id = p_id;
  if not found then raise exception 'Request not found.' using errcode = 'P0001', hint = 'REQUEST_NOT_FOUND'; end if;
end $$;
create function public.set_restock_status(p_id uuid, p_status text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if p_status not in ('received','underReview','planned','declined') then raise exception 'Unknown status.' using errcode = 'P0001'; end if;
  update public.restock_requests set status = p_status where id = p_id;
  if not found then raise exception 'Request not found.' using errcode = 'P0001', hint = 'REQUEST_NOT_FOUND'; end if;
end $$;

-- Visible = created within the last 30 days; EXACTLY 30 days old is still
-- visible. Hiding is not deletion: purge_old_notifications() deletes.
create function public.visible_notifications() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := public.require_user();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'userId', n.user_id, 'title', n.title, 'body', n.body,
            'createdAt', n.created_at, 'read', n.read) order by n.created_at desc)
          from public.notifications n where n.user_id = v_uid and now() - n.created_at <= interval '30 days'), '[]'::jsonb);
end $$;

create function public.mark_notifications_read() returns void language plpgsql security definer set search_path = public as $$
begin
  update public.notifications set read = true where user_id = public.require_user() and not read;
end $$;

create function public.purge_old_notifications() returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  delete from public.notifications where now() - created_at > interval '30 days';
  get diagnostics n = row_count;
  return n;
end $$;

-- Assets still referenced by an order item snapshot are kept so order history
-- never shows a broken image.
create function public.claim_cloudinary_cleanup(p_limit integer default 20) returns text[]
language plpgsql security definer set search_path = public as $$
declare ids text[];
begin
  delete from public.image_cleanup_queue q
   where exists (select 1 from public.order_items oi where oi.image_url like '%' || public.escape_like(q.public_id) || '%')
      or exists (select 1 from public.product_images pi where pi.public_id = q.public_id)
      or exists (select 1 from public.profiles pr where pr.profile_image_public_id = q.public_id);
  select coalesce(array_agg(public_id), '{}') into ids
    from (select public_id from public.image_cleanup_queue where attempts < 5 order by queued_at limit greatest(p_limit, 1)) s;
  return ids;
end $$;
create function public.complete_cloudinary_cleanup(p_ids text[]) returns void language sql security definer set search_path = public as $$
  delete from public.image_cleanup_queue where public_id = any (p_ids)
$$;
create function public.fail_cloudinary_cleanup(p_id text, p_error text) returns void language sql security definer set search_path = public as $$
  update public.image_cleanup_queue set attempts = attempts + 1, last_error = left(p_error, 300) where public_id = p_id
$$;

-- Run from the SQL editor / service role ONLY (see docs). Never reachable by clients.
create function public.provision_admin(p_email text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set role = 'admin' where email = lower(btrim(p_email));
  if not found then
    raise exception 'No account with that email. Register it first, then run this again.';
  end if;
end $$;

-- Nightly purge when pg_cron is available (Supabase: enable it in the dashboard).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('purge-old-notifications', '17 21 * * *', 'select public.purge_old_notifications()');
  end if;
exception when others then
  raise notice 'pg_cron not scheduled: %', sqlerrm;
end $$;
