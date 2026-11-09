-- Row Level Security and privileges. Deny by default: clients get SELECT on the
-- tables they may read (filtered by policy) and EXECUTE on the audited RPCs
-- below. They get no direct INSERT/UPDATE/DELETE on business tables.

alter table public.app_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.customer_measurements enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.product_variants enable row level security;
alter table public.vouchers enable row level security;
alter table public.customer_discounts enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_measurements enable row level security;
alter table public.order_events enable row level security;
alter table public.cancellations enable row level security;
alter table public.payments enable row level security;
alter table public.payment_attempts enable row level security;
alter table public.feedback enable row level security;
alter table public.suggestions enable row level security;
alter table public.restock_requests enable row level security;
alter table public.notifications enable row level security;
alter table public.wishlist_items enable row level security;
alter table public.promo_banners enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.rate_limits enable row level security;
alter table public.image_cleanup_queue enable row level security;

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy measurements_select on public.customer_measurements for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy customer_discounts_select on public.customer_discounts for select to authenticated
  using (customer_id = auth.uid() or public.is_admin());

create policy products_select on public.products for select to authenticated using (deleted_at is null);
create policy product_images_select on public.product_images for select to authenticated
  using (exists (select 1 from public.products p where p.id = product_id and p.deleted_at is null));
create policy product_variants_select on public.product_variants for select to authenticated
  using (exists (select 1 from public.products p where p.id = product_id and p.deleted_at is null));
create policy promo_banners_select on public.promo_banners for select to authenticated using (active);

create policy vouchers_select on public.vouchers for select to authenticated using (public.is_admin());

create policy orders_select on public.orders for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy order_items_select on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin())));
create policy order_measurements_select on public.order_measurements for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin())));
create policy order_events_select on public.order_events for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin())));
create policy cancellations_select on public.cancellations for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin())));
create policy payments_select on public.payments for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin())));
create policy payment_attempts_select on public.payment_attempts for select to authenticated using (public.is_admin());

create policy feedback_select on public.feedback for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy suggestions_select on public.suggestions for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy restock_select on public.restock_requests for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid() and now() - created_at <= interval '30 days');

create policy wishlist_select on public.wishlist_items for select to authenticated using (user_id = auth.uid());
create policy wishlist_insert on public.wishlist_items for insert to authenticated with check (user_id = auth.uid());
create policy wishlist_delete on public.wishlist_items for delete to authenticated using (user_id = auth.uid());
-- app_settings, idempotency_keys, rate_limits, image_cleanup_queue: no policy => no client access

revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

grant usage on schema public to anon, authenticated, service_role;
grant select on public.profiles, public.customer_measurements, public.products, public.product_images,
  public.product_variants, public.vouchers, public.customer_discounts, public.orders, public.order_items,
  public.order_measurements, public.order_events, public.cancellations, public.payments, public.payment_attempts,
  public.feedback, public.suggestions, public.restock_requests, public.notifications, public.promo_banners
  to authenticated;
grant select, insert, delete on public.wishlist_items to authenticated;

grant all on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Audited RPCs that signed-in clients may call. Everything else (payment
-- result recording, purge, cleanup, admin provisioning) is service-role only.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = any (array[
       'is_admin', 'normalize_phone', 'status_label', 'payment_status_label', 'escape_like',
       'search_products', 'get_products_by_ids', 'get_home', 'quote_pricing', 'get_voucher',
       'place_order', 'cancel_order', 'update_order_status', 'get_order', 'search_orders',
       'start_payment_attempt', 'my_profile', 'update_my_profile', 'set_measurements',
       'admin_list_customers', 'my_customer_discount', 'admin_list_customer_discounts',
       'admin_save_customer_discount', 'admin_remove_customer_discount',
       'admin_save_product', 'admin_delete_product', 'admin_is_code_taken',
       'admin_save_voucher', 'admin_set_voucher_active', 'admin_list_vouchers',
       'submit_feedback', 'feedback_for_product', 'my_feedback', 'admin_all_feedback',
       'submit_suggestion', 'submit_restock', 'my_suggestions', 'my_restocks',
       'admin_all_suggestions', 'admin_all_restocks', 'set_suggestion_status', 'set_restock_status',
       'visible_notifications', 'mark_notifications_read'])
  loop
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
