-- Fix infinite recursion between orders and delivery_assignments RLS policies.
-- orders policy checks delivery_assignments, which checks orders → loop.
-- Solution: use security definer functions that bypass RLS.

create or replace function is_order_customer(oid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from orders where id = oid and customer_id = auth.uid()
  );
$$;

create or replace function is_order_vendor(oid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from orders o
    join vendor_members vm on vm.vendor_id = o.vendor_id
    where o.id = oid and vm.user_id = auth.uid() and vm.status = 'active'
  );
$$;

create or replace function is_delivery_partner(oid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from delivery_assignments where order_id = oid and partner_id = auth.uid()
  );
$$;

-- Drop and recreate the orders read policy without cross-table RLS triggers
drop policy if exists "orders customer read" on orders;
create policy "orders customer read" on orders for select
  using (
    customer_id = auth.uid()
    or is_admin()
    or is_vendor_member(vendor_id)
    or is_delivery_partner(id)
  );

-- Drop and recreate order_items read policy
drop policy if exists "order_items read" on order_items;
create policy "order_items read" on order_items for select
  using (
    is_order_customer(order_id)
    or is_admin()
    or is_order_vendor(order_id)
    or is_delivery_partner(order_id)
  );

-- Drop and recreate delivery_assignments visible policy
drop policy if exists "assignments visible" on delivery_assignments;
create policy "assignments visible" on delivery_assignments for select
  using (
    partner_id = auth.uid()
    or is_admin()
    or is_order_customer(order_id)
    or is_order_vendor(order_id)
  );

-- Allow customers to insert their own orders (fallback when edge function unavailable)
drop policy if exists "orders customer insert" on orders;
create policy "orders customer insert" on orders for insert
  with check (customer_id = auth.uid());

-- Allow customers to insert order items for their own orders
drop policy if exists "order_items customer insert" on order_items;
create policy "order_items customer insert" on order_items for insert
  with check (is_order_customer(order_id));
