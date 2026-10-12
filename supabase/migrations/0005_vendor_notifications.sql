-- Dastak: fan-out notifications to all vendor members on key order events.
-- Fires on orders INSERT and status changes.

create or replace function notify_vendor_members(p_vendor_id uuid, p_order_id uuid, p_type text, p_title text, p_body text)
returns void language plpgsql as $$
begin
  insert into notifications (user_id, type, title, body, order_id)
  select vm.user_id, p_type, p_title, p_body, p_order_id
  from vendor_members vm
  where vm.vendor_id = p_vendor_id and vm.status = 'active';
end;
$$;

create or replace function on_order_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    perform notify_vendor_members(new.vendor_id, new.id,
      'new_order', 'New order ' || new.order_number,
      'A customer placed an order. Awaiting payment verification.');
    return new;
  end if;

  if TG_OP = 'UPDATE' and old.status is distinct from new.status then
    if new.status = 'vendor_confirmation' then
      perform notify_vendor_members(new.vendor_id, new.id,
        'order_awaiting_vendor', 'Order ' || new.order_number || ' is paid',
        'Please accept or reject the order.');
    elsif new.status = 'cancelled' then
      perform notify_vendor_members(new.vendor_id, new.id,
        'order_cancelled', 'Order ' || new.order_number || ' cancelled',
        'The order was cancelled.');
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_vendor_on_order on orders;
create trigger trg_notify_vendor_on_order
  after insert or update on orders
  for each row execute function on_order_change();

-- Notify assigned delivery partner when the order progresses.
create or replace function on_assignment_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_order_number text;
begin
  if TG_OP = 'INSERT' and new.status = 'accepted' then
    select order_number into v_order_number from orders where id = new.order_id;
    insert into notifications (user_id, type, title, body, order_id)
    values (new.partner_id, 'delivery_assigned', 'Delivery assigned',
            'You accepted order ' || v_order_number || '.', new.order_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_partner_on_assignment on delivery_assignments;
create trigger trg_notify_partner_on_assignment
  after insert on delivery_assignments
  for each row execute function on_assignment_change();
