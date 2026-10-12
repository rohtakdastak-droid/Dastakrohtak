-- Dastak: initial schema
-- Monetary values are stored as integer paise. Avoid floats for currency.

create extension if not exists "pgcrypto";

-- ============================================================
-- IDENTITY & ACCESS
-- ============================================================

create type user_role as enum ('customer', 'vendor', 'delivery', 'admin');
create type account_status as enum ('active', 'suspended', 'pending', 'rejected');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  phone text,
  phone_verified boolean not null default false,
  role user_role not null default 'customer',
  status account_status not null default 'active',
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_role_idx on profiles(role);

create table user_addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  label text,
  formatted_address text not null,
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,
  instructions text,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index user_addresses_user_idx on user_addresses(user_id);

-- ============================================================
-- VENDORS & PRODUCTS
-- ============================================================

create type vendor_category as enum ('food', 'medicine', 'accessories', 'groceries');

create table vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique,
  category vendor_category not null default 'food',
  description text,
  cover_image_path text,
  logo_image_path text,
  dispatch_address text not null,
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,
  min_order_paise integer not null default 0,
  prep_time_minutes integer not null default 20,
  is_active boolean not null default true,
  is_featured boolean not null default false,
  sort_priority integer not null default 100,
  service_radius_km numeric(5,2) not null default 7.0,
  opening_hours jsonb not null default '{}'::jsonb,
  rating_avg numeric(3,2) not null default 0,
  rating_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index vendors_category_active_idx on vendors(category, is_active);
create index vendors_sort_priority_idx on vendors(sort_priority);

create table vendor_members (
  user_id uuid not null references profiles(id) on delete cascade,
  vendor_id uuid not null references vendors(id) on delete cascade,
  role text not null default 'manager',
  status account_status not null default 'active',
  primary key (user_id, vendor_id)
);

create type diet_tag as enum ('veg', 'non_veg', 'egg', 'unknown');

create table products (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references vendors(id) on delete cascade,
  name text not null,
  description text,
  price_paise integer not null check (price_paise >= 0),
  sale_price_paise integer check (sale_price_paise is null or sale_price_paise >= 0),
  image_path text,
  diet diet_tag not null default 'unknown',
  stock integer, -- null = unlimited
  is_available boolean not null default true,
  sort_priority integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_vendor_idx on products(vendor_id);
create index products_available_idx on products(is_available);

create table product_options (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  group_name text not null,         -- e.g. "Size", "Add-ons"
  label text not null,              -- e.g. "Large", "Extra cheese"
  price_delta_paise integer not null default 0,
  is_available boolean not null default true,
  sort_priority integer not null default 100
);
create index product_options_product_idx on product_options(product_id);

-- ============================================================
-- DELIVERY RATE RULES (admin editable)
-- ============================================================

create table delivery_rate_rules (
  id uuid primary key default gen_random_uuid(),
  min_km numeric(6,3) not null,     -- inclusive-exclusive bands: (min, max]
  max_km numeric(6,3) not null,
  fee_paise integer not null,
  is_active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now()
);
create index delivery_rate_rules_active_idx on delivery_rate_rules(is_active, min_km, max_km);

-- Per-km rule for distances beyond the table ceiling: base + per_km * ceil(d - ceiling).
create table delivery_overflow_rule (
  id boolean primary key default true check (id),  -- singleton
  ceiling_km numeric(6,3) not null default 9.0,
  base_fee_paise integer not null default 9000,
  per_km_paise integer not null default 500
);
insert into delivery_overflow_rule (id) values (true) on conflict do nothing;

-- Seed the exact fee schedule from the spec. Bands are (min_km, max_km].
insert into delivery_rate_rules (min_km, max_km, fee_paise) values
  (0.0, 1.0, 1500),
  (1.0, 1.5, 2000),
  (1.5, 2.0, 2500),
  (2.0, 2.5, 2700),
  (2.5, 3.0, 3300),
  (3.0, 3.5, 3700),
  (3.5, 4.0, 4400),
  (4.0, 4.5, 4700),
  (4.5, 5.0, 5500),
  (5.0, 5.5, 5700),
  (5.5, 6.0, 6300),
  (6.0, 6.5, 6700),
  (6.5, 7.0, 7300),
  (7.0, 7.5, 7700),
  (7.5, 8.0, 8300),
  (8.0, 8.5, 8700),
  (8.5, 9.0, 9000);

-- ============================================================
-- ORDERS
-- ============================================================

create type order_status as enum (
  'cart', 'pending_payment', 'payment_review', 'payment_verified',
  'vendor_confirmation', 'preparing', 'ready_for_pickup',
  'assigned', 'picked_up', 'out_for_delivery', 'delivered',
  'rejected', 'cancelled', 'refunded'
);

create type payment_status as enum (
  'unpaid', 'submitted', 'verified', 'rejected', 'refunded'
);

create type payment_method as enum ('upi_qr', 'cod');

create table orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null default ('DST-' || upper(substr(gen_random_uuid()::text, 1, 8))),
  customer_id uuid not null references profiles(id) on delete restrict,
  vendor_id uuid not null references vendors(id) on delete restrict,
  category vendor_category not null,

  -- Destination snapshot
  destination_address text not null,
  destination_lat numeric(9,6) not null,
  destination_lng numeric(9,6) not null,

  -- Pricing snapshot (paise)
  items_subtotal_paise integer not null default 0,
  tax_paise integer not null default 0,
  discount_paise integer not null default 0,
  delivery_distance_km numeric(6,3) not null default 0,
  delivery_fee_paise integer not null default 0,
  delivery_route_provider text,  -- 'google' | 'mapbox' | 'haversine'
  total_payable_paise integer not null default 0,

  payment_method payment_method not null default 'upi_qr',
  payment_status payment_status not null default 'unpaid',
  status order_status not null default 'cart',

  customer_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz,
  delivered_at timestamptz
);
create index orders_customer_idx on orders(customer_id, created_at desc);
create index orders_vendor_idx on orders(vendor_id, created_at desc);
create index orders_status_idx on orders(status);

create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  product_name text not null,       -- snapshot
  unit_price_paise integer not null,
  quantity integer not null check (quantity > 0),
  options jsonb not null default '[]'::jsonb,
  line_total_paise integer not null
);
create index order_items_order_idx on order_items(order_id);

create table order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  old_status order_status,
  new_status order_status not null,
  actor_id uuid references profiles(id),
  reason text,
  created_at timestamptz not null default now()
);
create index order_status_history_order_idx on order_status_history(order_id, created_at);

-- ============================================================
-- DELIVERY PARTNERS
-- ============================================================

create table delivery_partner_profiles (
  user_id uuid primary key references profiles(id) on delete cascade,
  vehicle_type text,
  vehicle_number text,
  profile_photo_path text,
  partner_qr_code text unique default ('DP-' || upper(substr(gen_random_uuid()::text, 1, 10))),
  approved_at timestamptz,
  approved_by uuid references profiles(id),
  is_online boolean not null default false,
  last_seen timestamptz,
  created_at timestamptz not null default now()
);

create table partner_documents (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references profiles(id) on delete cascade,
  doc_type text not null,              -- 'driving_license', 'id_proof', 'vehicle_rc'
  file_path text not null,             -- private storage path
  masked_reference text,
  status account_status not null default 'pending',
  reviewer_id uuid references profiles(id),
  reviewed_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create index partner_documents_partner_idx on partner_documents(partner_id);

create type assignment_status as enum ('offered', 'accepted', 'rejected', 'expired', 'cancelled');

create table delivery_assignments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  partner_id uuid not null references profiles(id) on delete restrict,
  status assignment_status not null default 'offered',
  offered_at timestamptz not null default now(),
  responded_at timestamptz,
  completed_at timestamptz
);
-- At most one accepted assignment per order:
create unique index delivery_assignments_one_accepted
  on delivery_assignments(order_id)
  where status = 'accepted';
create index delivery_assignments_partner_idx on delivery_assignments(partner_id, status);

create table delivery_earnings (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete restrict,
  partner_id uuid not null references profiles(id) on delete restrict,
  gross_paise integer not null default 0,
  adjustments_paise integer not null default 0,
  net_paise integer not null default 0,
  settled boolean not null default false,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  unique (order_id)
);
create index delivery_earnings_partner_idx on delivery_earnings(partner_id, created_at desc);

-- ============================================================
-- PAYMENTS
-- ============================================================

create table payment_settings (
  id boolean primary key default true check (id),
  qr_image_path text,
  upi_vpa text,
  payee_name text default 'Dastak',
  instructions text,
  cod_enabled boolean not null default false,
  verification_mode text not null default 'manual'   -- 'manual' | 'gateway'
);
insert into payment_settings (id) values (true) on conflict do nothing;

create table payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  amount_paise integer not null,
  method payment_method not null default 'upi_qr',
  upi_reference text,
  proof_image_path text,
  status payment_status not null default 'submitted',
  verified_by uuid references profiles(id),
  verified_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now()
);
create index payments_order_idx on payments(order_id);
create index payments_status_idx on payments(status);

create table refunds (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references payments(id) on delete restrict,
  amount_paise integer not null,
  reason text,
  external_reference text,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

-- ============================================================
-- REVIEWS, NOTIFICATIONS, SUPPORT
-- ============================================================

create table reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  customer_id uuid not null references profiles(id) on delete cascade,
  vendor_id uuid not null references vendors(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  moderation_status text not null default 'visible',   -- 'visible' | 'hidden'
  created_at timestamptz not null default now(),
  unique (order_id)
);
create index reviews_vendor_idx on reviews(vendor_id);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text,
  order_id uuid references orders(id) on delete set null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on notifications(user_id, created_at desc);
create index notifications_unread_idx on notifications(user_id) where read_at is null;

create table support_tickets (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references profiles(id) on delete cascade,
  order_id uuid references orders(id) on delete set null,
  category text not null,
  description text not null,
  status text not null default 'open',
  assigned_admin uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support_tickets(id) on delete cascade,
  sender_id uuid not null references profiles(id),
  message text not null,
  attachment_path text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- APP SETTINGS & AUDIT
-- ============================================================

create table app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
insert into app_settings (key, value) values
  ('categories_enabled', '["food","medicine","accessories","groceries"]'::jsonb),
  ('tax_percent', '0'::jsonb),
  ('cancellation_window_minutes', '5'::jsonb)
on conflict do nothing;

create table admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references profiles(id),
  action text not null,
  entity text not null,
  entity_id text,
  reason text,
  payload jsonb,
  created_at timestamptz not null default now()
);
create index admin_audit_logs_actor_idx on admin_audit_logs(actor_id, created_at desc);
