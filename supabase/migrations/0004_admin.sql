-- Dastak: admin helper RPCs and views.

-- Approve / suspend a delivery partner.
create or replace function admin_set_partner_status(p_user_id uuid, p_status account_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;

  update profiles set status = p_status where id = p_user_id and role = 'delivery';

  if p_status = 'active' then
    update delivery_partner_profiles
      set approved_at = coalesce(approved_at, now()),
          approved_by = coalesce(approved_by, auth.uid())
      where user_id = p_user_id;
  end if;

  insert into admin_audit_logs (actor_id, action, entity, entity_id, reason)
    values (auth.uid(), 'partner_status_' || p_status::text, 'profile', p_user_id::text, null);
end;
$$;

-- Register a user as a delivery partner (admin invites them after they sign up).
create or replace function admin_assign_delivery_role(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  update profiles set role = 'delivery', status = 'pending' where id = p_user_id;
  insert into delivery_partner_profiles (user_id) values (p_user_id) on conflict do nothing;
  insert into admin_audit_logs (actor_id, action, entity, entity_id)
    values (auth.uid(), 'assign_delivery_role', 'profile', p_user_id::text);
end;
$$;

-- Assign a user to a vendor's team.
create or replace function admin_add_vendor_member(p_user_id uuid, p_vendor_id uuid, p_role text default 'manager')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  update profiles set role = 'vendor' where id = p_user_id and role = 'customer';
  insert into vendor_members (user_id, vendor_id, role, status)
    values (p_user_id, p_vendor_id, p_role, 'active')
    on conflict (user_id, vendor_id) do update set status = 'active', role = excluded.role;
  insert into admin_audit_logs (actor_id, action, entity, entity_id)
    values (auth.uid(), 'add_vendor_member', 'vendor', p_vendor_id::text);
end;
$$;

-- Reorder vendors in one shot. ids[] in display order.
create or replace function admin_reorder_vendors(p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare i integer; vid uuid;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  i := 10;
  foreach vid in array p_ids loop
    update vendors set sort_priority = i where id = vid;
    i := i + 10;
  end loop;
  insert into admin_audit_logs (actor_id, action, entity, entity_id)
    values (auth.uid(), 'reorder_vendors', 'vendor', null);
end;
$$;

-- Replace the entire delivery rate table in one transaction.
create or replace function admin_replace_rate_table(p_rows jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  delete from delivery_rate_rules;
  for r in select * from jsonb_array_elements(p_rows) loop
    insert into delivery_rate_rules (min_km, max_km, fee_paise, is_active)
    values (
      (r->>'min_km')::numeric,
      (r->>'max_km')::numeric,
      (r->>'fee_paise')::integer,
      true
    );
  end loop;
  insert into admin_audit_logs (actor_id, action, entity, entity_id, payload)
    values (auth.uid(), 'replace_rate_table', 'delivery_rate_rules', null, p_rows);
end;
$$;

-- Admin cancellation / refund trigger.
create or replace function admin_cancel_order(p_order_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_order record;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  select * into v_order from orders where id = p_order_id;
  if not found then raise exception 'order not found'; end if;

  update orders set status = 'cancelled' where id = p_order_id;
  insert into order_status_history (order_id, old_status, new_status, actor_id, reason)
    values (p_order_id, v_order.status, 'cancelled', auth.uid(), p_reason);
  insert into notifications (user_id, type, title, body, order_id)
    values (v_order.customer_id, 'order_cancelled', 'Order cancelled', p_reason, p_order_id);
  insert into admin_audit_logs (actor_id, action, entity, entity_id, reason)
    values (auth.uid(), 'cancel_order', 'order', p_order_id::text, p_reason);
end;
$$;

-- Aggregated metrics for the overview page. Admin-only via RLS of underlying tables.
create or replace view admin_overview_today as
with o as (
  select * from orders where created_at >= date_trunc('day', now())
)
select
  (select count(*) from o) as orders_today,
  (select count(*) from o where status in ('pending_payment','payment_review')) as awaiting_payment,
  (select count(*) from o where status = 'preparing') as preparing,
  (select count(*) from o where status in ('assigned','picked_up','out_for_delivery')) as in_delivery,
  (select count(*) from o where status = 'delivered') as delivered_today,
  (select count(*) from o where status = 'cancelled') as cancelled_today,
  (select coalesce(sum(total_payable_paise),0) from o where payment_status = 'verified') as collected_paise,
  (select coalesce(sum(total_payable_paise),0) from o) as gov_paise,
  (select count(*) from profiles where role = 'customer' and status = 'active') as customers_total,
  (select count(*) from vendors where is_active) as vendors_active,
  (select count(*) from profiles where role = 'delivery' and status = 'active') as partners_active;

grant select on admin_overview_today to authenticated;

-- Lightweight per-vendor sales (today).
create or replace view admin_vendor_sales_today as
select v.id as vendor_id, v.name,
  count(o.id) filter (where o.created_at >= date_trunc('day', now())) as orders,
  coalesce(sum(o.total_payable_paise) filter (
    where o.created_at >= date_trunc('day', now()) and o.payment_status = 'verified'
  ), 0) as collected_paise
from vendors v
left join orders o on o.vendor_id = v.id
group by v.id, v.name
order by collected_paise desc;

grant select on admin_vendor_sales_today to authenticated;
