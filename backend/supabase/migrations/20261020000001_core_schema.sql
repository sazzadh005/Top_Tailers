-- Top Tailers & Fabrics: core schema.
-- Money is stored as integer paisa (1 BDT = 100 paisa). Never floating point.
-- All timestamps are timestamptz (UTC). Authorization lives in RLS, grants and
-- SECURITY DEFINER functions (see later migrations), never in the client.

create extension if not exists pg_trgm with schema extensions;

create type public.user_role as enum ('customer', 'admin');

-- Non-secret configuration. Secrets (AamarPay signature key, Cloudinary API
-- secret) live ONLY in Edge Function secrets, never in the database.
create table public.app_settings (
  key text primary key,
  value text,
  updated_at timestamptz not null default now()
);
insert into public.app_settings(key, value) values
  ('delivery_flat_minor', '0'),            -- SRS defines no delivery charge
  ('delivery_free_above_minor', null),
  ('cloudinary_cloud_name', 'hmpqmney'),   -- public identifier, not a secret
  ('aamarpay_currency', 'BDT');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete restrict,
  name text not null check (char_length(btrim(name)) >= 2),
  email text not null,
  phone text not null,
  address text not null default '',
  profile_image_url text,
  profile_image_public_id text,
  role public.user_role not null default 'customer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_email_lower check (email = lower(email))
);
create unique index profiles_email_key on public.profiles (email);
create index profiles_role_created_idx on public.profiles (role, created_at desc);

create table public.customer_measurements (
  user_id uuid primary key references public.profiles (id) on delete restrict,
  "values" jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint measurements_is_object check (jsonb_typeof("values") = 'object')
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  product_name text not null check (char_length(btrim(product_name)) >= 1),
  description text not null default '',
  price_minor integer not null check (price_minor > 0 and price_minor <= 1000000000),
  category text not null check (category in ('Fabrics','Readymade','Tailoring','Accessories')),
  availability boolean not null default true,
  unit text not null default 'piece' check (unit in ('yard','piece','service')),
  requires_measurements boolean not null default false,
  is_featured boolean not null default false,
  popularity integer not null default 0 check (popularity >= 0),
  specs jsonb not null default '{}'::jsonb,
  discount_enabled boolean not null default false,
  discount_kind text check (discount_kind in ('percent','fixed')),
  discount_value integer check (discount_value > 0),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_code_format check (code ~ '^[A-Z0-9]+(-[A-Z0-9]+)*$' and char_length(code) between 3 and 24),
  constraint products_specs_is_object check (jsonb_typeof(specs) = 'object'),
  -- An enabled discount must be valid for the price: percent 1-99, fixed < price.
  constraint products_discount_valid check (
    not discount_enabled or (
      discount_kind is not null and discount_value is not null and (
        (discount_kind = 'percent' and discount_value between 1 and 99) or
        (discount_kind = 'fixed' and discount_value < price_minor)
      )
    )
  )
);
-- Codes stay reserved even after a soft delete: they are stable identifiers.
create unique index products_code_key on public.products (code);
create index products_category_idx on public.products (category) where deleted_at is null;
create index products_created_idx on public.products (created_at desc);
create index products_name_trgm on public.products using gin (product_name extensions.gin_trgm_ops);
create index products_desc_trgm on public.products using gin (description extensions.gin_trgm_ops);
create index products_code_trgm on public.products using gin (code extensions.gin_trgm_ops);

create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  url text not null,
  public_id text not null,
  position integer not null check (position between 0 and 3),
  created_at timestamptz not null default now(),
  unique (product_id, position),
  unique (public_id)
);

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  type text not null check (type in ('color','size')),
  name text not null check (char_length(btrim(name)) >= 1),
  argb bigint check (argb between 0 and 4294967295),
  position integer not null default 0,
  unique (product_id, type, name),
  check ((type = 'color') = (argb is not null))
);

create table public.vouchers (
  code text primary key,
  title text not null,
  kind text not null check (kind in ('percent','fixed')),
  value integer not null check (value > 0),
  expires_at timestamptz,
  categories text[] not null default '{}',
  is_active boolean not null default true,
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  constraint vouchers_code_format check (code ~ '^[A-Z0-9_-]{3,24}$'),
  constraint vouchers_percent_range check (kind <> 'percent' or value between 1 and 99)
);

create table public.customer_discounts (
  customer_id uuid primary key references public.profiles (id) on delete restrict,
  kind text not null check (kind in ('percent','fixed')),
  value integer not null check (value > 0),
  active boolean not null default true,
  note text not null default '',
  updated_at timestamptz not null default now(),
  constraint customer_discount_percent_range check (kind <> 'percent' or value between 1 and 99)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  user_id uuid not null references public.profiles (id) on delete restrict,
  customer_name text not null,
  contact_phone text not null,
  shipping_address text not null,
  note text not null default '' check (char_length(note) <= 300),
  subtotal_minor bigint not null check (subtotal_minor >= 0),
  product_discount_minor bigint not null default 0 check (product_discount_minor >= 0),
  customer_discount_minor bigint not null default 0 check (customer_discount_minor >= 0),
  voucher_discount_minor bigint not null default 0 check (voucher_discount_minor >= 0),
  delivery_minor bigint not null default 0 check (delivery_minor >= 0),
  total_minor bigint not null check (total_minor >= 0),
  voucher_code text,
  status text not null default 'pending'
    check (status in ('pending','confirmed','processing','completed','cancelled')),
  order_date timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- one order-level discount only (customer OR voucher), never both
  constraint orders_single_order_discount check (customer_discount_minor = 0 or voucher_discount_minor = 0),
  constraint orders_total_consistent check (
    total_minor = greatest(0, subtotal_minor - product_discount_minor - customer_discount_minor - voucher_discount_minor + delivery_minor)
  )
);
create index orders_user_date_idx on public.orders (user_id, order_date desc);
create index orders_status_date_idx on public.orders (status, order_date desc);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  line_no integer not null default 0,
  product_id uuid,                         -- no cascading FK: products may be removed
  product_code text not null,
  product_name text not null,
  list_unit_minor integer not null check (list_unit_minor > 0),
  unit_minor integer not null check (unit_minor > 0 and unit_minor <= list_unit_minor),
  quantity integer not null check (quantity between 1 and 20),
  image_url text,
  category text not null,
  unit text not null,
  color_name text,
  size text
);
create index order_items_order_idx on public.order_items (order_id);
create index order_items_code_trgm on public.order_items using gin (product_code extensions.gin_trgm_ops);

create table public.order_measurements (
  order_id uuid primary key references public.orders (id) on delete restrict,
  source text not null check (source in ('profile','enteredForOrder','otherPerson')),
  for_person text,
  captured_at timestamptz not null default now(),
  "values" jsonb not null,
  constraint order_measurements_other_person check (source <> 'otherPerson' or char_length(btrim(coalesce(for_person,''))) >= 2)
);

create table public.order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders (id) on delete restrict,
  status text not null check (status in ('pending','confirmed','processing','completed','cancelled')),
  at timestamptz not null default now()
);
create index order_events_order_idx on public.order_events (order_id, at);

create table public.cancellations (
  order_id uuid primary key references public.orders (id) on delete restrict,  -- one per order
  cancelled_by text not null check (cancelled_by in ('customer','shopAdmin')),
  cancelled_by_user uuid not null references public.profiles (id) on delete restrict,
  cancelled_by_name text not null,
  reason text not null check (char_length(btrim(reason)) >= 1),
  note text not null default '',
  paid_at_cancellation boolean not null default false,  -- refunds are undefined: flag for manual handling
  cancelled_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders (id) on delete restrict,
  method text not null check (method in ('cod','online')),
  status text not null default 'pending' check (status in ('pending','successful','failed','cancelled')),
  amount_minor bigint not null check (amount_minor >= 0),
  provider text not null check (provider in ('none','aamarpay')),
  transaction_ref text,
  needs_review boolean not null default false,
  review_reason text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint payments_provider_matches_method check ((method = 'cod' and provider = 'none') or (method = 'online' and provider = 'aamarpay'))
);
create unique index payments_provider_txn_key on public.payments (provider, transaction_ref) where transaction_ref is not null;

create table public.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  tran_id text not null unique check (char_length(tran_id) between 8 and 32),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'BDT',
  status text not null default 'initiated'
    check (status in ('initiated','successful','failed','expired','cancelled','mismatch')),
  payment_url text,
  gateway_txn_id text,
  verification jsonb,                       -- whitelisted fields only, never card data
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index payment_attempts_idem_key on public.payment_attempts (order_id, idempotency_key) where idempotency_key is not null;
create index payment_attempts_order_idx on public.payment_attempts (order_id);

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  product_id uuid not null,
  product_name text not null,
  user_id uuid not null references public.profiles (id) on delete restrict,
  rating integer not null check (rating between 1 and 5),
  comment text not null check (char_length(btrim(comment)) >= 5),
  created_at timestamptz not null default now(),
  unique (order_id, product_id)
);
create index feedback_product_idx on public.feedback (product_id, created_at desc);

create table public.suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete restrict,
  title text not null check (char_length(btrim(title)) >= 3),
  details text not null default '',
  status text not null default 'received' check (status in ('received','underReview','planned','declined')),
  created_at timestamptz not null default now()
);

create table public.restock_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete restrict,
  reason text not null default '',
  status text not null default 'received' check (status in ('received','underReview','planned','declined')),
  created_at timestamptz not null default now()
);
-- At most one OPEN request per user and product.
create unique index restock_open_key on public.restock_requests (user_id, product_id)
  where status in ('received','underReview');

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text not null default '',
  read boolean not null default false,
  created_at timestamptz not null default now()      -- NOT NULL: retention depends on it
);
create index notifications_user_created_idx on public.notifications (user_id, created_at desc);

create table public.wishlist_items (
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table public.promo_banners (
  id text primary key,
  title text not null,
  subtitle text not null,
  color_argb bigint not null,
  category text,
  voucher_code text,
  position integer not null default 0,
  active boolean not null default true
);

create table public.idempotency_keys (
  user_id uuid not null,
  key text not null,
  request_hash text not null,
  order_id uuid,
  created_at timestamptz not null default now(),
  primary key (user_id, key)
);

create table public.rate_limits (
  user_id uuid not null,
  bucket text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  primary key (user_id, bucket, window_start)
);

-- Cloudinary assets that are no longer referenced and should be destroyed.
create table public.image_cleanup_queue (
  public_id text primary key,
  queued_at timestamptz not null default now(),
  attempts integer not null default 0,
  last_error text
);
