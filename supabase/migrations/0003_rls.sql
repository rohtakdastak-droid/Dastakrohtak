-- Dastak: row-level security. Every exposed table is locked down.

alter table profiles enable row level security;
alter table user_addresses enable row level security;
alter table vendors enable row level security;
alter table vendor_members enable row level security;
alter table products enable row level security;
alter table product_options enable row level security;
alter table delivery_rate_rules enable row level security;
alter table delivery_overflow_rule enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table order_status_history enable row level security;
alter table delivery_partner_profiles enable row level security;
alter table partner_documents enable row level security;
alter table delivery_assignments enable row level security;
alter table delivery_earnings enable row level security;
alter table payment_settings enable row level security;
alter table payments enable row level security;
alter table refunds enable row level security;
alter table reviews enable row level security;
alter table notifications enable row level security;
alter table support_tickets enable row level security;
alter table support_messages enable row level security;
alter table app_settings enable row level security;
alter table admin_audit_logs enable row level security;

-- ===== profiles =====
create policy "profiles self read" on profiles for select
  using (id = auth.uid() or is_admin());
create policy "profiles self update" on profiles for update
  using (id = auth.uid()) with check (id = auth.uid() and role = (select role from profiles where id = auth.uid()));
create policy "profiles admin write" on profiles for all
  using (is_admin()) with check (is_admin());
create policy "profiles self insert" on profiles for insert
  with check (id = auth.uid());

-- ===== user_addresses =====
create policy "addresses owner all" on user_addresses for all
  using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());

-- ===== vendors (public read of active vendors) =====
create policy "vendors public read" on vendors for select
  using (is_active or is_admin() or is_vendor_member(id));
create policy "vendors admin write" on vendors for all
  using (is_admin()) with check (is_admin());
create policy "vendors member update" on vendors for update
  using (is_vendor_member(id))
  with check (is_vendor_member(id));

-- ===== vendor_members =====
create policy "vendor_members read" on vendor_members for select
  using (user_id = auth.uid() or is_admin());
create policy "vendor_members admin" on vendor_members for all
  using (is_admin()) with check (is_admin());

-- ===== products / options (public read of available ones) =====
create policy "products public read" on products for select
  using (is_available or is_admin() or is_vendor_member(vendor_id));
create policy "products vendor manage" on products for all
  using (is_admin() or is_vendor_member(vendor_id))
  with check (is_admin() or is_vendor_member(vendor_id));

create policy "options public read" on product_options for select
  using (
    is_available
    or is_admin()
    or exists (select 1 from products p where p.id = product_id and is_vendor_member(p.vendor_id))
  );
create policy "options vendor manage" on product_options for all
  using (
    is_admin()
    or exists (select 1 from products p where p.id = product_id and is_vendor_member(p.vendor_id))
  )
  with check (
    is_admin()
    or exists (select 1 from products p where p.id = product_id and is_vendor_member(p.vendor_id))
  );

-- ===== delivery rate rules: public read, admin write =====
create policy "rate rules read" on delivery_rate_rules for select using (true);
create policy "rate rules admin" on delivery_rate_rules for all
  using (is_admin()) with check (is_admin());
create policy "overflow read" on delivery_overflow_rule for select using (true);
create policy "overflow admin" on delivery_overflow_rule for all
  using (is_admin()) with check (is_admin());

-- ===== orders =====
create policy "orders customer read" on orders for select
  using (
    customer_id = auth.uid()
    or is_admin()
    or is_vendor_member(vendor_id)
    or exists (
      select 1 from delivery_assignments da
      where da.order_id = orders.id and da.partner_id = auth.uid()
    )
  );
-- No direct inserts/updates: all go through security-definer functions.
create policy "orders admin write" on orders for all
  using (is_admin()) with check (is_admin());

-- ===== order_items (readable with the parent order) =====
create policy "order_items read" on order_items for select
  using (
    exists (select 1 from orders o where o.id = order_id and (
      o.customer_id = auth.uid() or is_admin() or is_vendor_member(o.vendor_id)
      or exists (select 1 from delivery_assignments da where da.order_id = o.id and da.partner_id = auth.uid())
    ))
  );
create policy "order_items admin write" on order_items for all
  using (is_admin()) with check (is_admin());

create policy "status_history read" on order_status_history for select
  using (
    exists (select 1 from orders o where o.id = order_id and (
      o.customer_id = auth.uid() or is_admin() or is_vendor_member(o.vendor_id)
      or exists (select 1 from delivery_assignments da where da.order_id = o.id and da.partner_id = auth.uid())
    ))
  );

-- ===== delivery partner profiles =====
create policy "partner self read" on delivery_partner_profiles for select
  using (user_id = auth.uid() or is_admin());
create policy "partner self upsert" on delivery_partner_profiles for insert
  with check (user_id = auth.uid());
create policy "partner self update" on delivery_partner_profiles for update
  using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());

create policy "partner docs self" on partner_documents for all
  using (partner_id = auth.uid() or is_admin())
  with check (partner_id = auth.uid() or is_admin());

create policy "assignments visible" on delivery_assignments for select
  using (
    partner_id = auth.uid()
    or is_admin()
    or exists (select 1 from orders o where o.id = order_id and (o.customer_id = auth.uid() or is_vendor_member(o.vendor_id)))
  );
-- Inserts/updates only through accept_delivery.
create policy "assignments admin write" on delivery_assignments for all
  using (is_admin()) with check (is_admin());

create policy "earnings self" on delivery_earnings for select
  using (partner_id = auth.uid() or is_admin());

-- ===== payments =====
create policy "payment_settings read" on payment_settings for select using (true);
create policy "payment_settings admin" on payment_settings for all
  using (is_admin()) with check (is_admin());

create policy "payments visible" on payments for select
  using (
    is_admin()
    or exists (select 1 from orders o where o.id = order_id and o.customer_id = auth.uid())
    or exists (select 1 from orders o where o.id = order_id and is_vendor_member(o.vendor_id))
  );
create policy "payments admin write" on payments for all
  using (is_admin()) with check (is_admin());

create policy "refunds admin" on refunds for all
  using (is_admin()) with check (is_admin());

-- ===== reviews =====
create policy "reviews public read" on reviews for select
  using (moderation_status = 'visible' or customer_id = auth.uid() or is_admin());
create policy "reviews self insert" on reviews for insert
  with check (
    customer_id = auth.uid()
    and exists (
      select 1 from orders o
      where o.id = order_id and o.customer_id = auth.uid()
        and o.status = 'delivered' and o.vendor_id = reviews.vendor_id
    )
  );
create policy "reviews self update" on reviews for update
  using (customer_id = auth.uid() or is_admin())
  with check (customer_id = auth.uid() or is_admin());

-- ===== notifications =====
create policy "notifications self" on notifications for select
  using (user_id = auth.uid() or is_admin());
create policy "notifications self update" on notifications for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ===== support =====
create policy "tickets self" on support_tickets for all
  using (customer_id = auth.uid() or is_admin())
  with check (customer_id = auth.uid() or is_admin());
create policy "ticket msgs" on support_messages for all
  using (
    is_admin()
    or exists (select 1 from support_tickets t where t.id = ticket_id and t.customer_id = auth.uid())
  )
  with check (
    is_admin()
    or exists (select 1 from support_tickets t where t.id = ticket_id and t.customer_id = auth.uid())
  );

-- ===== app settings / audit =====
create policy "settings read" on app_settings for select using (true);
create policy "settings admin" on app_settings for all
  using (is_admin()) with check (is_admin());
create policy "audit admin" on admin_audit_logs for select using (is_admin());

-- Trigger: auto-create a profile row on user signup.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)), 'customer')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
