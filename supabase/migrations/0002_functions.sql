-- Dastak: server-authoritative functions.

-- Helper: is current user an admin?
create or replace function is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles where id = auth.uid() and role = 'admin' and status = 'active'
  );
$$;

create or replace function is_vendor_member(vid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from vendor_members
    where vendor_id = vid and user_id = auth.uid() and status = 'active'
  );
$$;

-- ------------------------------------------------------------
-- Delivery fee: given a road distance in km, return the fee (paise).
-- Matches the spec exactly. Bands are (min_km, max_km]; 0 km → first band fee.
-- For distances strictly greater than ceiling_km, fee = base + per_km * ceil(d - ceiling).
-- ------------------------------------------------------------
create or replace function calc_delivery_fee_paise(distance_km numeric)
returns integer language plpgsql stable as $$
declare
  f integer;
  ov record;
  extra_km integer;
begin
  if distance_km is null or distance_km < 0 then
    return null;
  end if;

  select * into ov from delivery_overflow_rule where id = true;

  -- Exact-boundary semantics: 0 maps to first band (0, 1.0]; otherwise band is (min, max].
  if distance_km <= 0 then
    select fee_paise into f from delivery_rate_rules
      where is_active and min_km = 0 order by max_km asc limit 1;
    return f;
  end if;

  if distance_km <= ov.ceiling_km then
    select fee_paise into f from delivery_rate_rules
      where is_active and distance_km > min_km and distance_km <= max_km
      order by effective_from desc limit 1;
    return f;
  end if;

  -- Overflow: ceil(distance - ceiling) × per_km, added to base.
  extra_km := ceil(distance_km - ov.ceiling_km)::integer;
  return ov.base_fee_paise + extra_km * ov.per_km_paise;
end;
$$;

-- ------------------------------------------------------------
-- Haversine fallback distance (km). The real app should prefer a routing API
-- and only call this if routing is unavailable.
-- ------------------------------------------------------------
create or replace function haversine_km(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric)
returns numeric language plpgsql immutable as $$
declare
  r numeric := 6371.0;
  dlat numeric := radians(lat2 - lat1);
  dlng numeric := radians(lng2 - lng1);
  a numeric;
begin
  a := sin(dlat/2)^2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng/2)^2;
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
end;
$$;

-- ------------------------------------------------------------
-- Atomic order creation.
-- Server recalculates subtotal from live product prices (snapshot), computes
-- delivery fee, and inserts the order + items in one transaction.
-- items jsonb: [{ product_id, quantity, options: [{option_id,label,price_delta_paise}] }]
-- ------------------------------------------------------------
create or replace function create_order(
  p_vendor_id uuid,
  p_dest_address text,
  p_dest_lat numeric,
  p_dest_lng numeric,
  p_distance_km numeric,
  p_route_provider text,
  p_items jsonb,
  p_customer_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_order_id uuid;
  v_customer uuid := auth.uid();
  v_vendor record;
  v_subtotal integer := 0;
  v_fee integer;
  v_item jsonb;
  v_product record;
  v_qty integer;
  v_options jsonb;
  v_delta integer;
  v_unit integer;
  v_line integer;
begin
  if v_customer is null then
    raise exception 'not authenticated';
  end if;

  select * into v_vendor from vendors where id = p_vendor_id and is_active;
  if not found then
    raise exception 'vendor not available';
  end if;

  if p_distance_km is null or p_distance_km < 0 then
    raise exception 'invalid distance';
  end if;
  if p_distance_km > v_vendor.service_radius_km then
    raise exception 'destination out of service area';
  end if;

  v_fee := calc_delivery_fee_paise(p_distance_km);

  insert into orders (
    customer_id, vendor_id, category,
    destination_address, destination_lat, destination_lng,
    delivery_distance_km, delivery_fee_paise, delivery_route_provider,
    items_subtotal_paise, total_payable_paise,
    payment_method, payment_status, status,
    customer_note
  ) values (
    v_customer, p_vendor_id, v_vendor.category,
    p_dest_address, p_dest_lat, p_dest_lng,
    p_distance_km, v_fee, coalesce(p_route_provider, 'haversine'),
    0, v_fee,
    'upi_qr', 'unpaid', 'pending_payment',
    p_customer_note
  ) returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_product from products
      where id = (v_item->>'product_id')::uuid
        and vendor_id = p_vendor_id
        and is_available;
    if not found then
      raise exception 'product % not available', v_item->>'product_id';
    end if;

    v_qty := greatest(1, coalesce((v_item->>'quantity')::integer, 1));
    v_options := coalesce(v_item->'options', '[]'::jsonb);

    v_delta := coalesce((
      select sum(coalesce((opt->>'price_delta_paise')::integer, 0))
      from jsonb_array_elements(v_options) opt
    ), 0);

    v_unit := coalesce(v_product.sale_price_paise, v_product.price_paise) + v_delta;
    v_line := v_unit * v_qty;
    v_subtotal := v_subtotal + v_line;

    insert into order_items (order_id, product_id, product_name, unit_price_paise, quantity, options, line_total_paise)
    values (v_order_id, v_product.id, v_product.name, v_unit, v_qty, v_options, v_line);
  end loop;

  update orders
    set items_subtotal_paise = v_subtotal,
        total_payable_paise = v_subtotal + v_fee
    where id = v_order_id;

  insert into order_status_history (order_id, old_status, new_status, actor_id, reason)
    values (v_order_id, 'cart', 'pending_payment', v_customer, 'order created');

  insert into notifications (user_id, type, title, body, order_id)
    values (v_customer, 'order_created', 'Order placed',
            'Please complete payment to confirm your order.', v_order_id);

  return v_order_id;
end;
$$;

-- ------------------------------------------------------------
-- Submit payment proof. Customer only, for their own unpaid order.
-- ------------------------------------------------------------
create or replace function submit_payment_proof(
  p_order_id uuid,
  p_upi_reference text,
  p_proof_image_path text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_order record;
  v_payment_id uuid;
begin
  select * into v_order from orders where id = p_order_id and customer_id = auth.uid();
  if not found then raise exception 'order not found'; end if;
  if v_order.payment_status not in ('unpaid', 'rejected') then
    raise exception 'payment already recorded';
  end if;

  insert into payments (order_id, amount_paise, method, upi_reference, proof_image_path, status)
    values (p_order_id, v_order.total_payable_paise, 'upi_qr', p_upi_reference, p_proof_image_path, 'submitted')
    returning id into v_payment_id;

  update orders set payment_status = 'submitted', status = 'payment_review' where id = p_order_id;

  insert into order_status_history (order_id, old_status, new_status, actor_id, reason)
    values (p_order_id, v_order.status, 'payment_review', auth.uid(), 'payment proof submitted');

  insert into notifications (user_id, type, title, body, order_id)
    values (auth.uid(), 'payment_submitted', 'Payment under review',
            'We are verifying your payment. You will be notified shortly.', p_order_id);

  return v_payment_id;
end;
$$;

-- ------------------------------------------------------------
-- Admin verifies a payment. Moves order to vendor_confirmation.
-- ------------------------------------------------------------
create or replace function verify_payment(p_payment_id uuid, p_approved boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_payment record;
  v_order record;
begin
  if not is_admin() then raise exception 'forbidden'; end if;

  select * into v_payment from payments where id = p_payment_id;
  if not found then raise exception 'payment not found'; end if;
  select * into v_order from orders where id = v_payment.order_id;

  if p_approved then
    update payments set status = 'verified', verified_by = auth.uid(), verified_at = now()
      where id = p_payment_id;
    update orders set payment_status = 'verified', status = 'vendor_confirmation',
                      confirmed_at = now()
      where id = v_order.id;
    insert into order_status_history (order_id, old_status, new_status, actor_id, reason)
      values (v_order.id, v_order.status, 'vendor_confirmation', auth.uid(), 'payment verified');
    insert into notifications (user_id, type, title, body, order_id)
      values (v_order.customer_id, 'payment_verified', 'Payment verified',
              'Your order is confirmed and sent to the restaurant.', v_order.id);
  else
    update payments set status = 'rejected', rejection_reason = p_reason,
                        verified_by = auth.uid(), verified_at = now()
      where id = p_payment_id;
    update orders set payment_status = 'rejected', status = 'pending_payment' where id = v_order.id;
    insert into order_status_history (order_id, old_status, new_status, actor_id, reason)
      values (v_order.id, v_order.status, 'pending_payment', auth.uid(), coalesce(p_reason, 'payment rejected'));
    insert into notifications (user_id, type, title, body, order_id)
      values (v_order.customer_id, 'payment_rejected', 'Payment could not be verified',
              coalesce(p_reason, 'Please retry payment.'), v_order.id);
  end if;

  insert into admin_audit_logs (actor_id, action, entity, entity_id, reason)
    values (auth.uid(), case when p_approved then 'verify_payment' else 'reject_payment' end,
            'payment', p_payment_id::text, p_reason);
end;
$$;

-- ------------------------------------------------------------
-- Vendor accepts/rejects an order.
-- ------------------------------------------------------------
create or replace function vendor_set_order_status(p_order_id uuid, p_new order_status, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_order record;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then raise exception 'order not found'; end if;
  if not (is_admin() or is_vendor_member(v_order.vendor_id)) then
    raise exception 'forbidden';
  end if;

  -- Vendors may only move through these states.
  if p_new not in ('preparing', 'ready_for_pickup', 'rejected') then
    raise exception 'invalid status for vendor';
  end if;

  update orders set status = p_new where id = p_order_id;
  insert into order_status_history (order_id, old_status, new_status, actor_id, reason)
    values (p_order_id, v_order.status, p_new, auth.uid(), p_reason);
  insert into notifications (user_id, type, title, body, order_id)
    values (v_order.customer_id, 'order_update', 'Order ' || p_new::text,
            'Your order status has changed.', p_order_id);
end;
$$;

-- ------------------------------------------------------------
-- Atomic delivery acceptance. First valid caller wins; others get 'already assigned'.
-- ------------------------------------------------------------
create or replace function accept_delivery(p_order_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_partner uuid := auth.uid();
  v_assignment uuid;
  v_order record;
begin
  if v_partner is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from delivery_partner_profiles where user_id = v_partner and approved_at is not null) then
    raise exception 'partner not approved';
  end if;

  select * into v_order from orders where id = p_order_id for update;
  if not found then raise exception 'order not found'; end if;
  if v_order.status not in ('ready_for_pickup', 'preparing', 'vendor_confirmation') then
    raise exception 'order not available for pickup';
  end if;

  -- Atomic: the unique partial index on (order_id) where status='accepted'
  -- guarantees only one row survives.
  begin
    insert into delivery_assignments (order_id, partner_id, status, responded_at)
      values (p_order_id, v_partner, 'accepted', now())
      returning id into v_assignment;
  exception when unique_violation then
    raise exception 'order already assigned';
  end;

  update orders set status = 'assigned' where id = p_order_id;
  insert into order_status_history (order_id, old_status, new_status, actor_id, reason)
    values (p_order_id, v_order.status, 'assigned', v_partner, 'delivery accepted');

  insert into notifications (user_id, type, title, body, order_id)
    values (v_order.customer_id, 'delivery_assigned', 'Rider assigned',
            'A delivery partner has accepted your order.', p_order_id);

  return v_assignment;
end;
$$;

-- ------------------------------------------------------------
-- Delivery partner progresses their accepted order.
-- ------------------------------------------------------------
create or replace function partner_set_order_status(p_order_id uuid, p_new order_status)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_order record;
  v_fee integer;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then raise exception 'order not found'; end if;

  if not exists (
    select 1 from delivery_assignments
    where order_id = p_order_id and partner_id = auth.uid() and status = 'accepted'
  ) then
    raise exception 'not your delivery';
  end if;

  if p_new not in ('picked_up', 'out_for_delivery', 'delivered') then
    raise exception 'invalid status for partner';
  end if;

  update orders set status = p_new,
                    delivered_at = case when p_new = 'delivered' then now() else delivered_at end
    where id = p_order_id;

  insert into order_status_history (order_id, old_status, new_status, actor_id, reason)
    values (p_order_id, v_order.status, p_new, auth.uid(), null);

  insert into notifications (user_id, type, title, body, order_id)
    values (v_order.customer_id, 'order_update', 'Order ' || p_new::text,
            'Your order is on its way.', p_order_id);

  if p_new = 'delivered' then
    v_fee := v_order.delivery_fee_paise;  -- simple default policy: partner earns the fee
    insert into delivery_earnings (order_id, partner_id, gross_paise, net_paise)
      values (p_order_id, auth.uid(), v_fee, v_fee)
      on conflict (order_id) do nothing;
    update delivery_assignments set completed_at = now()
      where order_id = p_order_id and partner_id = auth.uid();
  end if;
end;
$$;
