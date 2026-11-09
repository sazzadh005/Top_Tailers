-- Orders, cancellation, payments and admin operations (all transactional,
-- all authorization checks inside the functions).
set check_function_bodies = off;

create function public.require_user() returns uuid language plpgsql stable as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in.' using errcode = '28000', hint = 'UNAUTHENTICATED';
  end if;
  return auth.uid();
end $$;

create function public.require_admin() returns uuid language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in.' using errcode = '28000', hint = 'UNAUTHENTICATED';
  end if;
  if not public.is_admin() then
    raise exception 'Only the shop admin can do this.' using errcode = '42501', hint = 'FORBIDDEN';
  end if;
  return auth.uid();
end $$;

create function public.payment_status_label(s text) returns text language sql immutable as $$
  select case s when 'successful' then 'Paid' else initcap(s) end
$$;

create function public.notify(p_user uuid, p_title text, p_body text) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications(user_id, title, body) values (p_user, p_title, p_body)
$$;

create function public.order_json(o public.orders) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', o.id, 'reference', o.reference, 'userId', o.user_id, 'customerName', o.customer_name,
    'contactPhone', o.contact_phone, 'shippingAddress', o.shipping_address, 'note', o.note,
    'measurements', (select jsonb_build_object('source', m.source, 'forPerson', m.for_person,
                      'capturedAt', m.captured_at, 'values', m."values")
                       from public.order_measurements m where m.order_id = o.id),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'productId', i.product_id, 'productCode', i.product_code, 'productName', i.product_name,
        'listUnitMinor', i.list_unit_minor, 'unitMinor', i.unit_minor, 'quantity', i.quantity,
        'imagePath', i.image_url, 'category', i.category, 'unit', i.unit,
        'colorName', i.color_name, 'size', i.size) order by i.line_no)
        from public.order_items i where i.order_id = o.id), '[]'::jsonb),
    'subtotalMinor', o.subtotal_minor, 'productDiscountMinor', o.product_discount_minor,
    'customerDiscountMinor', o.customer_discount_minor, 'voucherDiscountMinor', o.voucher_discount_minor,
    'deliveryMinor', o.delivery_minor, 'totalMinor', o.total_minor, 'voucherCode', o.voucher_code,
    'payment', (select jsonb_build_object('id', pm.id, 'method', pm.method, 'status', pm.status,
                  'amountMinor', pm.amount_minor, 'provider', pm.provider,
                  'transactionRef', pm.transaction_ref, 'updatedAt', pm.updated_at)
                  from public.payments pm where pm.order_id = o.id),
    'status', o.status, 'orderDate', o.order_date,
    'history', coalesce((select jsonb_agg(jsonb_build_object('status', e.status, 'at', e.at) order by e.at, e.id)
                           from public.order_events e where e.order_id = o.id), '[]'::jsonb),
    'cancellation', (select jsonb_build_object('cancelledBy', c.cancelled_by, 'cancelledByName', c.cancelled_by_name,
                       'reason', c.reason, 'note', c.note, 'cancelledAt', c.cancelled_at)
                       from public.cancellations c where c.order_id = o.id))
$$;

-- Display reference only. The immutable identifier is the uuid `id`.
create function public.next_order_reference() returns text language plpgsql as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  s text; i integer; ref text; tries integer := 0;
begin
  loop
    s := '';
    for i in 1..4 loop s := s || substr(alphabet, 1 + floor(random() * 32)::integer, 1); end loop;
    ref := 'TTF-' || to_char(timezone('Asia/Dhaka', now()), 'YYMMDD') || '-' || s;
    exit when not exists (select 1 from public.orders where reference = ref);
    tries := tries + 1;
    if tries > 25 then raise exception 'Could not allocate an order reference.'; end if;
  end loop;
  return ref;
end $$;

-- Never trusts client prices: product, variants, availability, discounts,
-- voucher and the final total are all recomputed here. Safe to retry with the
-- same idempotency key.
create function public.place_order(p_request jsonb, p_idempotency_key text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := public.require_user();
  v_profile public.profiles%rowtype;
  v_hash text;
  v_existing public.idempotency_keys%rowtype;
  v_items jsonb := p_request -> 'items';
  v_pricing jsonb; v_voucher text := nullif(btrim(p_request ->> 'voucherCode'), '');
  v_phone text; v_addr text := btrim(coalesce(p_request ->> 'shippingAddress', ''));
  v_note text := btrim(coalesce(p_request ->> 'note', ''));
  v_method text := p_request ->> 'paymentMethod';
  v_expected bigint := nullif(p_request ->> 'expectedTotalMinor', '')::bigint;
  v_meas jsonb := p_request -> 'measurements';
  v_meas_values jsonb; v_meas_source text; v_for text; v_needs_meas boolean := false;
  r record; prod public.products%rowtype; v_order public.orders%rowtype; n integer := 0;
begin
  select * into v_profile from public.profiles where id = v_uid;
  if not found or v_profile.role <> 'customer' then
    raise exception 'Only customers can place orders.' using errcode = '42501', hint = 'FORBIDDEN';
  end if;

  if p_idempotency_key is not null then
    if char_length(p_idempotency_key) not between 8 and 64 then
      raise exception 'Invalid idempotency key.' using errcode = 'P0001';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(v_uid::text || p_idempotency_key, 0));
    v_hash := encode(sha256(convert_to(p_request::text, 'utf8')), 'hex');
    select * into v_existing from public.idempotency_keys where user_id = v_uid and key = p_idempotency_key;
    if found then
      if v_existing.request_hash <> v_hash then
        raise exception 'This request key was already used for a different order.' using errcode = 'P0001', hint = 'IDEMPOTENCY_CONFLICT';
      end if;
      return public.order_json((select o from public.orders o where o.id = v_existing.order_id));
    end if;
  end if;

  if v_items is null or jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    raise exception 'Your cart is empty.' using errcode = 'P0001', hint = 'CART_EMPTY';
  end if;
  if jsonb_array_length(v_items) > 50 then
    raise exception 'Too many cart lines.' using errcode = 'P0001';
  end if;

  v_phone := public.normalize_phone(p_request ->> 'contactPhone');
  if v_phone is null then
    raise exception 'Contact number: Enter a valid mobile number (e.g. 01712345678)' using errcode = 'P0001', hint = 'CONTACT_INVALID';
  end if;
  if v_addr = '' then
    raise exception 'Delivery address is required' using errcode = 'P0001', hint = 'ADDRESS_INVALID';
  elsif char_length(v_addr) < 8 then
    raise exception 'Please enter a more complete address' using errcode = 'P0001', hint = 'ADDRESS_INVALID';
  end if;
  if char_length(v_note) > 300 then
    raise exception 'Please keep notes under 300 characters' using errcode = 'P0001';
  end if;
  if v_method is null or v_method not in ('cod', 'online') then
    raise exception 'Choose Cash on Delivery or Online Payment.' using errcode = 'P0001';
  end if;
  if v_expected is null then
    raise exception 'Missing expected total.' using errcode = 'P0001';
  end if;

  for r in select (l ->> 'productId')::uuid as pid, (l ->> 'quantity')::integer as qty,
                  nullif(l ->> 'colorName', '') as color, nullif(l ->> 'size', '') as size
             from jsonb_array_elements(v_items) l loop
    select * into prod from public.products where id = r.pid and deleted_at is null;
    if not found or not prod.availability then
      raise exception '"%" is no longer available. Please update your cart.', coalesce(prod.product_name, 'An item')
        using errcode = 'P0001', hint = 'PRODUCT_UNAVAILABLE';
    end if;
    if r.qty is null or r.qty < 1 or r.qty > 20 then
      raise exception 'Invalid quantity for "%".', prod.product_name using errcode = 'P0001', hint = 'QUANTITY_INVALID';
    end if;
    if exists (select 1 from public.product_variants v where v.product_id = prod.id and v.type = 'color') then
      if r.color is null then
        raise exception 'Please choose a colour for "%".', prod.product_name using errcode = 'P0001', hint = 'VARIANT_REQUIRED';
      elsif not exists (select 1 from public.product_variants v where v.product_id = prod.id and v.type = 'color' and v.name = r.color) then
        raise exception 'Selected colour is no longer offered for "%".', prod.product_name using errcode = 'P0001', hint = 'VARIANT_INVALID';
      end if;
    elsif r.color is not null then
      raise exception 'Selected colour is no longer offered for "%".', prod.product_name using errcode = 'P0001', hint = 'VARIANT_INVALID';
    end if;
    if exists (select 1 from public.product_variants v where v.product_id = prod.id and v.type = 'size') then
      if r.size is null then
        raise exception 'Please choose a size for "%".', prod.product_name using errcode = 'P0001', hint = 'VARIANT_REQUIRED';
      elsif not exists (select 1 from public.product_variants v where v.product_id = prod.id and v.type = 'size' and v.name = r.size) then
        raise exception 'Selected size is no longer offered for "%".', prod.product_name using errcode = 'P0001', hint = 'VARIANT_INVALID';
      end if;
    elsif r.size is not null then
      raise exception 'Selected size is no longer offered for "%".', prod.product_name using errcode = 'P0001', hint = 'VARIANT_INVALID';
    end if;
    if prod.requires_measurements then v_needs_meas := true; end if;
  end loop;

  if v_needs_meas or (v_meas is not null and jsonb_typeof(v_meas) = 'object') then
    v_meas_source := coalesce(v_meas ->> 'source', '');
    if v_meas_source not in ('profile', 'enteredForOrder', 'otherPerson') then
      if v_needs_meas then
        raise exception 'Measurements are required for tailoring services.' using errcode = 'P0001', hint = 'MEASUREMENTS_REQUIRED';
      end if;
      v_meas_source := null;
    end if;
    if v_meas_source = 'profile' then
      select "values" into v_meas_values from public.customer_measurements where user_id = v_uid;
      v_meas_values := coalesce(v_meas_values, '{}'::jsonb);   -- server copy, not client data
      if v_meas_values = '{}'::jsonb and v_needs_meas then
        raise exception 'You have no saved measurements. Enter measurements for this order instead.' using errcode = 'P0001', hint = 'MEASUREMENTS_REQUIRED';
      end if;
    elsif v_meas_source is not null then
      v_meas_values := public.validate_measurements(v_meas -> 'values');
      if v_meas_values = '{}'::jsonb and v_needs_meas then
        raise exception 'Enter at least one measurement for this tailoring order.' using errcode = 'P0001', hint = 'MEASUREMENTS_REQUIRED';
      end if;
      if v_meas_source = 'otherPerson' then
        v_for := btrim(coalesce(v_meas ->> 'forPerson', ''));
        if char_length(v_for) < 2 then
          raise exception 'Please enter the name of the person measured.' using errcode = 'P0001', hint = 'MEASUREMENTS_REQUIRED';
        end if;
      end if;
    end if;
  end if;

  v_pricing := public.compute_pricing(v_items, v_voucher, v_uid);
  if v_voucher is not null and v_pricing ->> 'voucherIssue' is not null then
    raise exception '%', v_pricing ->> 'voucherNote' using errcode = 'P0001', hint = 'VOUCHER_INVALID';
  end if;
  if (v_pricing ->> 'totalMinor')::bigint <> v_expected then
    raise exception 'Prices or discounts changed since you reviewed your cart. Please check the new total and try again.'
      using errcode = 'P0001', hint = 'PRICE_CHANGED';
  end if;

  insert into public.orders(reference, user_id, customer_name, contact_phone, shipping_address, note,
      subtotal_minor, product_discount_minor, customer_discount_minor, voucher_discount_minor,
      delivery_minor, total_minor, voucher_code)
  values (public.next_order_reference(), v_uid, v_profile.name, v_phone, v_addr, v_note,
      (v_pricing ->> 'subtotalMinor')::bigint, (v_pricing ->> 'productDiscountMinor')::bigint,
      (v_pricing ->> 'customerDiscountMinor')::bigint, (v_pricing ->> 'voucherDiscountMinor')::bigint,
      (v_pricing ->> 'deliveryMinor')::bigint, (v_pricing ->> 'totalMinor')::bigint,
      v_pricing ->> 'voucherCode')
  returning * into v_order;

  for r in select (l ->> 'productId')::uuid as pid, (l ->> 'quantity')::integer as qty,
                  nullif(l ->> 'colorName', '') as color, nullif(l ->> 'size', '') as size
             from jsonb_array_elements(v_items) l loop
    select * into prod from public.products where id = r.pid;
    n := n + 1;
    insert into public.order_items(order_id, line_no, product_id, product_code, product_name, list_unit_minor,
        unit_minor, quantity, image_url, category, unit, color_name, size)
    values (v_order.id, n, prod.id, prod.code, prod.product_name, prod.price_minor,
        prod.price_minor - public.product_discount_minor(prod)::integer, r.qty,
        (select i.url from public.product_images i where i.product_id = prod.id order by i.position limit 1),
        prod.category, prod.unit, r.color, r.size);
  end loop;

  if v_meas_source is not null and v_meas_values is not null and v_meas_values <> '{}'::jsonb then
    insert into public.order_measurements(order_id, source, for_person, "values")
    values (v_order.id, v_meas_source, v_for, v_meas_values);
  end if;

  insert into public.payments(order_id, method, amount_minor, provider)
  values (v_order.id, v_method, v_order.total_minor, case when v_method = 'cod' then 'none' else 'aamarpay' end);

  perform public.notify(v_uid, 'Order placed',
    'Your order ' || v_order.reference || ' was received and is waiting for confirmation.');

  if p_idempotency_key is not null then
    insert into public.idempotency_keys(user_id, key, request_hash, order_id)
    values (v_uid, p_idempotency_key, v_hash, v_order.id);
  end if;

  return public.order_json(v_order);
end $$;

create function public.cancel_order(p_order_id uuid, p_reason text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := public.require_user();
  v_admin boolean := public.is_admin();
  v_name text; o public.orders%rowtype; v_paid boolean; v_reason text := btrim(coalesce(p_reason, ''));
  v_note text := btrim(coalesce(p_note, ''));
begin
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.' using errcode = 'P0001', hint = 'ORDER_NOT_FOUND';
  end if;
  if o.status = 'cancelled' then
    raise exception 'This order has already been cancelled.' using errcode = 'P0001', hint = 'ORDER_ALREADY_CANCELLED';
  end if;
  if v_reason = '' then
    raise exception 'Please give a cancellation reason.' using errcode = 'P0001', hint = 'REASON_REQUIRED';
  end if;
  if v_reason = 'Other' and char_length(v_note) < 5 then
    raise exception 'Please describe the reason.' using errcode = 'P0001', hint = 'REASON_REQUIRED';
  end if;
  if v_admin then
    if o.status not in ('pending', 'confirmed') then
      raise exception 'Only Pending or Confirmed orders can be cancelled.' using errcode = 'P0001', hint = 'ORDER_NOT_CANCELLABLE';
    end if;
  else
    if o.user_id <> v_uid then
      raise exception 'You can only cancel your own orders.' using errcode = '42501', hint = 'FORBIDDEN';
    end if;
    if o.status <> 'pending' then
      raise exception 'You can cancel an order only while it is Pending.' using errcode = 'P0001', hint = 'ORDER_NOT_CANCELLABLE';
    end if;
  end if;

  select name into v_name from public.profiles where id = v_uid;
  select (status = 'successful') into v_paid from public.payments where order_id = o.id;

  insert into public.cancellations(order_id, cancelled_by, cancelled_by_user, cancelled_by_name, reason, note, paid_at_cancellation)
  values (o.id, case when v_admin then 'shopAdmin' else 'customer' end, v_uid, v_name, v_reason, v_note, coalesce(v_paid, false));

  update public.orders set status = 'cancelled' where id = o.id returning * into o;
  update public.payments set status = 'cancelled' where order_id = o.id and method = 'online' and status = 'pending';
  update public.payment_attempts set status = 'cancelled' where order_id = o.id and status = 'initiated';
  if coalesce(v_paid, false) then
    update public.payments set needs_review = true, review_reason = 'Order cancelled after payment; refund handling is not defined.'
     where order_id = o.id;
  end if;

  perform public.notify(o.user_id, 'Order cancelled',
    case when v_admin then 'Your order ' || o.reference || ' was cancelled by the shop. Reason: ' || v_reason || '.'
         else 'Your order ' || o.reference || ' has been cancelled.' end);
  return public.order_json(o);
end $$;

create function public.update_order_status(p_order_id uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype;
begin
  perform public.require_admin();
  if p_status = 'cancelled' then
    raise exception 'Use the cancel action to cancel an order.' using errcode = 'P0001';
  end if;
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.' using errcode = 'P0001', hint = 'ORDER_NOT_FOUND';
  end if;
  if not ((o.status = 'pending' and p_status = 'confirmed') or (o.status = 'confirmed' and p_status = 'processing')
          or (o.status = 'processing' and p_status = 'completed')) then
    raise exception 'An order cannot move from % to %.', public.status_label(o.status), public.status_label(coalesce(p_status, '?'))
      using errcode = 'P0001', hint = 'ORDER_INVALID_TRANSITION';
  end if;
  update public.orders set status = p_status where id = o.id returning * into o;
  -- Cash on delivery is collected on delivery, so completing confirms payment.
  if p_status = 'completed' then
    update public.payments set status = 'successful' where order_id = o.id and method = 'cod' and status <> 'successful';
  end if;
  perform public.notify(o.user_id, 'Order ' || public.status_label(p_status),
    case when p_status = 'completed'
         then 'Your order ' || o.reference || ' is Completed. Share your feedback from the order page.'
         else 'Your order ' || o.reference || ' is now ' || public.status_label(p_status) || '.' end);
  return public.order_json(o);
end $$;

create function public.get_order(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.orders%rowtype;
begin
  perform public.require_user();
  select * into o from public.orders where id = p_id and (user_id = auth.uid() or public.is_admin());
  if not found then
    raise exception 'Order not found.' using errcode = 'P0001', hint = 'ORDER_NOT_FOUND';
  end if;
  return public.order_json(o);
end $$;

-- Same matching as the app's OrderSearch. Scope comes from the caller's
-- identity, never from a parameter.
create function public.search_orders(
  p_text text default '', p_status text default null, p_payment_status text default null,
  p_from date default null, p_to date default null, p_limit integer default 100, p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := public.require_user(); v_admin boolean := public.is_admin();
  v_tokens text[]; v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_start timestamptz; v_end timestamptz;
begin
  if char_length(coalesce(p_text, '')) > 60 then
    raise exception 'Search text is too long' using errcode = 'P0001', hint = 'SEARCH_INVALID';
  end if;
  if p_from is not null and p_to is not null and p_from > p_to then
    raise exception 'The start date must be before the end date' using errcode = 'P0001', hint = 'SEARCH_INVALID';
  end if;
  if p_status is not null and p_status not in ('pending','confirmed','processing','completed','cancelled') then
    raise exception 'Unknown order status.' using errcode = 'P0001';
  end if;
  if p_payment_status is not null and p_payment_status not in ('pending','successful','failed','cancelled') then
    raise exception 'Unknown payment status.' using errcode = 'P0001';
  end if;
  v_tokens := array(select t from unnest(regexp_split_to_array(lower(btrim(coalesce(p_text, ''))), '\s+')) t where t <> '');
  if p_from is not null then v_start := p_from::timestamp at time zone 'Asia/Dhaka'; end if;
  if p_to is not null then v_end := (p_to + 1)::timestamp at time zone 'Asia/Dhaka'; end if;

  return coalesce((
    select jsonb_agg(public.order_json(x) order by x.order_date desc)
    from (
      select o.* from public.orders o
      join public.payments pm on pm.order_id = o.id
      where (v_admin or o.user_id = v_uid)
        and (p_status is null or o.status = p_status)
        and (p_payment_status is null or pm.status = p_payment_status)
        and (v_start is null or o.order_date >= v_start)
        and (v_end is null or o.order_date < v_end)
        and not exists (
          select 1 from unnest(v_tokens) tok
          where (' ' || lower(o.id::text) || ' ' || lower(o.reference) || ' ' || o.contact_phone || ' '
                 || regexp_replace(o.contact_phone, '\D', '', 'g') || ' ' || lower(public.status_label(o.status)) || ' '
                 || lower(public.payment_status_label(pm.status)) || ' '
                 || lower(case pm.method when 'cod' then 'Cash on Delivery' else 'Online Payment' end) || ' '
                 || lower(case when pm.method = 'cod' then (case when pm.status = 'successful' then 'Paid on delivery' else 'Pay on delivery' end)
                               else public.payment_status_label(pm.status) end) || ' '
                 || case when v_admin then lower(o.customer_name) else '' end || ' '
                 || coalesce((select string_agg(lower(i.product_name || ' ' || i.product_code), ' ')
                                from public.order_items i where i.order_id = o.id), ''))
                not like '%' || public.escape_like(tok) || '%' escape '\')
      order by o.order_date desc
      limit v_limit offset greatest(coalesce(p_offset, 0), 0)
    ) x), '[]'::jsonb);
end $$;

-- Step 1 (called with the CUSTOMER's JWT by the payments-initiate function):
-- creates a pending attempt. The amount comes from the stored order, never
-- from the client.
create function public.start_payment_attempt(p_order_id uuid, p_idempotency_key text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := public.require_user(); o public.orders%rowtype; pm public.payments%rowtype;
  a public.payment_attempts%rowtype; v_profile public.profiles%rowtype;
begin
  perform public.check_rate_limit('pay-start', 10);
  select * into o from public.orders where id = p_order_id for update;
  if not found or o.user_id <> v_uid then
    raise exception 'Order not found.' using errcode = 'P0001', hint = 'ORDER_NOT_FOUND';
  end if;
  select * into pm from public.payments where order_id = o.id for update;
  if pm.method <> 'online' then
    raise exception 'This order is Cash on Delivery.' using errcode = 'P0001', hint = 'PAYMENT_NOT_ONLINE';
  end if;
  if o.status = 'cancelled' then
    raise exception 'This order was cancelled.' using errcode = 'P0001', hint = 'ORDER_CANCELLED';
  end if;
  if pm.status = 'successful' then
    raise exception 'This order is already paid.' using errcode = 'P0001', hint = 'PAYMENT_ALREADY_PAID';
  end if;
  if o.total_minor <= 0 then
    raise exception 'Nothing to pay for this order.' using errcode = 'P0001';
  end if;

  if p_idempotency_key is not null then
    select * into a from public.payment_attempts where order_id = o.id and idempotency_key = p_idempotency_key;
  end if;
  if not found or a.id is null then
    insert into public.payment_attempts(order_id, tran_id, amount_minor, currency, idempotency_key)
    values (o.id, 'TTF' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 24), o.total_minor,
            coalesce((select value from public.app_settings where key = 'aamarpay_currency'), 'BDT'), p_idempotency_key)
    returning * into a;
  end if;
  select * into v_profile from public.profiles where id = v_uid;
  return jsonb_build_object(
    'tranId', a.tran_id, 'amountMinor', a.amount_minor,
    'amountDecimal', (a.amount_minor / 100)::text || '.' || lpad((a.amount_minor % 100)::text, 2, '0'),
    'currency', a.currency, 'orderId', o.id, 'orderReference', o.reference,
    'customerName', v_profile.name, 'customerEmail', v_profile.email, 'customerPhone', o.contact_phone,
    'customerAddress', o.shipping_address,
    'description', 'Order ' || o.reference, 'paymentUrl', a.payment_url, 'status', a.status);
end $$;

create function public.attach_payment_url(p_tran_id text, p_url text) returns void
language sql security definer set search_path = public as $$
  update public.payment_attempts set payment_url = p_url, updated_at = now()
   where tran_id = p_tran_id and status = 'initiated' and payment_url is null
$$;

-- Applies a VERIFIED gateway result (service role ONLY). The caller must have
-- obtained p_verified from the provider's server-side verification API, never
-- from a redirect or client. Idempotent and amount/identity checked.
create function public.record_payment_result(p_tran_id text, p_verified jsonb, p_expected_store text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a public.payment_attempts%rowtype; pm public.payments%rowtype; o public.orders%rowtype;
  v_code text := coalesce(p_verified ->> 'statusCode', '');
  v_amount_text text := p_verified ->> 'amount'; v_amount bigint;
  v_cur text := nullif(btrim(coalesce(p_verified ->> 'currency', '')), '');
  v_mer text := p_verified ->> 'merTxnId'; v_pg text := nullif(btrim(coalesce(p_verified ->> 'pgTxnId', '')), '');
  v_store text := nullif(btrim(coalesce(p_verified ->> 'storeId', '')), '');
  v_safe jsonb; v_problem text;
begin
  select * into a from public.payment_attempts where tran_id = p_tran_id for update;
  if not found then
    raise exception 'Unknown transaction.' using errcode = 'P0001', hint = 'PAYMENT_UNKNOWN';
  end if;
  select * into pm from public.payments where order_id = a.order_id for update;
  select * into o from public.orders where id = a.order_id;

  v_safe := jsonb_strip_nulls(jsonb_build_object(
    'statusCode', v_code, 'payStatus', p_verified ->> 'payStatus', 'merTxnId', v_mer, 'pgTxnId', v_pg,
    'amount', v_amount_text, 'currency', v_cur, 'storeId', v_store, 'paymentType', p_verified ->> 'paymentType'));

  if a.status = 'successful' then
    return jsonb_build_object('outcome', 'already_processed', 'orderId', o.id);   -- repeated callback
  end if;

  if v_amount_text ~ '^[0-9]+(\.[0-9]{1,2})?$' then
    v_amount := split_part(v_amount_text, '.', 1)::bigint * 100
                + coalesce(nullif(rpad(split_part(v_amount_text, '.', 2), 2, '0'), '')::bigint, 0);
  end if;

  if v_code = '2' then
    if v_mer is distinct from a.tran_id then v_problem := 'Transaction id does not match.';
    elsif v_amount is null or v_amount <> a.amount_minor then v_problem := 'Amount does not match the order.';
    elsif v_cur is not null and upper(v_cur) <> upper(a.currency) then v_problem := 'Currency does not match.';
    elsif p_expected_store is not null and v_store is not null and v_store <> p_expected_store then v_problem := 'Store does not match.';
    elsif v_pg is not null and exists (select 1 from public.payments x where x.provider = 'aamarpay'
            and x.transaction_ref = v_pg and x.order_id <> a.order_id) then v_problem := 'Gateway transaction already used by another order.';
    end if;
    if v_problem is not null then
      update public.payment_attempts set status = 'mismatch', verification = v_safe, gateway_txn_id = v_pg, updated_at = now() where id = a.id;
      update public.payments set needs_review = true, review_reason = v_problem where id = pm.id;
      return jsonb_build_object('outcome', 'mismatch', 'reason', v_problem, 'orderId', o.id);
    end if;

    update public.payment_attempts set status = 'successful', verification = v_safe, gateway_txn_id = v_pg, updated_at = now() where id = a.id;
    if pm.status = 'successful' then
      update public.payments set needs_review = true, review_reason = 'A second successful payment was received for this order.' where id = pm.id;
      return jsonb_build_object('outcome', 'duplicate_success', 'orderId', o.id);
    end if;
    update public.payments set status = 'successful', provider = 'aamarpay', transaction_ref = v_pg where id = pm.id;
    if o.status = 'cancelled' then
      update public.payments set needs_review = true, review_reason = 'Payment received for a cancelled order; refund handling is not defined.' where id = pm.id;
    end if;
    perform public.notify(o.user_id, 'Payment received', 'We received your online payment for order ' || o.reference || '.');
    return jsonb_build_object('outcome', 'paid', 'orderId', o.id);

  elsif v_code = '7' or v_code = '3' then
    update public.payment_attempts set status = case when v_code = '3' then 'expired' else 'failed' end,
           verification = v_safe, updated_at = now() where id = a.id;
    if pm.status in ('pending', 'cancelled') then
      update public.payments set status = 'failed' where id = pm.id;
      perform public.notify(o.user_id, 'Payment not completed', 'The online payment for order ' || o.reference || ' did not complete. You can try again from the order page.');
    end if;
    return jsonb_build_object('outcome', case when v_code = '3' then 'expired' else 'failed' end, 'orderId', o.id);
  end if;

  update public.payment_attempts set verification = v_safe, updated_at = now() where id = a.id;
  return jsonb_build_object('outcome', 'pending', 'orderId', o.id);   -- still initiated at the gateway
end $$;

create function public.record_payment_cancel(p_tran_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.payment_attempts%rowtype;
begin
  select * into a from public.payment_attempts where tran_id = p_tran_id for update;
  if not found then
    raise exception 'Unknown transaction.' using errcode = 'P0001', hint = 'PAYMENT_UNKNOWN';
  end if;
  if a.status <> 'initiated' then
    return jsonb_build_object('outcome', 'ignored', 'orderId', a.order_id);
  end if;
  update public.payment_attempts set status = 'cancelled', updated_at = now() where id = a.id;
  update public.payments set status = 'cancelled' where order_id = a.order_id and status = 'pending';
  return jsonb_build_object('outcome', 'cancelled', 'orderId', a.order_id);
end $$;

create function public.payment_attempt_info(p_tran_id text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('tranId', a.tran_id, 'orderId', a.order_id, 'amountMinor', a.amount_minor,
                            'currency', a.currency, 'status', a.status)
    from public.payment_attempts a where a.tran_id = p_tran_id
$$;
