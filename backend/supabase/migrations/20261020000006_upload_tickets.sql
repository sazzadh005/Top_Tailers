-- Track every Cloudinary upload ticket the server issues so uploads that never
-- get attached to a product or profile (failed save, abandoned form) are found
-- and destroyed instead of lingering as orphaned assets.

create table public.image_upload_tickets (
  public_id text primary key,
  issued_to uuid not null,
  issued_at timestamptz not null default now()
);
alter table public.image_upload_tickets enable row level security;   -- no policy: service role only
revoke all on public.image_upload_tickets from public, anon, authenticated;
grant all on public.image_upload_tickets to service_role;

create function public.record_upload_ticket(p_public_id text, p_user uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.image_upload_tickets(public_id, issued_to) values (p_public_id, p_user)
  on conflict (public_id) do update set issued_at = now(), issued_to = excluded.issued_to
$$;

create function public.queue_orphaned_uploads(p_older_than interval default interval '1 hour') returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  insert into public.image_cleanup_queue(public_id)
  select t.public_id from public.image_upload_tickets t
   where t.issued_at < now() - p_older_than
     and not exists (select 1 from public.product_images pi where pi.public_id = t.public_id)
     and not exists (select 1 from public.profiles pr where pr.profile_image_public_id = t.public_id)
  on conflict do nothing;
  get diagnostics n = row_count;
  delete from public.image_upload_tickets t where t.issued_at < now() - p_older_than;
  return n;
end $$;

revoke execute on function public.record_upload_ticket(text, uuid) from public, anon, authenticated;
revoke execute on function public.queue_orphaned_uploads(interval) from public, anon, authenticated;
grant execute on function public.record_upload_ticket(text, uuid) to service_role;
grant execute on function public.queue_orphaned_uploads(interval) to service_role;
