-- Review and test on staging. Additive schema; no production records deleted.
begin;

drop policy if exists "orders customer insert" on orders;
drop policy if exists "order_items customer insert" on order_items;
drop policy if exists "profiles self insert" on profiles;
drop policy if exists "profiles self update" on profiles;
create policy "profiles self update" on profiles for update
 using (id = auth.uid()) with check (id = auth.uid());

create or replace function is_vendor_member(vid uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from vendor_members vm join profiles p on p.id=vm.user_id
 where vm.vendor_id=vid and vm.user_id=auth.uid() and vm.status='active' and p.status='active');
$$;

-- Guard privileged fields even when an owner policy permits updating a row.
create function guard_mobile_identity() returns trigger
language plpgsql set search_path=public as $$
begin
 if auth.role()='service_role' or is_admin() or auth.uid() is null then return new; end if;
 if TG_TABLE_NAME='profiles' then
   if (new.role,new.status,new.phone_verified) is distinct from (old.role,old.status,old.phone_verified)
   then raise exception 'privileged profile fields'; end if;
 elsif TG_TABLE_NAME='delivery_partner_profiles' then
   if TG_OP='INSERT' then
     if new.approved_at is not null or new.approved_by is not null then raise exception 'approval is admin only'; end if;
   elsif (new.user_id,new.approved_at,new.approved_by,new.partner_qr_code) is distinct from
         (old.user_id,old.approved_at,old.approved_by,old.partner_qr_code) then raise exception 'approval is admin only'; end if;
 elsif TG_TABLE_NAME='partner_documents' then
   if TG_OP='INSERT' then
     if new.status<>'pending' or new.reviewer_id is not null or new.reviewed_at is not null then raise exception 'review is admin only'; end if;
   elsif (new.partner_id,new.status,new.reviewer_id,new.reviewed_at) is distinct from
         (old.partner_id,old.status,old.reviewer_id,old.reviewed_at) then raise exception 'review is admin only'; end if;
 end if;
 return new;
end; $$;
create trigger guard_profile before update on profiles for each row execute function guard_mobile_identity();
create trigger guard_partner before insert or update on delivery_partner_profiles for each row execute function guard_mobile_identity();
create trigger guard_document before insert or update on partner_documents for each row execute function guard_mobile_identity();

create function guard_vendor_profile_fields() returns trigger language plpgsql set search_path=public as $$
begin
 if is_admin() or auth.role()='service_role' or auth.uid() is null then return new; end if;
 if (to_jsonb(new)-array['description','dispatch_address','latitude','longitude','min_order_paise','prep_time_minutes','service_radius_km','opening_hours','is_active','updated_at'])
 is distinct from (to_jsonb(old)-array['description','dispatch_address','latitude','longitude','min_order_paise','prep_time_minutes','service_radius_km','opening_hours','is_active','updated_at'])
 then raise exception 'Store identity and ranking are managed by admin'; end if;
 return new;
end; $$;
create trigger guard_vendor_profile_fields before update on vendors for each row execute function guard_vendor_profile_fields();

alter view admin_overview_today set (security_invoker=true);
alter view admin_vendor_sales_today set (security_invoker=true);

create table checkout_attempts (
 customer_id uuid not null references profiles(id), request_id uuid not null,
 fingerprint text not null, order_id uuid references orders(id),
 created_at timestamptz not null default now(), primary key(customer_id,request_id)
);
alter table checkout_attempts enable row level security;
create policy "own attempts read" on checkout_attempts for select using(customer_id=auth.uid());

create function mobile_checkout_capabilities() returns jsonb language sql stable as $$
 select jsonb_build_object('version',case when exists(
 select 1 from app_settings where key='mobile_checkout_enabled' and value='true'::jsonb
 ) then 1 else 0 end,'server_pricing',true,'idempotent',true);
$$;
-- Enable only AFTER the upgraded Edge Function is deployed and tested.
insert into app_settings(key,value) values('mobile_checkout_enabled','false') on conflict do nothing;

-- Price resolver shared by quotes and order creation; no price supplied by client is used.
create function resolve_checkout(p_vendor_id uuid,p_items jsonb,p_distance numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v vendors; p products; i jsonb; opt product_options; opts jsonb; lines jsonb:='[]';
 qty integer; unit integer; subtotal integer:=0; fee integer; tax integer; pct numeric; ids uuid[];
begin
 select * into v from vendors where id=p_vendor_id and is_active;
 if not found then raise exception 'Store is unavailable'; end if;
 if p_distance is null or p_distance<0 or p_distance>v.service_radius_km then raise exception 'Outside delivery area'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Invalid cart'; end if;
 if (select count(*)<>count(distinct x->>'product_id') from jsonb_array_elements(p_items) x) then raise exception 'Duplicate product lines'; end if;
 -- Lock in deterministic order. A transaction reserves stock only when creating.
 perform id from products where id in(select (x->>'product_id')::uuid from jsonb_array_elements(p_items) x) order by id for update;
 for i in select * from jsonb_array_elements(p_items) loop
   select * into p from products where id=(i->>'product_id')::uuid and vendor_id=p_vendor_id and is_available;
   if not found then raise exception 'Product is unavailable'; end if;
   qty:=(i->>'quantity')::integer;
   if qty is null or qty not between 1 and 99 or (p.stock is not null and p.stock<qty) then raise exception 'Invalid quantity or insufficient stock'; end if;
   unit:=coalesce(p.sale_price_paise,p.price_paise); opts:='[]';
   if jsonb_typeof(coalesce(i->'options','[]'))<>'array' then raise exception 'Invalid options'; end if;
   ids:=array(select (x->>'option_id')::uuid from jsonb_array_elements(coalesce(i->'options','[]')) x);
   if cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception 'Duplicate options'; end if;
   if exists(select 1 from unnest(ids) x where x is null) then raise exception 'Option ID required'; end if;
   for opt in select * from product_options where id=any(ids) and product_id=p.id and is_available loop
     unit:=unit+opt.price_delta_paise;
     opts:=opts||jsonb_build_array(jsonb_build_object('option_id',opt.id,'label',opt.label,'price_delta_paise',opt.price_delta_paise));
   end loop;
   if jsonb_array_length(opts)<>cardinality(ids) or unit<0 then raise exception 'Option unavailable'; end if;
   subtotal:=subtotal+unit*qty;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',p.id,'product_name',p.name,'quantity',qty,'unit_price_paise',unit,'options',opts,'line_total_paise',unit*qty));
 end loop;
 if subtotal<v.min_order_paise then raise exception 'Store minimum order not met'; end if;
 fee:=calc_delivery_fee_paise(p_distance);
 if fee is null or fee<0 then raise exception 'Delivery rates unavailable'; end if;
 select (value #>> '{}')::numeric into pct from app_settings where key='tax_percent';
 if coalesce(pct,0) not between 0 and 100 then raise exception 'Invalid tax configuration'; end if;
 tax:=round(subtotal*coalesce(pct,0)/100);
 return jsonb_build_object('items',lines,'items_subtotal_paise',subtotal,'delivery_fee_paise',fee,
 'tax_paise',tax,'discount_paise',0,'total_payable_paise',subtotal+fee+tax);
end; $$;
revoke all on function resolve_checkout(uuid,jsonb,numeric) from public,anon,authenticated;
grant execute on function resolve_checkout(uuid,jsonb,numeric) to service_role;

-- The original distance-taking RPC must not be callable by untrusted clients.
revoke all on function create_order(uuid,text,numeric,numeric,numeric,text,jsonb,text) from public,anon,authenticated;

create function mobile_place_order(p_customer uuid,p_request uuid,p_vendor uuid,p_address text,
 p_lat numeric,p_lng numeric,p_distance numeric,p_items jsonb,p_note text,p_expected integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare q jsonb; i jsonb; oid uuid; fp text; attempt checkout_attempts;
begin
 if auth.role()<>'service_role' then raise exception 'Server only'; end if;
 if not exists(select 1 from profiles where id=p_customer and status='active') then raise exception 'Account not active'; end if;
 if p_request is null or length(trim(p_address))<8 or length(p_address)>1000 or p_lat not between -90 and 90 or p_lng not between -180 and 180
 or p_lat is null or p_lng is null then raise exception 'Invalid address or request'; end if;
 fp:=md5(jsonb_build_object('vendor',p_vendor,'address',p_address,'lat',p_lat,'lng',p_lng,'items',p_items,'note',p_note,'expected',p_expected)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_customer::text||p_request::text,0));
 select * into attempt from checkout_attempts where customer_id=p_customer and request_id=p_request;
 if found then
   if attempt.fingerprint<>fp then raise exception 'Request already used for a different checkout'; end if;
   return attempt.order_id;
 end if;
 q:=resolve_checkout(p_vendor,p_items,p_distance);
 if p_expected is not null and p_expected<>(q->>'total_payable_paise')::integer then raise exception 'Price changed. Review a new quote.'; end if;
 insert into orders(customer_id,vendor_id,category,destination_address,destination_lat,destination_lng,
 delivery_distance_km,delivery_fee_paise,delivery_route_provider,items_subtotal_paise,tax_paise,total_payable_paise,
 payment_method,payment_status,status,customer_note)
 select p_customer,p_vendor,category,p_address,p_lat,p_lng,p_distance,(q->>'delivery_fee_paise')::integer,'google',
 (q->>'items_subtotal_paise')::integer,(q->>'tax_paise')::integer,(q->>'total_payable_paise')::integer,
 'upi_qr','unpaid','pending_payment',p_note from vendors where id=p_vendor returning id into oid;
 for i in select * from jsonb_array_elements(q->'items') loop
   insert into order_items(order_id,product_id,product_name,unit_price_paise,quantity,options,line_total_paise)
   values(oid,(i->>'product_id')::uuid,i->>'product_name',(i->>'unit_price_paise')::integer,(i->>'quantity')::integer,i->'options',(i->>'line_total_paise')::integer);
   update products set stock=stock-(i->>'quantity')::integer where id=(i->>'product_id')::uuid and stock is not null;
 end loop;
 insert into order_status_history(order_id,new_status,actor_id,reason) values(oid,'pending_payment',p_customer,'Order created');
 insert into notifications(user_id,type,title,body,order_id) values(p_customer,'order_created','Order placed','Complete UPI payment to confirm.',oid);
 insert into checkout_attempts(customer_id,request_id,fingerprint,order_id) values(p_customer,p_request,fp,oid);
 return oid;
end; $$;
revoke all on function mobile_place_order(uuid,uuid,uuid,text,numeric,numeric,numeric,jsonb,text,integer) from public,anon,authenticated;
grant execute on function mobile_place_order(uuid,uuid,uuid,text,numeric,numeric,numeric,jsonb,text,integer) to service_role;

-- Serialize and validate status transitions regardless of which RPC performs the update.
create function guard_order_transition() returns trigger language plpgsql set search_path=public as $$
begin
 if old.status=new.status then return new; end if;
 if not (
 (old.status='pending_payment' and new.status='payment_review') or
 (old.status='payment_review' and new.status in ('pending_payment','vendor_confirmation')) or
 (old.status='vendor_confirmation' and new.status in ('preparing','rejected')) or
 (old.status='preparing' and new.status='ready_for_pickup') or
 (old.status='ready_for_pickup' and new.status='assigned') or
 (old.status='assigned' and new.status='picked_up') or
 (old.status='picked_up' and new.status='out_for_delivery') or
 (old.status='out_for_delivery' and new.status='delivered') or
 (new.status='cancelled' and old.status in ('pending_payment','payment_review','vendor_confirmation','preparing','ready_for_pickup','assigned'))
 ) then raise exception 'Invalid order status transition'; end if;
 if new.status in ('preparing','ready_for_pickup','assigned','picked_up','out_for_delivery','delivered') and new.payment_status<>'verified'
 then raise exception 'Payment is not verified'; end if;
 new.updated_at:=now();
 return new;
end; $$;
create trigger guard_order_transition before update on orders for each row execute function guard_order_transition();

create function guard_delivery_accept() returns trigger language plpgsql set search_path=public as $$
begin
 if new.status='accepted' then
   perform 1 from profiles where id=new.partner_id for update;
   if not exists(select 1 from profiles p join delivery_partner_profiles d on d.user_id=p.id
     where p.id=new.partner_id and p.role='delivery' and p.status='active' and d.approved_at is not null and d.is_online)
   then raise exception 'Partner must be approved, active and online'; end if;
   if exists(select 1 from delivery_assignments a join orders o on o.id=a.order_id
     where a.partner_id=new.partner_id and a.status='accepted' and o.status in('assigned','picked_up','out_for_delivery') and a.id<>new.id)
   then raise exception 'Complete your active delivery first'; end if;
 end if;
 return new;
end; $$;
create trigger guard_delivery_accept before insert on delivery_assignments for each row execute function guard_delivery_accept();

create or replace function submit_payment_proof(p_order_id uuid,p_upi_reference text,p_proof_image_path text)
returns uuid language plpgsql security definer set search_path=public as $$
declare o orders; pid uuid;
begin
 select * into o from orders where id=p_order_id and customer_id=auth.uid() for update;
 if not found or o.status<>'pending_payment' or o.payment_status not in('unpaid','rejected') then raise exception 'Order not eligible'; end if;
 if trim(p_upi_reference) !~ '^[0-9]{12}$' or p_upi_reference is null then raise exception 'Enter the 12-digit UPI reference'; end if;
 perform pg_advisory_xact_lock(hashtextextended(trim(p_upi_reference),1));
 if exists(select 1 from payments where upi_reference=trim(p_upi_reference) and status in('submitted','verified')) then raise exception 'Reference already submitted'; end if;
 insert into payments(order_id,amount_paise,upi_reference,proof_image_path) values(p_order_id,o.total_payable_paise,trim(p_upi_reference),p_proof_image_path) returning id into pid;
 update orders set status='payment_review',payment_status='submitted' where id=p_order_id;
 insert into order_status_history(order_id,old_status,new_status,actor_id,reason) values(p_order_id,o.status,'payment_review',auth.uid(),'UPI reference submitted, not verified');
 insert into notifications(user_id,type,title,order_id) values(auth.uid(),'payment_submitted','Payment under review',p_order_id);
 return pid;
end; $$;

create function guard_payment_review() returns trigger language plpgsql set search_path=public as $$
begin
 if old.status<>'submitted' then raise exception 'Payment already reviewed'; end if;
 if new.status in('verified','rejected') and old.status='submitted' then
   perform 1 from orders where id=new.order_id and status='payment_review' for update;
   if not found then raise exception 'Order is not awaiting payment review'; end if;
 end if;
 return new;
end; $$;
create trigger guard_payment_review before update on payments for each row execute function guard_payment_review();

-- Inventory reservation is released once on cancellation/rejection.
create function release_cancelled_stock() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status in('cancelled','rejected') and old.status not in('cancelled','rejected')
 and exists(select 1 from checkout_attempts where order_id=new.id) then
   update products p set stock=p.stock+i.quantity from order_items i where i.order_id=new.id and p.id=i.product_id and p.stock is not null;
 end if;
 return new;
end; $$;
create trigger release_cancelled_stock after update on orders for each row execute function release_cancelled_stock();

create function mobile_admin_metrics() returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 return (select to_jsonb(t) from admin_overview_today t);
end; $$;

create function admin_review_document(p_id uuid,p_approved boolean) returns void language plpgsql security definer set search_path=public as $$
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 update partner_documents set status=case when p_approved then 'active'::account_status else 'rejected'::account_status end,
 reviewer_id=auth.uid(),reviewed_at=now() where id=p_id and status='pending';
 if not found then raise exception 'Document already reviewed or missing'; end if;
 insert into admin_audit_logs(actor_id,action,entity,entity_id) values(auth.uid(),'review_document','partner_documents',p_id::text);
end; $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('product-images','product-images',true,5242880,array['image/jpeg','image/png','image/webp']),
 ('partner-docs','partner-docs',false,5242880,array['image/jpeg','image/png','image/webp']),
 ('payment-qr','payment-qr',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy "mobile product image read" on storage.objects for select using(bucket_id='product-images');
create policy "mobile product image write" on storage.objects for insert to authenticated with check(
 bucket_id='product-images' and (is_admin() or exists(select 1 from vendors v where v.id::text=(storage.foldername(name))[1] and is_vendor_member(v.id))));
create policy "mobile partner document read" on storage.objects for select to authenticated using(
 bucket_id='partner-docs' and ((storage.foldername(name))[1]=auth.uid()::text or is_admin()));
create policy "mobile partner document upload" on storage.objects for insert to authenticated with check(
 bucket_id='partner-docs' and (storage.foldername(name))[1]=auth.uid()::text);
-- Live audit found legacy QR write policies that authorized every signed-in user.
drop policy if exists "qr_admin_insert" on storage.objects;
drop policy if exists "qr_delete" on storage.objects;
create policy "mobile payment qr read" on storage.objects for select using(bucket_id='payment-qr');
create policy "mobile payment qr upload" on storage.objects for insert to authenticated with check(bucket_id='payment-qr' and is_admin());
create policy "mobile payment qr delete" on storage.objects for delete to authenticated using(bucket_id='payment-qr' and is_admin());

-- Add tables to Realtime only if not already published.
do $$ declare t text; begin
 foreach t in array array['orders','products','notifications','delivery_assignments'] loop
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
 select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t)
 then execute format('alter publication supabase_realtime add table public.%I',t); end if;
 end loop;
end $$;
-- A partner cannot submit another user's private object for an admin to open.
drop policy if exists "partner docs self" on partner_documents;
create policy "partner docs read" on partner_documents for select using(partner_id=auth.uid() or is_admin());
create policy "partner docs insert" on partner_documents for insert with check(
 (partner_id=auth.uid() and split_part(file_path,'/',1)=auth.uid()::text and status='pending') or is_admin());
create policy "partner docs admin update" on partner_documents for update using(is_admin()) with check(is_admin());

create or replace function admin_replace_rate_table(p_rows jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare r jsonb; boundary numeric:=0; ceiling numeric;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 100 then raise exception 'Invalid rate table'; end if;
 select ceiling_km into ceiling from delivery_overflow_rule where id;
 for r in select * from jsonb_array_elements(p_rows) x order by (x->>'min_km')::numeric loop
  if (r->>'min_km')::numeric is distinct from boundary or (r->>'max_km')::numeric<=boundary
   or (r->>'fee_paise')::integer<0 or r->>'fee_paise' is null then raise exception 'Rates must be contiguous, increasing and nonnegative'; end if;
  boundary:=(r->>'max_km')::numeric;
 end loop;
 if boundary is distinct from ceiling then raise exception 'Final rate must match overflow ceiling'; end if;
 delete from delivery_rate_rules;
 insert into delivery_rate_rules(min_km,max_km,fee_paise,is_active)
 select (x->>'min_km')::numeric,(x->>'max_km')::numeric,(x->>'fee_paise')::integer,true from jsonb_array_elements(p_rows) x;
 insert into admin_audit_logs(actor_id,action,entity,payload) values(auth.uid(),'replace_rate_table','delivery_rate_rules',p_rows);
end; $$;

-- Suspended partners cannot continue delivery status mutations.
create function guard_partner_order_actor() returns trigger language plpgsql set search_path=public as $$
begin
 if new.status is distinct from old.status and new.status in('picked_up','out_for_delivery','delivered') then
  if not exists(select 1 from profiles where id=auth.uid() and role='delivery' and status='active') then raise exception 'Partner account is not active'; end if;
 end if;
 return new;
end; $$;
create trigger guard_partner_order_actor before update on orders for each row execute function guard_partner_order_actor();

-- Audit administrative table edits without logging sensitive documents or keys.
create function audit_mobile_admin_edit() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if is_admin() then insert into admin_audit_logs(actor_id,action,entity,entity_id)
 values(auth.uid(),lower(TG_OP),TG_TABLE_NAME,coalesce(to_jsonb(new)->>'id',to_jsonb(new)->>'key')); end if;
 return new;
end; $$;
create trigger audit_vendor_edit after insert or update on vendors for each row execute function audit_mobile_admin_edit();
create trigger audit_product_edit after insert or update on products for each row execute function audit_mobile_admin_edit();
create trigger audit_payment_settings after update on payment_settings for each row execute function audit_mobile_admin_edit();
create trigger audit_app_settings after update on app_settings for each row execute function audit_mobile_admin_edit();

create or replace function vendor_set_order_status(p_order_id uuid,p_new order_status,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare o orders;
begin
 select * into o from orders where id=p_order_id for update;
 if not found or not(is_admin() or is_vendor_member(o.vendor_id)) then raise exception 'Forbidden'; end if;
 if not((o.status='vendor_confirmation' and p_new in('preparing','rejected')) or (o.status='preparing' and p_new='ready_for_pickup')) then raise exception 'Invalid vendor transition'; end if;
 if p_new='rejected' and coalesce(length(trim(p_reason)),0)=0 then raise exception 'Rejection reason required'; end if;
 update orders set status=p_new where id=p_order_id;
 insert into order_status_history(order_id,old_status,new_status,actor_id,reason) values(p_order_id,o.status,p_new,auth.uid(),p_reason);
 insert into notifications(user_id,type,title,order_id) values(o.customer_id,'order_update','Order '||p_new::text,p_order_id);
end; $$;
create or replace function partner_set_order_status(p_order_id uuid,p_new order_status)
returns void language plpgsql security definer set search_path=public as $$
declare o orders;
begin
 select * into o from orders where id=p_order_id for update;
 if not found or not exists(select 1 from delivery_assignments where order_id=p_order_id and partner_id=auth.uid() and status='accepted') then raise exception 'Not your delivery'; end if;
 if not((o.status='assigned' and p_new='picked_up') or (o.status='picked_up' and p_new='out_for_delivery') or (o.status='out_for_delivery' and p_new='delivered')) then raise exception 'Invalid delivery transition'; end if;
 update orders set status=p_new,delivered_at=case when p_new='delivered' then now() else delivered_at end where id=p_order_id;
 insert into order_status_history(order_id,old_status,new_status,actor_id) values(p_order_id,o.status,p_new,auth.uid());
 insert into notifications(user_id,type,title,order_id) values(o.customer_id,'order_update','Order '||p_new::text,p_order_id);
 if p_new='delivered' then
  insert into delivery_earnings(order_id,partner_id,gross_paise,net_paise) values(p_order_id,auth.uid(),o.delivery_fee_paise,o.delivery_fee_paise);
  update delivery_assignments set completed_at=now() where order_id=p_order_id and partner_id=auth.uid() and status='accepted';
 end if;
end; $$;
commit;
