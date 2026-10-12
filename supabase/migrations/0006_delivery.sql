-- Dastak: delivery-partner helpers.

-- Available orders: ready for pickup, not yet assigned.
-- Only approved + active delivery partners can call this (enforced inside).
create or replace function list_available_orders()
returns table (
  id uuid, order_number text, vendor_id uuid, vendor_name text,
  pickup_address text, pickup_lat numeric, pickup_lng numeric,
  destination_address text, destination_lat numeric, destination_lng numeric,
  delivery_distance_km numeric, delivery_fee_paise integer,
  items_subtotal_paise integer, total_payable_paise integer,
  created_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from delivery_partner_profiles dp
    join profiles p on p.id = dp.user_id
    where dp.user_id = auth.uid() and dp.approved_at is not null and p.status = 'active'
  ) then
    raise exception 'partner not active or not approved';
  end if;

  return query
    select o.id, o.order_number, o.vendor_id, v.name as vendor_name,
      v.dispatch_address as pickup_address, v.latitude as pickup_lat, v.longitude as pickup_lng,
      o.destination_address, o.destination_lat, o.destination_lng,
      o.delivery_distance_km, o.delivery_fee_paise,
      o.items_subtotal_paise, o.total_payable_paise,
      o.created_at
    from orders o
    join vendors v on v.id = o.vendor_id
    where o.status = 'ready_for_pickup'
      and not exists (
        select 1 from delivery_assignments da
        where da.order_id = o.id and da.status = 'accepted'
      )
    order by o.created_at asc;
end;
$$;

-- Partner's active (in-progress) delivery, if any.
create or replace function my_active_delivery()
returns table (
  assignment_id uuid, order_id uuid, order_number text, status order_status,
  vendor_id uuid, vendor_name text, pickup_address text, pickup_lat numeric, pickup_lng numeric,
  destination_address text, destination_lat numeric, destination_lng numeric,
  delivery_distance_km numeric, delivery_fee_paise integer, items_subtotal_paise integer,
  item_count integer, customer_note text
)
language sql security definer set search_path = public as $$
  select
    da.id as assignment_id,
    o.id as order_id, o.order_number, o.status,
    v.id as vendor_id, v.name as vendor_name,
    v.dispatch_address as pickup_address, v.latitude as pickup_lat, v.longitude as pickup_lng,
    o.destination_address, o.destination_lat, o.destination_lng,
    o.delivery_distance_km, o.delivery_fee_paise, o.items_subtotal_paise,
    (select count(*)::integer from order_items oi where oi.order_id = o.id) as item_count,
    o.customer_note
  from delivery_assignments da
  join orders o on o.id = da.order_id
  join vendors v on v.id = o.vendor_id
  where da.partner_id = auth.uid()
    and da.status = 'accepted'
    and o.status in ('assigned', 'picked_up', 'out_for_delivery')
  limit 1;
$$;

-- Earnings summary.
create or replace function my_earnings_summary()
returns table (
  today_count integer, week_count integer, month_count integer,
  today_paise bigint, week_paise bigint, month_paise bigint,
  pending_paise bigint, settled_paise bigint
)
language sql security definer set search_path = public as $$
  select
    count(*) filter (where created_at >= date_trunc('day', now()))::integer,
    count(*) filter (where created_at >= date_trunc('week', now()))::integer,
    count(*) filter (where created_at >= date_trunc('month', now()))::integer,
    coalesce(sum(net_paise) filter (where created_at >= date_trunc('day', now())), 0)::bigint,
    coalesce(sum(net_paise) filter (where created_at >= date_trunc('week', now())), 0)::bigint,
    coalesce(sum(net_paise) filter (where created_at >= date_trunc('month', now())), 0)::bigint,
    coalesce(sum(net_paise) filter (where not settled), 0)::bigint,
    coalesce(sum(net_paise) filter (where settled), 0)::bigint
  from delivery_earnings
  where partner_id = auth.uid();
$$;

-- Toggle online/offline.
create or replace function set_partner_online(p_online boolean)
returns void language sql security definer set search_path = public as $$
  update delivery_partner_profiles
    set is_online = p_online, last_seen = now()
    where user_id = auth.uid();
$$;
