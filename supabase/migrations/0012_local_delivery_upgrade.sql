-- Local Delivery upgrade: partner onboarding, payouts, ratings, posters, store hours,
-- location-aware discovery, live rider location, dashboards and admin tooling.
-- Additive: no table is dropped and no existing row is deleted. Review on staging first.
begin;

-- =====================================================================
-- Shared helpers
-- =====================================================================

-- Statements executed inside SECURITY DEFINER functions run as the function owner,
-- so guards can trust them while still blocking direct client (authenticated/anon) writes.
create or replace function is_trusted_context() returns boolean
language sql stable as $$ select current_user not in ('authenticated','anon') $$;

create or replace function local_day_start(p_at timestamptz default now()) returns timestamptz
language sql stable as $$ select date_trunc('day', p_at at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' $$;

create or replace function mask_phone(p text) returns text language sql immutable as $$
  select case when p is null or length(regexp_replace(p,'\D','','g'))<4 then null
  else repeat('•', length(regexp_replace(p,'\D','','g'))-4) || right(regexp_replace(p,'\D','','g'),4) end
$$;

create or replace function app_setting_number(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path=public as $$
  select coalesce((select case when jsonb_typeof(value)='number' then (value #>> '{}')::numeric end
                   from app_settings where key=p_key), p_default)
$$;

create or replace function notify_admins(p_type text, p_title text, p_body text, p_order uuid default null)
returns void language sql security definer set search_path=public as $$
  insert into notifications(user_id,type,title,body,order_id)
  select id,p_type,p_title,p_body,p_order from profiles where role='admin' and status='active';
$$;
revoke all on function notify_admins(text,text,text,uuid) from public,anon,authenticated;

create or replace function order_status_label(s order_status) returns text language sql immutable as $$
  select case s
    when 'pending_payment' then 'Awaiting payment'
    when 'payment_review' then 'Payment under review'
    when 'vendor_confirmation' then 'Waiting for restaurant'
    when 'preparing' then 'Restaurant is preparing your food'
    when 'ready_for_pickup' then 'Ready for pickup'
    when 'assigned' then 'Delivery partner assigned'
    when 'picked_up' then 'Order picked up'
    when 'out_for_delivery' then 'Out for delivery'
    when 'delivered' then 'Delivered'
    when 'rejected' then 'Rejected by restaurant'
    when 'cancelled' then 'Order cancelled'
    when 'refunded' then 'Refunded'
    else replace(s::text,'_',' ') end
$$;

insert into app_settings(key,value) values
  ('partner_earning_percent','100'),
  ('partner_earning_bonus_paise','0'),
  ('platform_commission_percent','0')
on conflict do nothing;

-- Existing guards: let trusted SECURITY DEFINER workflows through.
create or replace function guard_mobile_identity() returns trigger
language plpgsql set search_path=public as $$
begin
 if is_trusted_context() or auth.role()='service_role' or is_admin() or auth.uid() is null then return new; end if;
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

-- =====================================================================
-- Restaurants: hours, temporary closure, archive, owner applications
-- =====================================================================

alter table vendors
  add column if not exists temporarily_closed boolean not null default false,
  add column if not exists closed_reason text,
  add column if not exists archived_at timestamptz,
  add column if not exists city text,
  add column if not exists postal_code text,
  add column if not exists contact_phone text,
  add column if not exists contact_email text,
  add column if not exists cuisine text;

-- opening_hours: {"timezone":"Asia/Kolkata","weekly":{"1":[["09:00","23:00"]],...,"7":[...]},"holidays":["2026-10-20"]}
-- ISO weekday keys (1 = Monday). A close time earlier than the open time spans midnight.
-- An empty/missing weekly schedule means hours are not configured: the store follows its manual open switch.
create or replace function valid_opening_hours(h jsonb) returns boolean language plpgsql stable as $$
declare k text; slot jsonb; tz text;
begin
 if h is null or h='{}'::jsonb then return true; end if;
 if jsonb_typeof(h)<>'object' then return false; end if;
 tz := coalesce(h->>'timezone','Asia/Kolkata');
 if not exists(select 1 from pg_timezone_names where name=tz) then return false; end if;
 if h ? 'weekly' then
   if jsonb_typeof(h->'weekly')<>'object' then return false; end if;
   for k in select jsonb_object_keys(h->'weekly') loop
     if k !~ '^[1-7]$' or jsonb_typeof(h->'weekly'->k)<>'array' or jsonb_array_length(h->'weekly'->k)>4 then return false; end if;
     for slot in select * from jsonb_array_elements(h->'weekly'->k) loop
       if jsonb_typeof(slot)<>'array' or jsonb_array_length(slot)<>2
          or slot->>0 !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or slot->>1 !~ '^([01][0-9]|2[0-4]):[0-5][0-9]$' then return false; end if;
     end loop;
   end loop;
 end if;
 if h ? 'holidays' then
   if jsonb_typeof(h->'holidays')<>'array' or jsonb_array_length(h->'holidays')>366 then return false; end if;
   if exists(select 1 from jsonb_array_elements_text(h->'holidays') d where d !~ '^\d{4}-\d{2}-\d{2}$') then return false; end if;
 end if;
 return true;
end; $$;

create or replace function vendor_is_open(p_hours jsonb, p_active boolean, p_temp_closed boolean, p_at timestamptz default now())
returns boolean language plpgsql stable as $$
declare tz text; loc timestamp; d date; t time; dow int; prev int; slot jsonb; o time; c time; hol jsonb;
begin
 if not coalesce(p_active,false) or coalesce(p_temp_closed,false) then return false; end if;
 if p_hours is null or jsonb_typeof(p_hours->'weekly') is distinct from 'object' or p_hours->'weekly'='{}'::jsonb then return true; end if;
 tz := coalesce(nullif(p_hours->>'timezone',''),'Asia/Kolkata');
 loc := p_at at time zone tz; d := loc::date; t := loc::time; dow := extract(isodow from loc)::int;
 prev := case when dow=1 then 7 else dow-1 end;
 hol := coalesce(p_hours->'holidays','[]'::jsonb);
 if not (hol ? d::text) then
   for slot in select * from jsonb_array_elements(coalesce(p_hours->'weekly'->(dow::text),'[]'::jsonb)) loop
     o := (slot->>0)::time; c := (slot->>1)::time;
     if o < c and t >= o and t < c then return true; end if;
     if o >= c and t >= o then return true; end if;
   end loop;
 end if;
 if not (hol ? (d-1)::text) then
   for slot in select * from jsonb_array_elements(coalesce(p_hours->'weekly'->(prev::text),'[]'::jsonb)) loop
     o := (slot->>0)::time; c := (slot->>1)::time;
     if o >= c and t < c then return true; end if;
   end loop;
 end if;
 return false;
end; $$;

create or replace function guard_vendor_profile_fields() returns trigger language plpgsql set search_path=public as $$
declare editable text[] := array['description','dispatch_address','latitude','longitude','min_order_paise','prep_time_minutes',
  'service_radius_km','opening_hours','is_active','updated_at','temporarily_closed','closed_reason','contact_phone','contact_email','cuisine','city','postal_code',
  'cover_image_path','logo_image_path'];
begin
 if not valid_opening_hours(new.opening_hours) then raise exception 'Invalid opening hours'; end if;
 if TG_OP='UPDATE' and not (is_trusted_context() or is_admin()) and (
    (new.cover_image_path is distinct from old.cover_image_path and new.cover_image_path is not null and split_part(new.cover_image_path,'/',1)<>new.id::text)
    or (new.logo_image_path is distinct from old.logo_image_path and new.logo_image_path is not null and split_part(new.logo_image_path,'/',1)<>new.id::text))
 then raise exception 'Images must be uploaded to this restaurant folder'; end if;
 if new.closed_reason is not null and length(new.closed_reason)>160 then raise exception 'Closed note is too long'; end if;
 if is_trusted_context() or is_admin() or auth.role()='service_role' or auth.uid() is null then return new; end if;
 if (to_jsonb(new)-editable) is distinct from (to_jsonb(old)-editable)
 then raise exception 'Store identity and ranking are managed by admin'; end if;
 return new;
end; $$;
drop trigger if exists guard_vendor_insert_hours on vendors;
create trigger guard_vendor_insert_hours before insert on vendors for each row execute function guard_vendor_profile_fields();

create table if not exists vendor_applications (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references profiles(id) on delete cascade,
  restaurant_name text not null, owner_name text not null, phone text not null, email text,
  address text not null, city text not null, postal_code text not null,
  category vendor_category not null default 'food', cuisine text,
  latitude numeric(9,6), longitude numeric(9,6), location_source text check (location_source in ('gps','map_pin','manual')),
  opening_hours jsonb not null default '{}'::jsonb, prep_time_minutes integer not null default 20,
  min_order_paise integer not null default 0, service_radius_km numeric(5,2) not null default 5,
  notes text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','action_required')),
  review_reason text, reviewed_by uuid references profiles(id), reviewed_at timestamptz,
  vendor_id uuid references vendors(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists vendor_applications_one_open on vendor_applications(applicant_id) where status in ('pending','action_required');
alter table vendor_applications enable row level security;
drop policy if exists "vendor applications read" on vendor_applications;
create policy "vendor applications read" on vendor_applications for select using (applicant_id=auth.uid() or is_admin());

create or replace function submit_vendor_application(p jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); app vendor_applications; lat numeric; lng numeric; result uuid;
begin
 if me is null then raise exception 'Please sign in'; end if;
 if not exists(select 1 from profiles where id=me and status='active' and role in ('customer','vendor')) then
   raise exception 'This account cannot register a restaurant'; end if;
 if length(trim(coalesce(p->>'restaurant_name',''))) not between 2 and 80 then raise exception 'Enter the restaurant name'; end if;
 if length(trim(coalesce(p->>'owner_name',''))) not between 2 and 80 then raise exception 'Enter the owner name'; end if;
 if regexp_replace(coalesce(p->>'phone',''),'\D','','g') !~ '^\d{10}$' then raise exception 'Enter a 10-digit contact number'; end if;
 if coalesce(p->>'email','')<>'' and p->>'email' !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Enter a valid email'; end if;
 if length(trim(coalesce(p->>'address',''))) not between 10 and 300 then raise exception 'Enter the full restaurant address'; end if;
 if length(trim(coalesce(p->>'city',''))) not between 2 and 60 then raise exception 'Enter the city'; end if;
 if coalesce(p->>'postal_code','') !~ '^\d{6}$' then raise exception 'Enter a 6-digit PIN code'; end if;
 lat := nullif(p->>'latitude','')::numeric; lng := nullif(p->>'longitude','')::numeric;
 if lat is null or lng is null or lat not between -90 and 90 or lng not between -180 and 180 then raise exception 'Set the restaurant location on the map'; end if;
 if not valid_opening_hours(coalesce(p->'opening_hours','{}'::jsonb)) then raise exception 'Invalid opening hours'; end if;
 if coalesce((p->>'prep_time_minutes')::int,20) not between 5 and 180 then raise exception 'Preparation time must be 5–180 minutes'; end if;
 if coalesce((p->>'service_radius_km')::numeric,5) not between 0.5 and 30 then raise exception 'Delivery radius must be 0.5–30 km'; end if;
 if coalesce((p->>'min_order_paise')::int,0) not between 0 and 1000000 then raise exception 'Invalid minimum order'; end if;
 select * into app from vendor_applications where applicant_id=me and status in ('pending','action_required') for update;
 if found and app.status='pending' then raise exception 'Your application is already under review'; end if;
 if found then
   update vendor_applications set restaurant_name=trim(p->>'restaurant_name'), owner_name=trim(p->>'owner_name'),
     phone=regexp_replace(p->>'phone','\D','','g'), email=nullif(trim(coalesce(p->>'email','')),''), address=trim(p->>'address'),
     city=trim(p->>'city'), postal_code=p->>'postal_code', cuisine=nullif(trim(coalesce(p->>'cuisine','')),''),
     latitude=lat, longitude=lng, location_source=coalesce(p->>'location_source','manual'),
     opening_hours=coalesce(p->'opening_hours','{}'::jsonb), prep_time_minutes=coalesce((p->>'prep_time_minutes')::int,20),
     min_order_paise=coalesce((p->>'min_order_paise')::int,0), service_radius_km=coalesce((p->>'service_radius_km')::numeric,5),
     notes=left(nullif(trim(coalesce(p->>'notes','')),''),500), status='pending', review_reason=null, updated_at=now()
   where id=app.id returning id into result;
 else
   insert into vendor_applications(applicant_id,restaurant_name,owner_name,phone,email,address,city,postal_code,cuisine,latitude,longitude,
     location_source,opening_hours,prep_time_minutes,min_order_paise,service_radius_km,notes)
   values(me,trim(p->>'restaurant_name'),trim(p->>'owner_name'),regexp_replace(p->>'phone','\D','','g'),nullif(trim(coalesce(p->>'email','')),''),
     trim(p->>'address'),trim(p->>'city'),p->>'postal_code',nullif(trim(coalesce(p->>'cuisine','')),''),lat,lng,coalesce(p->>'location_source','manual'),
     coalesce(p->'opening_hours','{}'::jsonb),coalesce((p->>'prep_time_minutes')::int,20),coalesce((p->>'min_order_paise')::int,0),
     coalesce((p->>'service_radius_km')::numeric,5),left(nullif(trim(coalesce(p->>'notes','')),''),500))
   returning id into result;
 end if;
 perform notify_admins('vendor_application','New restaurant registration', trim(p->>'restaurant_name')||' is awaiting review.', null);
 return result;
end; $$;

create or replace function admin_review_vendor_application(p_id uuid, p_decision text, p_reason text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare app vendor_applications; vid uuid;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 select * into app from vendor_applications where id=p_id for update;
 if not found then raise exception 'Application not found'; end if;
 if app.status<>'pending' then raise exception 'Application already reviewed'; end if;
 if p_decision not in ('approve','reject','request_changes') then raise exception 'Invalid decision'; end if;
 if p_decision<>'approve' and length(trim(coalesce(p_reason,'')))<3 then raise exception 'A reason is required'; end if;
 if p_decision='approve' then
   insert into vendors(name,category,description,dispatch_address,latitude,longitude,min_order_paise,prep_time_minutes,
     service_radius_km,opening_hours,is_active,city,postal_code,contact_phone,contact_email,cuisine)
   values(app.restaurant_name,app.category,app.cuisine,app.address,app.latitude,app.longitude,app.min_order_paise,app.prep_time_minutes,
     app.service_radius_km,app.opening_hours,false,app.city,app.postal_code,app.phone,app.email,app.cuisine)
   returning id into vid;
   update profiles set role='vendor' where id=app.applicant_id and role='customer';
   insert into vendor_members(user_id,vendor_id,role,status) values(app.applicant_id,vid,'owner','active')
     on conflict (user_id,vendor_id) do update set status='active';
   update vendor_applications set status='approved',vendor_id=vid,reviewed_by=auth.uid(),reviewed_at=now(),review_reason=p_reason,updated_at=now() where id=p_id;
   insert into notifications(user_id,type,title,body) values(app.applicant_id,'vendor_application','Restaurant approved',
     'Add your menu, then switch on "Accept new orders" in your restaurant workspace.');
 else
   update vendor_applications set status=case when p_decision='reject' then 'rejected' else 'action_required' end,
     reviewed_by=auth.uid(),reviewed_at=now(),review_reason=trim(p_reason),updated_at=now() where id=p_id;
   insert into notifications(user_id,type,title,body) values(app.applicant_id,'vendor_application',
     case when p_decision='reject' then 'Restaurant application rejected' else 'Restaurant application needs changes' end, trim(p_reason));
 end if;
 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(auth.uid(),'vendor_application_'||p_decision,'vendor_applications',p_id::text,p_reason);
 return vid;
end; $$;

create or replace function admin_set_vendor_state(p_vendor uuid, p_state text, p_reason text default null) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 if p_state not in ('active','inactive','archived','restore') then raise exception 'Invalid state'; end if;
 if p_state in ('inactive','archived') and length(trim(coalesce(p_reason,'')))<3 then raise exception 'A reason is required'; end if;
 update vendors set is_active = case when p_state='active' then true when p_state in ('inactive','archived') then false else is_active end,
   archived_at = case when p_state='archived' then now() when p_state='restore' then null else archived_at end,
   updated_at=now() where id=p_vendor;
 if not found then raise exception 'Restaurant not found'; end if;
 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(auth.uid(),'vendor_'||p_state,'vendors',p_vendor::text,p_reason);
 insert into notifications(user_id,type,title,body)
   select user_id,'vendor_status','Restaurant status updated','Status: '||p_state||coalesce(' — '||p_reason,'') from vendor_members where vendor_id=p_vendor and status='active';
end; $$;

-- Customer discovery: active, non-archived stores that can serve the chosen point.
-- Distance here is straight-line; checkout re-checks the road distance server-side.
create or replace function discover_stores(p_lat numeric default null, p_lng numeric default null,
  p_search text default '', p_category text default 'food', p_page integer default 0)
returns jsonb language sql stable security definer set search_path=public as $$
  with base as (
    select v.*, case when p_lat is null or p_lng is null then null
                     else round(haversine_km(p_lat,p_lng,v.latitude,v.longitude)::numeric,2) end as distance_km
    from vendors v
    where v.is_active and v.archived_at is null
      and (p_category is null or v.category::text=p_category)
      and (coalesce(p_search,'')='' or v.name ilike '%'||replace(replace(p_search,'%',''),'_','')||'%'
           or coalesce(v.cuisine,'') ilike '%'||replace(replace(p_search,'%',''),'_','')||'%')
  ), ranked as (
    select b.*, vendor_is_open(b.opening_hours,b.is_active,b.temporarily_closed) as is_open from base b
    where b.distance_km is null or b.distance_km<=b.service_radius_km
    order by vendor_is_open(b.opening_hours,b.is_active,b.temporarily_closed) desc, b.sort_priority, b.distance_km nulls last, b.name
    offset greatest(p_page,0)*30 limit 30
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'name',r.name,'category',r.category,'description',r.description,'cuisine',r.cuisine,
    'dispatch_address',r.dispatch_address,'latitude',r.latitude,'longitude',r.longitude,
    'cover_image_path',r.cover_image_path,'logo_image_path',r.logo_image_path,'min_order_paise',r.min_order_paise,
    'prep_time_minutes',r.prep_time_minutes,'service_radius_km',r.service_radius_km,'rating_avg',r.rating_avg,
    'rating_count',r.rating_count,'is_active',r.is_active,'is_open',r.is_open,'temporarily_closed',r.temporarily_closed,
    'closed_reason',r.closed_reason,'opening_hours',r.opening_hours,'distance_km',r.distance_km,
    'preview',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'price_paise',coalesce(p.sale_price_paise,p.price_paise),
        'image_path',p.image_path,'diet',p.diet,'available',(p.stock is null or p.stock>0)) order by p.sort_priority,p.name)
      from (select * from products where vendor_id=r.id and is_available order by sort_priority,name limit 4) p),'[]'::jsonb)
  ) order by r.is_open desc, r.sort_priority, r.distance_km nulls last, r.name),'[]'::jsonb) from ranked r
$$;
grant execute on function discover_stores(numeric,numeric,text,text,integer) to anon,authenticated;

create or replace function store_status(p_vendor uuid) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('is_open',vendor_is_open(opening_hours,is_active,temporarily_closed),'is_active',is_active,
    'temporarily_closed',temporarily_closed,'closed_reason',closed_reason,'opening_hours',opening_hours,
    'rating_avg',rating_avg,'rating_count',rating_count)
  from vendors where id=p_vendor and archived_at is null
$$;
grant execute on function store_status(uuid) to anon,authenticated;

-- =====================================================================
-- Payment configuration: enable switch and change history
-- =====================================================================

alter table payment_settings
  add column if not exists upi_enabled boolean not null default true,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists payment_settings_history (
  id uuid primary key default gen_random_uuid(),
  changed_by uuid references profiles(id),
  old_value jsonb, new_value jsonb,
  created_at timestamptz not null default now()
);
alter table payment_settings_history enable row level security;
drop policy if exists "payment history admin" on payment_settings_history;
create policy "payment history admin" on payment_settings_history for select using (is_admin());

create or replace function record_payment_settings_change() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if to_jsonb(new) is distinct from to_jsonb(old) then
   insert into payment_settings_history(changed_by,old_value,new_value) values(auth.uid(),to_jsonb(old),to_jsonb(new));
 end if;
 return new;
end; $$;
drop trigger if exists record_payment_settings_change on payment_settings;
create trigger record_payment_settings_change after update on payment_settings for each row execute function record_payment_settings_change();

-- Checkout price resolver: unchanged pricing, plus open-hours and payment-availability checks.
create or replace function resolve_checkout(p_vendor_id uuid,p_items jsonb,p_distance numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v vendors; p products; i jsonb; opt product_options; opts jsonb; lines jsonb:='[]';
 qty integer; unit integer; subtotal integer:=0; fee integer; tax integer; pct numeric; ids uuid[];
begin
 select * into v from vendors where id=p_vendor_id and is_active and archived_at is null;
 if not found then raise exception 'Store is unavailable'; end if;
 if not vendor_is_open(v.opening_hours,v.is_active,v.temporarily_closed) then raise exception 'Store is closed right now'; end if;
 if not coalesce((select upi_enabled from payment_settings where id),false) then raise exception 'Online payment is temporarily unavailable'; end if;
 if p_distance is null or p_distance<0 or p_distance>v.service_radius_km then raise exception 'Outside delivery area'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Invalid cart'; end if;
 if (select count(*)<>count(distinct x->>'product_id') from jsonb_array_elements(p_items) x) then raise exception 'Duplicate product lines'; end if;
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

create or replace function on_payment_submitted() returns trigger language plpgsql security definer set search_path=public as $$
declare num text;
begin
 select order_number into num from orders where id=new.order_id;
 perform notify_admins('payment_review','Payment awaiting verification',
   'Order '||coalesce(num,'')||' • UPI reference '||coalesce(new.upi_reference,'—'), new.order_id);
 return new;
end; $$;
drop trigger if exists on_payment_submitted on payments;
create trigger on_payment_submitted after insert on payments for each row execute function on_payment_submitted();

-- =====================================================================
-- Delivery partner onboarding and verification
-- =====================================================================

alter table delivery_partner_profiles
  add column if not exists verification_status text not null default 'draft',
  add column if not exists legal_name text,
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists residential_address text,
  add column if not exists city text,
  add column if not exists service_area text,
  add column if not exists emergency_contact_name text,
  add column if not exists emergency_contact_phone text,
  add column if not exists licence_last4 text,
  add column if not exists aadhaar_last4 text,
  add column if not exists payout_upi_vpa text,
  add column if not exists bank_account_last4 text,
  add column if not exists bank_ifsc text,
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists submitted_at timestamptz,
  add column if not exists review_reason text,
  add column if not exists reviewed_by uuid references profiles(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists qr_image_path text,
  add column if not exists qr_status text not null default 'none',
  add column if not exists qr_review_reason text,
  add column if not exists qr_reviewed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

do $$ begin
 if not exists(select 1 from pg_constraint where conname='dpp_verification_status_check') then
   alter table delivery_partner_profiles add constraint dpp_verification_status_check
     check (verification_status in ('draft','pending_verification','approved','rejected','action_required','suspended'));
 end if;
 if not exists(select 1 from pg_constraint where conname='dpp_qr_status_check') then
   alter table delivery_partner_profiles add constraint dpp_qr_status_check check (qr_status in ('none','pending','approved','rejected'));
 end if;
end $$;

-- Backfill existing partners from the old approval/status model.
update delivery_partner_profiles d set verification_status = case
  when p.status='suspended' then 'suspended'
  when p.status='rejected' then 'rejected'
  when d.approved_at is not null then 'approved'
  when exists(select 1 from partner_documents x where x.partner_id=d.user_id) then 'pending_verification'
  else 'draft' end
from profiles p where p.id=d.user_id and d.verification_status='draft';

alter table partner_documents add column if not exists review_reason text;

do $$ begin
 if exists(select 1 from delivery_partner_profiles where coalesce(vehicle_number,'')<>''
           group by upper(regexp_replace(vehicle_number,'\s|-','','g')) having count(*)>1) then
   raise notice 'Duplicate vehicle numbers exist; unique index skipped until they are resolved';
 else
   create unique index if not exists dpp_vehicle_unique
     on delivery_partner_profiles (upper(regexp_replace(vehicle_number,'\s|-','','g'))) where coalesce(vehicle_number,'')<>'';
 end if;
end $$;

create table if not exists partner_verification_events (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references profiles(id) on delete cascade,
  actor_id uuid references profiles(id),
  event text not null,
  from_status text, to_status text, reason text,
  created_at timestamptz not null default now()
);
create index if not exists partner_events_partner_idx on partner_verification_events(partner_id, created_at desc);
alter table partner_verification_events enable row level security;
drop policy if exists "partner events read" on partner_verification_events;
create policy "partner events read" on partner_verification_events for select using (partner_id=auth.uid() or is_admin());

create or replace function guard_partner_application() returns trigger language plpgsql set search_path=public as $$
begin
 if is_trusted_context() or is_admin() then return new; end if;
 if TG_OP='INSERT' then
   if new.verification_status<>'draft' or new.qr_status<>'none' or new.qr_image_path is not null or new.reviewed_by is not null
   then raise exception 'Use the partner application form'; end if;
   return new;
 end if;
 if (new.verification_status,new.qr_status,new.qr_image_path,new.qr_review_reason,new.qr_reviewed_at,new.review_reason,
     new.reviewed_by,new.reviewed_at,new.submitted_at,new.terms_accepted_at)
    is distinct from (old.verification_status,old.qr_status,old.qr_image_path,old.qr_review_reason,old.qr_reviewed_at,old.review_reason,
     old.reviewed_by,old.reviewed_at,old.submitted_at,old.terms_accepted_at)
 then raise exception 'Verification fields are managed by the review workflow'; end if;
 if old.verification_status not in ('draft','action_required','rejected')
    and (to_jsonb(new)-array['is_online','last_seen','updated_at']) is distinct from (to_jsonb(old)-array['is_online','last_seen','updated_at'])
 then raise exception 'Submitted profiles can only change through a new review'; end if;
 return new;
end; $$;
drop trigger if exists guard_partner_application on delivery_partner_profiles;
create trigger guard_partner_application before insert or update on delivery_partner_profiles
  for each row execute function guard_partner_application();

create or replace function partner_event(p_partner uuid, p_event text, p_from text, p_to text, p_reason text)
returns void language sql security definer set search_path=public as $$
  insert into partner_verification_events(partner_id,actor_id,event,from_status,to_status,reason)
  values(p_partner,auth.uid(),p_event,p_from,p_to,p_reason);
$$;
revoke all on function partner_event(uuid,text,text,text,text) from public,anon,authenticated;

create or replace function partner_save_application(p jsonb, p_submit boolean default false) returns text
language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); prof profiles; d delivery_partner_profiles; vehicle text; vtype text; phone_digits text; emergency text;
begin
 if me is null then raise exception 'Please sign in'; end if;
 select * into prof from profiles where id=me for update;
 if prof.role not in ('customer','delivery') then raise exception 'This account cannot register as a delivery partner'; end if;
 if prof.status<>'active' then raise exception 'Your account is not active'; end if;
 insert into delivery_partner_profiles(user_id) values(me) on conflict do nothing;
 select * into d from delivery_partner_profiles where user_id=me for update;
 if d.verification_status not in ('draft','action_required','rejected') then
   raise exception 'Your application is % and cannot be edited now', replace(d.verification_status,'_',' '); end if;

 vtype := nullif(trim(coalesce(p->>'vehicle_type','')),'');
 vehicle := nullif(upper(regexp_replace(coalesce(p->>'vehicle_number',''),'\s|-','','g')),'');
 phone_digits := nullif(right(regexp_replace(coalesce(p->>'phone',''),'\D','','g'),10),'');
 emergency := nullif(right(regexp_replace(coalesce(p->>'emergency_contact_phone',''),'\D','','g'),10),'');
 if vtype is not null and vtype not in ('bicycle','e_bike','scooter','motorcycle','car') then raise exception 'Choose a valid vehicle type'; end if;
 if vehicle is not null and vehicle !~ '^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{1,4}$' then raise exception 'Enter a valid vehicle registration number'; end if;
 if vehicle is not null and exists(select 1 from delivery_partner_profiles where user_id<>me and upper(regexp_replace(coalesce(vehicle_number,''),'\s|-','','g'))=vehicle)
   then raise exception 'This vehicle is already registered with another partner'; end if;
 if phone_digits is not null and exists(select 1 from delivery_partner_profiles where user_id<>me and phone=phone_digits)
   then raise exception 'This mobile number is already registered with another partner'; end if;
 if coalesce(p->>'licence_last4','')<>'' and upper(p->>'licence_last4') !~ '^[A-Z0-9]{4}$' then raise exception 'Enter only the last 4 characters of the licence'; end if;
 if coalesce(p->>'aadhaar_last4','')<>'' and p->>'aadhaar_last4' !~ '^[0-9]{4}$' then raise exception 'Enter only the last 4 digits of Aadhaar'; end if;
 if coalesce(p->>'bank_account_last4','')<>'' and p->>'bank_account_last4' !~ '^[0-9]{4}$' then raise exception 'Enter only the last 4 digits of the bank account'; end if;
 if coalesce(p->>'bank_ifsc','')<>'' and upper(p->>'bank_ifsc') !~ '^[A-Z]{4}0[A-Z0-9]{6}$' then raise exception 'Enter a valid IFSC'; end if;
 if coalesce(p->>'payout_upi_vpa','')<>'' and p->>'payout_upi_vpa' !~ '^[A-Za-z0-9._-]{2,64}@[A-Za-z]{2,32}$' then raise exception 'Enter a valid UPI ID'; end if;
 if coalesce(p->>'email','')<>'' and p->>'email' !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Enter a valid email'; end if;
 if length(coalesce(p->>'residential_address',''))>300 or length(coalesce(p->>'legal_name',''))>80
    or length(coalesce(p->>'service_area',''))>120 or length(coalesce(p->>'city',''))>60 then raise exception 'One of the fields is too long'; end if;

 update delivery_partner_profiles set
   legal_name=nullif(trim(coalesce(p->>'legal_name','')),''), phone=phone_digits, email=nullif(lower(trim(coalesce(p->>'email',''))),''),
   residential_address=nullif(trim(coalesce(p->>'residential_address','')),''), city=nullif(trim(coalesce(p->>'city','')),''),
   service_area=nullif(trim(coalesce(p->>'service_area','')),''),
   emergency_contact_name=nullif(trim(coalesce(p->>'emergency_contact_name','')),''), emergency_contact_phone=emergency,
   vehicle_type=vtype, vehicle_number=vehicle, licence_last4=nullif(upper(coalesce(p->>'licence_last4','')),''),
   aadhaar_last4=nullif(coalesce(p->>'aadhaar_last4',''),''), payout_upi_vpa=nullif(trim(coalesce(p->>'payout_upi_vpa','')),''),
   bank_account_last4=nullif(coalesce(p->>'bank_account_last4',''),''), bank_ifsc=nullif(upper(coalesce(p->>'bank_ifsc','')),''),
   updated_at=now()
 where user_id=me;

 if not p_submit then return d.verification_status; end if;

 select * into d from delivery_partner_profiles where user_id=me;
 if length(coalesce(d.legal_name,''))<2 then raise exception 'Enter your full name'; end if;
 if d.phone is null or d.phone !~ '^[6-9][0-9]{9}$' then raise exception 'Enter a valid 10-digit mobile number'; end if;
 if length(coalesce(d.residential_address,''))<10 then raise exception 'Enter your full residential address'; end if;
 if d.city is null or d.service_area is null then raise exception 'Enter your city and service area'; end if;
 if d.emergency_contact_name is null or d.emergency_contact_phone is null then raise exception 'Add an emergency contact'; end if;
 if d.emergency_contact_phone=d.phone then raise exception 'Emergency contact must be a different number'; end if;
 if d.vehicle_type is null then raise exception 'Choose your vehicle type'; end if;
 if d.vehicle_type not in ('bicycle') and d.vehicle_number is null then raise exception 'Enter the vehicle registration number'; end if;
 if d.vehicle_type not in ('bicycle','e_bike') and d.licence_last4 is null then raise exception 'Enter the last 4 characters of your driving licence'; end if;
 if d.aadhaar_last4 is null then raise exception 'Enter the last 4 digits of your Aadhaar'; end if;
 if d.payout_upi_vpa is null and d.bank_account_last4 is null then raise exception 'Add a UPI ID or bank account for payouts'; end if;
 if coalesce((p->>'accept_terms')::boolean,false) is not true then raise exception 'Accept the partner terms and privacy policy'; end if;
 if d.profile_photo_path is null then raise exception 'Upload a profile photo'; end if;
 if not exists(select 1 from partner_documents where partner_id=me and doc_type='aadhaar' and status in ('pending','active'))
   then raise exception 'Upload your Aadhaar document'; end if;
 if d.vehicle_type not in ('bicycle','e_bike') and not exists(select 1 from partner_documents where partner_id=me and doc_type='driving_license' and status in ('pending','active'))
   then raise exception 'Upload your driving licence'; end if;

 update delivery_partner_profiles set verification_status='pending_verification', submitted_at=now(), terms_accepted_at=now(),
   review_reason=null, updated_at=now() where user_id=me;
 update profiles set role='delivery', display_name=coalesce(nullif(display_name,''),d.legal_name), phone=coalesce(phone,d.phone)
   where id=me and role='customer';
 perform partner_event(me,'application_submitted',d.verification_status,'pending_verification',null);
 perform notify_admins('partner_application','Delivery partner application', d.legal_name||' submitted documents for verification.', null);
 return 'pending_verification';
end; $$;

create or replace function partner_submit_document(p_doc_type text, p_path text, p_masked text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); d delivery_partner_profiles; doc uuid;
begin
 if me is null then raise exception 'Please sign in'; end if;
 select * into d from delivery_partner_profiles where user_id=me for update;
 if not found then raise exception 'Start your partner application first'; end if;
 if d.verification_status='suspended' then raise exception 'Your partner account is suspended'; end if;
 if p_doc_type not in ('profile_photo','driving_license','aadhaar','vehicle_rc','other') then raise exception 'Invalid document type'; end if;
 if p_path is null or split_part(p_path,'/',1)<>me::text or p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$' then raise exception 'Invalid document file'; end if;
 if p_masked is not null and p_masked !~ '^[A-Za-z0-9]{4}$' then raise exception 'Enter only the last 4 characters'; end if;
 if not exists(select 1 from storage.objects where bucket_id='partner-docs' and name=p_path) then raise exception 'Upload the file first'; end if;
 if p_doc_type='profile_photo' then
   update delivery_partner_profiles set profile_photo_path=p_path, updated_at=now() where user_id=me;
 end if;
 insert into partner_documents(partner_id,doc_type,file_path,masked_reference,status)
   values(me,p_doc_type,p_path,upper(p_masked),'pending') returning id into doc;
 perform partner_event(me,'document_uploaded',null,null,p_doc_type);
 if d.verification_status in ('pending_verification','approved') then
   perform notify_admins('partner_document','Partner document uploaded', coalesce(d.legal_name,'A partner')||' uploaded '||replace(p_doc_type,'_',' ')||'.', null);
 end if;
 return doc;
end; $$;

create or replace function partner_submit_qr(p_path text) returns void
language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); d delivery_partner_profiles;
begin
 select * into d from delivery_partner_profiles where user_id=me for update;
 if not found then raise exception 'Start your partner application first'; end if;
 if d.verification_status='suspended' then raise exception 'Your partner account is suspended'; end if;
 if p_path is null or split_part(p_path,'/',1)<>me::text or p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$' then raise exception 'Invalid QR file'; end if;
 if not exists(select 1 from storage.objects where bucket_id='partner-docs' and name=p_path) then raise exception 'Upload the file first'; end if;
 update delivery_partner_profiles set qr_image_path=p_path, qr_status='pending', qr_review_reason=null, qr_reviewed_at=null, updated_at=now() where user_id=me;
 perform partner_event(me,'qr_submitted',d.qr_status,'pending',null);
 perform notify_admins('partner_qr','Payout QR submitted', coalesce(d.legal_name,'A partner')||' submitted a payout QR for review.', null);
end; $$;

create or replace function admin_review_partner(p_partner uuid, p_decision text, p_reason text default null) returns text
language plpgsql security definer set search_path=public as $$
declare d delivery_partner_profiles; next_status text; title text;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 select * into d from delivery_partner_profiles where user_id=p_partner for update;
 if not found then raise exception 'Partner not found'; end if;
 if p_decision not in ('approve','reject','request_changes','suspend','reactivate') then raise exception 'Invalid decision'; end if;
 if p_decision in ('reject','request_changes','suspend') and length(trim(coalesce(p_reason,'')))<3 then raise exception 'A reason is required'; end if;
 if p_decision='approve' and d.verification_status not in ('pending_verification','action_required','rejected') then
   raise exception 'Only submitted applications can be approved'; end if;
 if p_decision='reactivate' and d.verification_status<>'suspended' then raise exception 'Only suspended partners can be reactivated'; end if;
 next_status := case p_decision when 'approve' then 'approved' when 'reactivate' then 'approved' when 'reject' then 'rejected'
   when 'request_changes' then 'action_required' else 'suspended' end;
 update delivery_partner_profiles set verification_status=next_status, review_reason=nullif(trim(coalesce(p_reason,'')),''),
   reviewed_by=auth.uid(), reviewed_at=now(),
   approved_at=case when next_status='approved' then coalesce(approved_at,now()) else null end,
   approved_by=case when next_status='approved' then coalesce(approved_by,auth.uid()) else null end,
   is_online=case when next_status='approved' then is_online else false end, updated_at=now()
 where user_id=p_partner;
 update profiles set role='delivery', status=case when next_status='suspended' then 'suspended'::account_status else 'active'::account_status end
   where id=p_partner and role in ('customer','delivery');
 perform partner_event(p_partner,'review_'||p_decision,d.verification_status,next_status,p_reason);
 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(auth.uid(),'partner_'||p_decision,'delivery_partner_profiles',p_partner::text,p_reason);
 title := case next_status when 'approved' then 'You are approved to deliver' when 'rejected' then 'Partner application rejected'
   when 'action_required' then 'Action required on your application' else 'Partner account suspended' end;
 insert into notifications(user_id,type,title,body) values(p_partner,'partner_verification',title,
   coalesce(nullif(trim(coalesce(p_reason,'')),''),'Open your partner dashboard for details.'));
 return next_status;
end; $$;

-- Keep the legacy status RPC consistent with the new verification states.
create or replace function admin_set_partner_status(p_user_id uuid, p_status account_status) returns void
language plpgsql security definer set search_path=public as $$
declare cur text;
begin
 if not is_admin() then raise exception 'forbidden'; end if;
 select verification_status into cur from delivery_partner_profiles where user_id=p_user_id;
 if p_status='active' then
   perform admin_review_partner(p_user_id, case when cur='suspended' then 'reactivate' else 'approve' end, null);
 elsif p_status='suspended' then perform admin_review_partner(p_user_id,'suspend','Suspended by admin');
 elsif p_status='rejected' then perform admin_review_partner(p_user_id,'reject','Rejected by admin');
 else raise exception 'Unsupported status'; end if;
end; $$;

create or replace function admin_review_partner_document(p_id uuid, p_approved boolean, p_reason text default null) returns void
language plpgsql security definer set search_path=public as $$
declare doc partner_documents;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 if not p_approved and length(trim(coalesce(p_reason,'')))<3 then raise exception 'A reason is required'; end if;
 update partner_documents set status=case when p_approved then 'active'::account_status else 'rejected'::account_status end,
   reviewer_id=auth.uid(), reviewed_at=now(), review_reason=nullif(trim(coalesce(p_reason,'')),'')
 where id=p_id and status='pending' returning * into doc;
 if not found then raise exception 'Document already reviewed or missing'; end if;
 perform partner_event(doc.partner_id, case when p_approved then 'document_accepted' else 'document_rejected' end, null, null,
   doc.doc_type||coalesce(': '||p_reason,''));
 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(auth.uid(),'review_document','partner_documents',p_id::text,p_reason);
 if not p_approved then
   insert into notifications(user_id,type,title,body) values(doc.partner_id,'partner_verification',
     'Document needs correction', replace(doc.doc_type,'_',' ')||': '||trim(p_reason));
 end if;
end; $$;

create or replace function admin_review_partner_qr(p_partner uuid, p_approved boolean, p_reason text default null) returns void
language plpgsql security definer set search_path=public as $$
declare d delivery_partner_profiles;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 if not p_approved and length(trim(coalesce(p_reason,'')))<3 then raise exception 'A reason is required'; end if;
 select * into d from delivery_partner_profiles where user_id=p_partner for update;
 if not found or d.qr_status<>'pending' then raise exception 'No QR awaiting review'; end if;
 update delivery_partner_profiles set qr_status=case when p_approved then 'approved' else 'rejected' end,
   qr_review_reason=nullif(trim(coalesce(p_reason,'')),''), qr_reviewed_at=now(), updated_at=now() where user_id=p_partner;
 perform partner_event(p_partner, case when p_approved then 'qr_approved' else 'qr_rejected' end, 'pending',
   case when p_approved then 'approved' else 'rejected' end, p_reason);
 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(auth.uid(),
   case when p_approved then 'approve_partner_qr' else 'reject_partner_qr' end,'delivery_partner_profiles',p_partner::text,p_reason);
 insert into notifications(user_id,type,title,body) values(p_partner,'partner_qr',
   case when p_approved then 'Payout QR approved' else 'Please upload a new payout QR' end, coalesce(p_reason,'Your payout QR was reviewed.'));
end; $$;

-- Partners may go online only when approved and active.
create or replace function set_partner_online(p_online boolean) returns void
language plpgsql security definer set search_path=public as $$
begin
 if p_online and not exists(select 1 from delivery_partner_profiles d join profiles p on p.id=d.user_id
   where d.user_id=auth.uid() and d.verification_status='approved' and d.approved_at is not null and p.status='active' and p.role='delivery')
 then raise exception 'Your partner account is not approved for deliveries yet'; end if;
 update delivery_partner_profiles set is_online=p_online, last_seen=now() where user_id=auth.uid();
 if not found then raise exception 'Partner profile not found'; end if;
end; $$;

create or replace function guard_delivery_accept() returns trigger language plpgsql set search_path=public as $$
begin
 if new.status='accepted' then
   perform 1 from profiles where id=new.partner_id for update;
   if not exists(select 1 from profiles p join delivery_partner_profiles d on d.user_id=p.id
     where p.id=new.partner_id and p.role='delivery' and p.status='active' and d.approved_at is not null
       and d.verification_status='approved' and d.is_online)
   then raise exception 'Partner must be approved, active and online'; end if;
   if exists(select 1 from delivery_assignments a join orders o on o.id=a.order_id
     where a.partner_id=new.partner_id and a.status='accepted' and o.status in('assigned','picked_up','out_for_delivery') and a.id<>new.id)
   then raise exception 'Complete your active delivery first'; end if;
 end if;
 return new;
end; $$;

-- =====================================================================
-- Earnings rules, payouts and delivery completion
-- =====================================================================

create table if not exists partner_payouts (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references profiles(id) on delete restrict,
  amount_paise integer not null check (amount_paise>0),
  period_start timestamptz, period_end timestamptz,
  method text not null check (method in ('upi','bank_transfer','cash','other')),
  reference text,
  status text not null default 'pending' check (status in ('pending','processing','paid','failed')),
  notes text, failed_reason text,
  created_by uuid not null references profiles(id),
  confirmed_by uuid references profiles(id),
  paid_at timestamptz,
  idempotency_key uuid not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists partner_payouts_partner_idx on partner_payouts(partner_id, created_at desc);
alter table partner_payouts enable row level security;
drop policy if exists "payouts read" on partner_payouts;
create policy "payouts read" on partner_payouts for select using (partner_id=auth.uid() or is_admin());

alter table delivery_earnings add column if not exists payout_id uuid references partner_payouts(id);
alter table delivery_earnings add column if not exists rule jsonb;

create or replace function partner_earning_for_fee(p_fee integer) returns integer language sql stable security definer set search_path=public as $$
  select greatest(0, round(p_fee * least(greatest(app_setting_number('partner_earning_percent',100),0),100) / 100.0)::integer
    + greatest(app_setting_number('partner_earning_bonus_paise',0),0)::integer)
$$;

create or replace function admin_create_payout(p_partner uuid, p_until timestamptz, p_method text, p_notes text, p_key uuid) returns uuid
language plpgsql security definer set search_path=public as $$
declare existing partner_payouts; total bigint; first_at timestamptz; last_at timestamptz; pid uuid;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 if p_key is null then raise exception 'Idempotency key required'; end if;
 if p_method not in ('upi','bank_transfer','cash','other') then raise exception 'Invalid payout method'; end if;
 perform pg_advisory_xact_lock(hashtextextended('payout:'||p_partner::text,0));
 select * into existing from partner_payouts where idempotency_key=p_key;
 if found then
   if existing.partner_id<>p_partner then raise exception 'Idempotency key already used'; end if;
   return existing.id;
 end if;
 select coalesce(sum(net_paise),0), min(created_at), max(created_at) into total, first_at, last_at
   from delivery_earnings where partner_id=p_partner and payout_id is null and not settled and created_at<=coalesce(p_until,now());
 if total<=0 then raise exception 'No unpaid earnings for this partner'; end if;
 insert into partner_payouts(partner_id,amount_paise,period_start,period_end,method,notes,created_by,idempotency_key)
   values(p_partner,total,first_at,last_at,p_method,left(nullif(trim(coalesce(p_notes,'')),''),500),auth.uid(),p_key) returning id into pid;
 update delivery_earnings set payout_id=pid where partner_id=p_partner and payout_id is null and not settled and created_at<=coalesce(p_until,now());
 insert into admin_audit_logs(actor_id,action,entity,entity_id,payload) values(auth.uid(),'create_payout','partner_payouts',pid::text,
   jsonb_build_object('partner',p_partner,'amount_paise',total));
 insert into notifications(user_id,type,title,body) values(p_partner,'payout','Payout being prepared',
   'A payout of ₹'||to_char(total/100.0,'FM999999990.00')||' was created. It is not paid until marked paid with a transaction reference.');
 return pid;
end; $$;

create or replace function admin_update_payout(p_id uuid, p_status text, p_reference text default null, p_notes text default null) returns void
language plpgsql security definer set search_path=public as $$
declare po partner_payouts;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 select * into po from partner_payouts where id=p_id for update;
 if not found then raise exception 'Payout not found'; end if;
 if not ((po.status='pending' and p_status in ('processing','paid','failed')) or (po.status='processing' and p_status in ('paid','failed'))) then
   raise exception 'Payout cannot move from % to %', po.status, p_status; end if;
 if p_status='paid' and length(trim(coalesce(p_reference,'')))<4 then raise exception 'Enter the bank/UPI transaction reference'; end if;
 if p_status='failed' and length(trim(coalesce(p_notes,'')))<3 then raise exception 'Enter the failure reason'; end if;
 if p_status='paid' and exists(select 1 from partner_payouts where reference=trim(p_reference) and id<>p_id and status='paid') then
   raise exception 'This transaction reference is already recorded'; end if;
 update partner_payouts set status=p_status, reference=coalesce(nullif(trim(coalesce(p_reference,'')),''),reference),
   notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes),
   failed_reason=case when p_status='failed' then trim(p_notes) else failed_reason end,
   paid_at=case when p_status='paid' then now() else paid_at end,
   confirmed_by=case when p_status='paid' then auth.uid() else confirmed_by end, updated_at=now()
 where id=p_id;
 if p_status='paid' then
   update delivery_earnings set settled=true, settled_at=now() where payout_id=p_id;
 elsif p_status='failed' then
   update delivery_earnings set payout_id=null where payout_id=p_id and not settled;
 end if;
 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(auth.uid(),'payout_'||p_status,'partner_payouts',p_id::text,coalesce(p_reference,p_notes));
 insert into notifications(user_id,type,title,body) values(po.partner_id,'payout',
   case p_status when 'paid' then 'Payout paid' when 'failed' then 'Payout failed' else 'Payout processing' end,
   '₹'||to_char(po.amount_paise/100.0,'FM999999990.00')||case when p_status='paid' then ' • Ref '||trim(p_reference) when p_status='failed' then ' • '||trim(p_notes) else '' end);
end; $$;

create or replace function partner_set_order_status(p_order_id uuid,p_new order_status)
returns void language plpgsql security definer set search_path=public as $$
declare o orders; earning integer;
begin
 select * into o from orders where id=p_order_id for update;
 if not found or not exists(select 1 from delivery_assignments where order_id=p_order_id and partner_id=auth.uid() and status='accepted') then raise exception 'Not your delivery'; end if;
 if not((o.status='assigned' and p_new='picked_up') or (o.status='picked_up' and p_new='out_for_delivery') or (o.status='out_for_delivery' and p_new='delivered')) then raise exception 'Invalid delivery transition'; end if;
 update orders set status=p_new,delivered_at=case when p_new='delivered' then now() else delivered_at end where id=p_order_id;
 insert into order_status_history(order_id,old_status,new_status,actor_id,reason) values(p_order_id,o.status,p_new,auth.uid(),
   case when p_new='delivered' then 'Delivery confirmed by partner' end);
 insert into notifications(user_id,type,title,body,order_id) values(o.customer_id,'order_update',order_status_label(p_new),'Order '||o.order_number,p_order_id);
 if p_new in ('picked_up','delivered') then
   insert into notifications(user_id,type,title,body,order_id)
     select user_id,'order_update',order_status_label(p_new),'Order '||o.order_number,p_order_id from vendor_members where vendor_id=o.vendor_id and status='active';
 end if;
 if p_new='delivered' then
  earning := partner_earning_for_fee(o.delivery_fee_paise);
  insert into delivery_earnings(order_id,partner_id,gross_paise,net_paise,rule)
    values(p_order_id,auth.uid(),earning,earning,jsonb_build_object('fee_paise',o.delivery_fee_paise,
      'percent',app_setting_number('partner_earning_percent',100),'bonus_paise',app_setting_number('partner_earning_bonus_paise',0)));
  update delivery_assignments set completed_at=now() where order_id=p_order_id and partner_id=auth.uid() and status='accepted';
  insert into notifications(user_id,type,title,body,order_id) values(auth.uid(),'earning','Delivery completed',
    'You earned ₹'||to_char(earning/100.0,'FM999999990.00')||' for order '||o.order_number,p_order_id);
 end if;
end; $$;

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
 insert into notifications(user_id,type,title,body,order_id) values(o.customer_id,'order_update',order_status_label(p_new),
   coalesce(p_reason,'Order '||o.order_number),p_order_id);
 if p_new='ready_for_pickup' then
   insert into notifications(user_id,type,title,body,order_id)
   select d.user_id,'delivery_offer','New delivery available','Pickup from your area • order '||o.order_number,p_order_id
   from delivery_partner_profiles d join profiles p on p.id=d.user_id
   where d.is_online and d.verification_status='approved' and p.status='active'
     and not exists(select 1 from delivery_assignments a join orders x on x.id=a.order_id
       where a.partner_id=d.user_id and a.status='accepted' and x.status in ('assigned','picked_up','out_for_delivery'));
 end if;
end; $$;

create or replace function on_assignment_change() returns trigger language plpgsql security definer set search_path=public as $$
declare o orders; pname text;
begin
 if TG_OP='INSERT' and new.status='accepted' then
   select * into o from orders where id=new.order_id;
   select display_name into pname from profiles where id=new.partner_id;
   insert into notifications(user_id,type,title,body,order_id) values(new.partner_id,'delivery_assigned','Delivery assigned',
     'Pick up order '||o.order_number||'.',new.order_id);
   insert into notifications(user_id,type,title,body,order_id)
     select user_id,'delivery_assigned','Delivery partner assigned',coalesce(pname,'A partner')||' will pick up order '||o.order_number,new.order_id
     from vendor_members where vendor_id=o.vendor_id and status='active';
 end if;
 return new;
end; $$;

-- Admin corrections may cancel in-transit orders (for example a failed delivery).
create or replace function guard_order_transition() returns trigger language plpgsql set search_path=public as $$
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
 (new.status='cancelled' and old.status in ('pending_payment','payment_review','vendor_confirmation','preparing','ready_for_pickup','assigned')) or
 (new.status='cancelled' and old.status in ('picked_up','out_for_delivery') and is_admin())
 ) then raise exception 'Invalid order status transition'; end if;
 if new.status in ('preparing','ready_for_pickup','assigned','picked_up','out_for_delivery','delivered') and new.payment_status<>'verified'
 then raise exception 'Payment is not verified'; end if;
 new.updated_at:=now();
 return new;
end; $$;

create or replace function admin_cancel_order(p_order_id uuid, p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare o orders;
begin
 if not is_admin() then raise exception 'forbidden'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'A reason is required'; end if;
 select * into o from orders where id=p_order_id for update;
 if not found then raise exception 'order not found'; end if;
 update orders set status='cancelled' where id=p_order_id;
 insert into order_status_history(order_id,old_status,new_status,actor_id,reason) values(p_order_id,o.status,'cancelled',auth.uid(),p_reason);
 insert into notifications(user_id,type,title,body,order_id) values(o.customer_id,'order_cancelled','Order cancelled',p_reason,p_order_id);
 insert into notifications(user_id,type,title,body,order_id)
   select partner_id,'order_cancelled','Delivery cancelled','Order '||o.order_number||': '||p_reason,p_order_id
   from delivery_assignments where order_id=p_order_id and status='accepted';
 update delivery_assignments set status='cancelled', responded_at=now() where order_id=p_order_id and status='accepted';
 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(auth.uid(),'cancel_order','order',p_order_id::text,p_reason);
end; $$;

-- =====================================================================
-- Live partner location (only while a delivery is in progress)
-- =====================================================================

create table if not exists partner_locations (
  partner_id uuid primary key references profiles(id) on delete cascade,
  order_id uuid references orders(id) on delete set null,
  latitude numeric(9,6) not null, longitude numeric(9,6) not null,
  accuracy_m numeric,
  updated_at timestamptz not null default now()
);
alter table partner_locations enable row level security;
drop policy if exists "locations admin read" on partner_locations;
create policy "locations admin read" on partner_locations for select using (is_admin() or partner_id=auth.uid());

create or replace function partner_update_location(p_order_id uuid, p_lat numeric, p_lng numeric, p_accuracy numeric default null) returns void
language plpgsql security definer set search_path=public as $$
begin
 if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Invalid location'; end if;
 if not exists(select 1 from delivery_assignments a join orders o on o.id=a.order_id
   where a.order_id=p_order_id and a.partner_id=auth.uid() and a.status='accepted' and o.status in ('assigned','picked_up','out_for_delivery'))
 then raise exception 'Location sharing is only allowed during your active delivery'; end if;
 insert into partner_locations(partner_id,order_id,latitude,longitude,accuracy_m,updated_at)
   values(auth.uid(),p_order_id,p_lat,p_lng,p_accuracy,now())
 on conflict (partner_id) do update set order_id=excluded.order_id, latitude=excluded.latitude, longitude=excluded.longitude,
   accuracy_m=excluded.accuracy_m, updated_at=now();
end; $$;

create or replace function partner_stop_location() returns void language sql security definer set search_path=public as $$
  delete from partner_locations where partner_id=auth.uid();
$$;

create or replace function order_live_location(p_order_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare o orders; loc partner_locations;
begin
 select * into o from orders where id=p_order_id;
 if not found or not (o.customer_id=auth.uid() or is_admin() or is_vendor_member(o.vendor_id)) then raise exception 'Forbidden'; end if;
 if o.status not in ('assigned','picked_up','out_for_delivery') then return null; end if;
 select l.* into loc from partner_locations l join delivery_assignments a on a.partner_id=l.partner_id and a.order_id=p_order_id and a.status='accepted'
   where l.order_id=p_order_id and l.updated_at>now()-interval '10 minutes';
 if not found then return null; end if;
 return jsonb_build_object('latitude',loc.latitude,'longitude',loc.longitude,'accuracy_m',loc.accuracy_m,'updated_at',loc.updated_at);
end; $$;

create or replace function clear_location_on_finish() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status is distinct from old.status and new.status in ('delivered','cancelled','refunded','rejected') then
   delete from partner_locations where order_id=new.id;
 end if;
 return new;
end; $$;
drop trigger if exists clear_location_on_finish on orders;
create trigger clear_location_on_finish after update on orders for each row execute function clear_location_on_finish();

-- =====================================================================
-- Ratings and reviews
-- =====================================================================

alter table reviews
  add column if not exists vendor_reply text,
  add column if not exists vendor_replied_at timestamptz,
  add column if not exists reported_reason text,
  add column if not exists updated_at timestamptz;

create table if not exists partner_reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references orders(id) on delete cascade,
  customer_id uuid not null references profiles(id) on delete cascade,
  partner_id uuid not null references profiles(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text check (comment is null or length(comment)<=500),
  moderation_status text not null default 'visible' check (moderation_status in ('visible','hidden')),
  reported_reason text,
  created_at timestamptz not null default now(), updated_at timestamptz
);
create index if not exists partner_reviews_partner_idx on partner_reviews(partner_id, created_at desc);
alter table partner_reviews enable row level security;
drop policy if exists "partner reviews read" on partner_reviews;
create policy "partner reviews read" on partner_reviews for select using (customer_id=auth.uid() or partner_id=auth.uid() or is_admin());

-- Reviews change only through the review workflow; admins moderate.
drop policy if exists "reviews self update" on reviews;
drop policy if exists "reviews self insert" on reviews;
drop policy if exists "reviews admin update" on reviews;
create policy "reviews admin update" on reviews for update using (is_admin()) with check (is_admin());

create or replace function refresh_vendor_rating() returns trigger language plpgsql security definer set search_path=public as $$
declare vid uuid := coalesce(new.vendor_id, old.vendor_id);
begin
 update vendors set rating_avg=coalesce((select round(avg(rating)::numeric,2) from reviews where vendor_id=vid and moderation_status='visible'),0),
   rating_count=(select count(*) from reviews where vendor_id=vid and moderation_status='visible') where id=vid;
 return null;
end; $$;
drop trigger if exists refresh_vendor_rating on reviews;
create trigger refresh_vendor_rating after insert or update or delete on reviews for each row execute function refresh_vendor_rating();

create or replace function clean_review_text(p text) returns text language plpgsql immutable as $$
declare t text := nullif(trim(regexp_replace(coalesce(p,''),'\s+',' ','g')),'');
begin
 if t is null then return null; end if;
 if length(t)>500 then raise exception 'Reviews can be at most 500 characters'; end if;
 if t ~* '(https?://|www\.|\.com\b|\.in\b)' then raise exception 'Links are not allowed in reviews'; end if;
 if t ~ '(.)\1{9,}' then raise exception 'Please write a genuine review'; end if;
 return t;
end; $$;

create or replace function submit_order_review(p_order_id uuid, p_vendor_rating integer, p_vendor_comment text,
  p_partner_rating integer, p_partner_comment text) returns void
language plpgsql security definer set search_path=public as $$
declare o orders; partner uuid; prior record; vc text := clean_review_text(p_vendor_comment); pc text := clean_review_text(p_partner_comment);
begin
 select * into o from orders where id=p_order_id and customer_id=auth.uid() for update;
 if not found then raise exception 'Order not found'; end if;
 if o.status<>'delivered' then raise exception 'You can rate only delivered orders'; end if;
 if p_vendor_rating is null and p_partner_rating is null then raise exception 'Choose a rating'; end if;
 if (p_vendor_rating is not null and p_vendor_rating not between 1 and 5) or (p_partner_rating is not null and p_partner_rating not between 1 and 5)
 then raise exception 'Ratings must be 1 to 5 stars'; end if;
 if (select count(*) from reviews where customer_id=auth.uid() and created_at>now()-interval '1 day')>=20 then
   raise exception 'Too many reviews today. Try again tomorrow'; end if;
 if p_vendor_rating is not null then
   select id, created_at into prior from reviews where order_id=p_order_id;
   if found then
     if prior.created_at<now()-interval '7 days' then raise exception 'Reviews can be edited for 7 days'; end if;
     update reviews set rating=p_vendor_rating, comment=vc, updated_at=now() where id=prior.id;
   else
     insert into reviews(order_id,customer_id,vendor_id,rating,comment) values(p_order_id,auth.uid(),o.vendor_id,p_vendor_rating,vc);
     insert into notifications(user_id,type,title,body,order_id)
       select user_id,'review','New review',p_vendor_rating||'★ for order '||o.order_number,p_order_id
       from vendor_members where vendor_id=o.vendor_id and status='active';
   end if;
 end if;
 if p_partner_rating is not null then
   select partner_id into partner from delivery_assignments where order_id=p_order_id and status='accepted' limit 1;
   if partner is null then raise exception 'No delivery partner to rate for this order'; end if;
   select id, created_at into prior from partner_reviews where order_id=p_order_id;
   if found then
     if prior.created_at<now()-interval '7 days' then raise exception 'Reviews can be edited for 7 days'; end if;
     update partner_reviews set rating=p_partner_rating, comment=pc, updated_at=now() where id=prior.id;
   else
     insert into partner_reviews(order_id,customer_id,partner_id,rating,comment) values(p_order_id,auth.uid(),partner,p_partner_rating,pc);
   end if;
 end if;
end; $$;

create or replace function vendor_reply_review(p_review uuid, p_reply text) returns void
language plpgsql security definer set search_path=public as $$
declare r reviews; t text := clean_review_text(p_reply);
begin
 select * into r from reviews where id=p_review for update;
 if not found or not is_vendor_member(r.vendor_id) then raise exception 'Forbidden'; end if;
 if t is null then raise exception 'Write a reply'; end if;
 update reviews set vendor_reply=t, vendor_replied_at=now() where id=p_review;
end; $$;

create or replace function report_review(p_kind text, p_review uuid, p_reason text) returns void
language plpgsql security definer set search_path=public as $$
begin
 if length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Enter a reason (3–300 characters)'; end if;
 if p_kind='vendor' then
   update reviews set reported_reason=trim(p_reason) where id=p_review and (is_vendor_member(vendor_id) or customer_id=auth.uid());
 elsif p_kind='partner' then
   update partner_reviews set reported_reason=trim(p_reason) where id=p_review and partner_id=auth.uid();
 else raise exception 'Invalid review type'; end if;
 if not found then raise exception 'Review not found'; end if;
 perform notify_admins('review_report','Review reported',left(trim(p_reason),120),null);
end; $$;

create or replace function admin_moderate_review(p_kind text, p_review uuid, p_visible boolean) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 if p_kind='vendor' then update reviews set moderation_status=case when p_visible then 'visible' else 'hidden' end, reported_reason=null where id=p_review;
 elsif p_kind='partner' then update partner_reviews set moderation_status=case when p_visible then 'visible' else 'hidden' end, reported_reason=null where id=p_review;
 else raise exception 'Invalid review type'; end if;
 if not found then raise exception 'Review not found'; end if;
 insert into admin_audit_logs(actor_id,action,entity,entity_id) values(auth.uid(),case when p_visible then 'show_review' else 'hide_review' end,p_kind||'_review',p_review::text);
end; $$;

create or replace function my_order_reviews(p_order_id uuid) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'vendor',(select jsonb_build_object('rating',rating,'comment',comment,'created_at',created_at,'vendor_reply',vendor_reply) from reviews where order_id=p_order_id and customer_id=auth.uid()),
    'partner',(select jsonb_build_object('rating',rating,'comment',comment,'created_at',created_at) from partner_reviews where order_id=p_order_id and customer_id=auth.uid()),
    'has_partner',exists(select 1 from delivery_assignments where order_id=p_order_id and status='accepted'))
$$;

create or replace function store_reviews(p_vendor uuid, p_page integer default 0) returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'rating',r.rating,'comment',r.comment,'created_at',r.created_at,
    'vendor_reply',r.vendor_reply,'author',coalesce(left(nullif(p.display_name,''),1)||'.','Customer'),
    'moderation_status',r.moderation_status,'reported_reason',case when is_admin() or is_vendor_member(r.vendor_id) then r.reported_reason end)
    order by r.created_at desc),'[]'::jsonb)
  from (select * from reviews where vendor_id=p_vendor and (moderation_status='visible' or is_admin() or is_vendor_member(vendor_id))
        order by created_at desc offset greatest(p_page,0)*30 limit 30) r
  left join profiles p on p.id=r.customer_id
$$;
grant execute on function store_reviews(uuid,integer) to anon,authenticated;

-- =====================================================================
-- Promotional posters
-- =====================================================================

create table if not exists promo_posters (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(title) between 1 and 80),
  subtitle text check (subtitle is null or length(subtitle)<=160),
  image_path text not null,
  alt_text text check (alt_text is null or length(alt_text)<=160),
  cta_label text check (cta_label is null or length(cta_label)<=30),
  target_url text check (target_url is null or target_url ~ '^(https://[^\s]+|/store/[0-9a-f-]{36})$'),
  starts_at timestamptz, ends_at timestamptz,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  area_lat numeric(9,6), area_lng numeric(9,6), area_radius_km numeric(6,2),
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at>starts_at),
  check ((area_lat is null and area_lng is null and area_radius_km is null) or (area_lat is not null and area_lng is not null and area_radius_km>0))
);
alter table promo_posters enable row level security;
drop policy if exists "posters public read" on promo_posters;
drop policy if exists "posters admin write" on promo_posters;
create policy "posters public read" on promo_posters for select using (
  is_admin() or (is_active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())));
create policy "posters admin write" on promo_posters for all using (is_admin()) with check (is_admin());

create or replace function active_posters(p_lat numeric default null, p_lng numeric default null) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) - array['created_by','area_lat','area_lng','area_radius_km'] order by x.sort_order, x.created_at desc),'[]'::jsonb)
  from promo_posters x
  where x.is_active and (x.starts_at is null or x.starts_at<=now()) and (x.ends_at is null or x.ends_at>now())
    and (x.area_radius_km is null or (p_lat is not null and p_lng is not null and haversine_km(p_lat,p_lng,x.area_lat,x.area_lng)<=x.area_radius_km))
$$;
grant execute on function active_posters(numeric,numeric) to anon,authenticated;

-- =====================================================================
-- Dashboards and admin read models
-- =====================================================================

create or replace function my_partner_dashboard() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare d delivery_partner_profiles; p profiles; me uuid := auth.uid(); today timestamptz := local_day_start(); res jsonb;
begin
 select * into p from profiles where id=me;
 select * into d from delivery_partner_profiles where user_id=me;
 if not found then return jsonb_build_object('verification_status','none'); end if;
 select jsonb_build_object(
  'verification_status',d.verification_status,'review_reason',d.review_reason,'is_online',d.is_online,
  'qr_status',d.qr_status,'qr_review_reason',d.qr_review_reason,'has_qr',d.qr_image_path is not null,
  'legal_name',d.legal_name,'vehicle_type',d.vehicle_type,'vehicle_number',d.vehicle_number,
  'can_accept',(d.verification_status='approved' and d.approved_at is not null and p.status='active' and p.role='delivery'),
  'block_reason',case when p.status='suspended' or d.verification_status='suspended' then 'Your account is suspended. Contact support.'
     when d.verification_status='draft' then 'Complete and submit your application.'
     when d.verification_status='pending_verification' then 'Your documents are being verified.'
     when d.verification_status='action_required' then 'Corrections are required: '||coalesce(d.review_reason,'see notifications')
     when d.verification_status='rejected' then 'Your application was rejected: '||coalesce(d.review_reason,'')
     else null end,
  'deliveries_today',(select count(*) from delivery_earnings where partner_id=me and created_at>=today),
  'deliveries_week',(select count(*) from delivery_earnings where partner_id=me and created_at>=today-interval '6 days'),
  'deliveries_month',(select count(*) from delivery_earnings where partner_id=me and created_at>=date_trunc('month',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
  'deliveries_total',(select count(*) from delivery_earnings where partner_id=me),
  'active_orders',(select count(*) from delivery_assignments a join orders o on o.id=a.order_id where a.partner_id=me and a.status='accepted' and o.status in ('assigned','picked_up','out_for_delivery')),
  'accepted_total',(select count(*) from delivery_assignments where partner_id=me and status in ('accepted','cancelled')),
  'cancelled_or_failed',(select count(*) from delivery_assignments a join orders o on o.id=a.order_id where a.partner_id=me and (a.status='cancelled' or o.status in ('cancelled','refunded'))),
  'earned_today_paise',(select coalesce(sum(net_paise),0) from delivery_earnings where partner_id=me and created_at>=today),
  'earned_total_paise',(select coalesce(sum(net_paise),0) from delivery_earnings where partner_id=me),
  'paid_paise',(select coalesce(sum(amount_paise),0) from partner_payouts where partner_id=me and status='paid'),
  'in_payout_paise',(select coalesce(sum(amount_paise),0) from partner_payouts where partner_id=me and status in ('pending','processing')),
  'pending_payout_paise',(select coalesce(sum(net_paise),0) from delivery_earnings where partner_id=me and not settled),
  'rating_avg',(select round(avg(rating)::numeric,2) from partner_reviews where partner_id=me and moderation_status='visible'),
  'rating_count',(select count(*) from partner_reviews where partner_id=me and moderation_status='visible')
 ) into res;
 return res;
end; $$;

create or replace function my_partner_application() returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('profile',to_jsonb(d)-array['approved_by','reviewed_by'],
    'documents',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'doc_type',x.doc_type,'masked_reference',x.masked_reference,
       'status',x.status,'review_reason',x.review_reason,'created_at',x.created_at) order by x.created_at desc)
       from partner_documents x where x.partner_id=auth.uid()),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(jsonb_build_object('event',e.event,'to_status',e.to_status,'reason',e.reason,'created_at',e.created_at)
       order by e.created_at desc) from (select * from partner_verification_events where partner_id=auth.uid() order by created_at desc limit 30) e),'[]'::jsonb),
    'account',(select jsonb_build_object('display_name',display_name,'phone',phone,'role',role) from profiles where id=auth.uid()))
  from (select 1) one left join delivery_partner_profiles d on d.user_id=auth.uid()
$$;

create or replace function admin_dashboard(p_from timestamptz, p_to timestamptz) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare res jsonb; commission numeric := app_setting_number('platform_commission_percent',0);
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 if p_from is null or p_to is null or p_to<=p_from then raise exception 'Invalid date range'; end if;
 with o as (select * from orders where created_at>=p_from and created_at<p_to),
      dl as (select * from orders where status='delivered' and delivered_at>=p_from and delivered_at<p_to)
 select jsonb_build_object(
  'restaurants_total',(select count(*) from vendors where archived_at is null),
  'restaurants_active',(select count(*) from vendors where archived_at is null and is_active),
  'restaurants_open_now',(select count(*) from vendors where archived_at is null and vendor_is_open(opening_hours,is_active,temporarily_closed)),
  'restaurant_applications_pending',(select count(*) from vendor_applications where status='pending'),
  'partners_total',(select count(*) from delivery_partner_profiles),
  'partners_pending_verification',(select count(*) from delivery_partner_profiles where verification_status='pending_verification'),
  'partners_online',(select count(*) from delivery_partner_profiles where is_online and verification_status='approved'),
  'partner_qr_pending',(select count(*) from delivery_partner_profiles where qr_status='pending'),
  'customers_total',(select count(*) from profiles where role='customer'),
  'orders',(select count(*) from o),
  'orders_active_now',(select count(*) from orders where status in ('vendor_confirmation','preparing','ready_for_pickup','assigned','picked_up','out_for_delivery')),
  'orders_awaiting_payment',(select count(*) from o where status in ('pending_payment','payment_review')),
  'orders_completed',(select count(*) from dl),
  'orders_cancelled',(select count(*) from o where status in ('cancelled','rejected','refunded')),
  'gross_order_value_paise',(select coalesce(sum(total_payable_paise),0) from o where payment_status='verified'),
  'restaurant_sales_paise',(select coalesce(sum(items_subtotal_paise),0) from dl),
  'delivery_fees_paise',(select coalesce(sum(delivery_fee_paise),0) from dl),
  'platform_commission_paise',(select coalesce(round(sum(items_subtotal_paise)*commission/100),0) from dl),
  'partner_earnings_paise',(select coalesce(sum(net_paise),0) from delivery_earnings where created_at>=p_from and created_at<p_to),
  'payouts_pending_paise',(select coalesce(sum(net_paise),0) from delivery_earnings where not settled),
  'payouts_completed_paise',(select coalesce(sum(amount_paise),0) from partner_payouts where status='paid' and paid_at>=p_from and paid_at<p_to),
  'payments_pending_verification',(select count(*) from payments where status='submitted'),
  'restaurant_rating_avg',(select round(avg(rating)::numeric,2) from reviews where moderation_status='visible'),
  'partner_rating_avg',(select round(avg(rating)::numeric,2) from partner_reviews where moderation_status='visible'),
  'reviews_reported',(select count(*) from reviews where reported_reason is not null)+(select count(*) from partner_reviews where reported_reason is not null)
 ) into res;
 return res;
end; $$;

create or replace function admin_partners(p_search text default '', p_status text default null) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare today timestamptz := local_day_start(); res jsonb;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 select coalesce(jsonb_agg(t.r order by (t.r->>'registered_at') desc),'[]'::jsonb) into res from (
  select jsonb_build_object('user_id',d.user_id,'name',coalesce(d.legal_name,p.display_name,'Partner'),'phone',coalesce(d.phone,p.phone),
   'photo_path',d.profile_photo_path,'verification_status',d.verification_status,'account_status',p.status,'city',d.city,
   'vehicle_type',d.vehicle_type,'vehicle_number',d.vehicle_number,'is_online',d.is_online,'qr_status',d.qr_status,
   'today_deliveries',(select count(*) from delivery_earnings e where e.partner_id=d.user_id and e.created_at>=today),
   'total_deliveries',(select count(*) from delivery_earnings e where e.partner_id=d.user_id),
   'today_earnings_paise',(select coalesce(sum(net_paise),0) from delivery_earnings e where e.partner_id=d.user_id and e.created_at>=today),
   'total_earnings_paise',(select coalesce(sum(net_paise),0) from delivery_earnings e where e.partner_id=d.user_id),
   'paid_paise',(select coalesce(sum(amount_paise),0) from partner_payouts x where x.partner_id=d.user_id and x.status='paid'),
   'pending_paise',(select coalesce(sum(net_paise),0) from delivery_earnings e where e.partner_id=d.user_id and not e.settled),
   'active_order',(select o.order_number from delivery_assignments a join orders o on o.id=a.order_id
       where a.partner_id=d.user_id and a.status='accepted' and o.status in ('assigned','picked_up','out_for_delivery') limit 1),
   'registered_at',d.created_at) as r
  from delivery_partner_profiles d join profiles p on p.id=d.user_id
  where (p_status is null or d.verification_status=p_status)
    and (coalesce(p_search,'')='' or coalesce(d.legal_name,p.display_name,'') ilike '%'||p_search||'%'
         or coalesce(d.phone,p.phone,'') like '%'||regexp_replace(p_search,'\D','','g')||'%' and regexp_replace(p_search,'\D','','g')<>''
         or coalesce(d.vehicle_number,'') ilike '%'||regexp_replace(p_search,'\s|-','','g')||'%'
         or coalesce(d.city,'') ilike '%'||p_search||'%')
 ) t;
 return res;
end; $$;

create or replace function admin_partner_detail(p_partner uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare res jsonb;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 select jsonb_build_object(
  'profile',to_jsonb(d),'account',jsonb_build_object('display_name',p.display_name,'phone',p.phone,'status',p.status,'role',p.role,'created_at',p.created_at),
  'documents',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from partner_documents x where x.partner_id=p_partner),'[]'::jsonb),
  'events',coalesce((select jsonb_agg(jsonb_build_object('event',e.event,'from_status',e.from_status,'to_status',e.to_status,'reason',e.reason,
       'created_at',e.created_at,'actor',a.display_name) order by e.created_at desc)
       from partner_verification_events e left join profiles a on a.id=e.actor_id where e.partner_id=p_partner),'[]'::jsonb),
  'payouts',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from partner_payouts x where x.partner_id=p_partner),'[]'::jsonb),
  'reviews',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'rating',r.rating,'comment',r.comment,'created_at',r.created_at,
       'moderation_status',r.moderation_status,'reported_reason',r.reported_reason,'order_id',r.order_id) order by r.created_at desc)
       from partner_reviews r where r.partner_id=p_partner),'[]'::jsonb),
  'notifications',coalesce((select jsonb_agg(jsonb_build_object('title',n.title,'body',n.body,'created_at',n.created_at,'read_at',n.read_at) order by n.created_at desc)
       from (select * from notifications where user_id=p_partner order by created_at desc limit 30) n),'[]'::jsonb),
  'audit',coalesce((select jsonb_agg(jsonb_build_object('action',l.action,'reason',l.reason,'created_at',l.created_at,'actor',a.display_name) order by l.created_at desc)
       from admin_audit_logs l left join profiles a on a.id=l.actor_id where l.entity_id=p_partner::text),'[]'::jsonb),
  'unsettled_paise',(select coalesce(sum(net_paise),0) from delivery_earnings where partner_id=p_partner and not settled and payout_id is null),
  'location',(select jsonb_build_object('latitude',latitude,'longitude',longitude,'updated_at',updated_at,'order_id',order_id) from partner_locations where partner_id=p_partner)
 ) into res
 from delivery_partner_profiles d join profiles p on p.id=d.user_id where d.user_id=p_partner;
 if res is null then raise exception 'Partner not found'; end if;
 return res;
end; $$;

create or replace function admin_partner_orders(p_partner uuid, p_from timestamptz, p_to timestamptz) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare res jsonb;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'order_id',o.id,'order_number',o.order_number,'created_at',o.created_at,'status',o.status,'payment_method',o.payment_method,
   'payment_status',o.payment_status,'total_paise',o.total_payable_paise,'delivery_fee_paise',o.delivery_fee_paise,
   'partner_earning_paise',e.net_paise,'settled',e.settled,'delivered_at',o.delivered_at,'accepted_at',a.responded_at,
   'restaurant',v.name,'restaurant_address',v.dispatch_address,'destination',o.destination_address,
   'customer',coalesce(c.display_name,'Customer'),'customer_phone',mask_phone(c.phone),
   'items',(select string_agg(i.quantity||' × '||i.product_name,', ') from order_items i where i.order_id=o.id)
 ) order by o.created_at desc),'[]'::jsonb) into res
 from delivery_assignments a join orders o on o.id=a.order_id join vendors v on v.id=o.vendor_id
 left join profiles c on c.id=o.customer_id left join delivery_earnings e on e.order_id=o.id
 where a.partner_id=p_partner and a.status in ('accepted','cancelled') and a.responded_at>=p_from and a.responded_at<p_to;
 return res;
end; $$;

create or replace function admin_customers(p_search text default '', p_page integer default 0) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare res jsonb;
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 select coalesce(jsonb_agg(t.r),'[]'::jsonb) into res from (
  select jsonb_build_object('id',p.id,'name',coalesce(p.display_name,'Customer'),'phone',mask_phone(p.phone),'status',p.status,
   'created_at',p.created_at,'orders',(select count(*) from orders o where o.customer_id=p.id),
   'delivered',(select count(*) from orders o where o.customer_id=p.id and o.status='delivered'),
   'spent_paise',(select coalesce(sum(total_payable_paise),0) from orders o where o.customer_id=p.id and o.payment_status='verified'),
   'reviews',(select count(*) from reviews r where r.customer_id=p.id),
   'last_order_at',(select max(created_at) from orders o where o.customer_id=p.id)) as r
  from profiles p where p.role='customer'
   and (coalesce(p_search,'')='' or coalesce(p.display_name,'') ilike '%'||p_search||'%'
        or (regexp_replace(p_search,'\D','','g')<>'' and coalesce(p.phone,'') like '%'||regexp_replace(p_search,'\D','','g')||'%'))
  order by p.created_at desc offset greatest(p_page,0)*30 limit 30) t;
 return res;
end; $$;

create or replace function admin_set_customer_status(p_customer uuid, p_status account_status, p_reason text) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not is_admin() then raise exception 'Forbidden'; end if;
 if p_status not in ('active','suspended') then raise exception 'Invalid status'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'A reason is required'; end if;
 update profiles set status=p_status where id=p_customer and role='customer';
 if not found then raise exception 'Customer not found'; end if;
 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(auth.uid(),'customer_'||p_status,'profiles',p_customer::text,p_reason);
end; $$;

create or replace function vendor_dashboard(p_vendor uuid, p_from timestamptz, p_to timestamptz) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v vendors; res jsonb; commission numeric := app_setting_number('platform_commission_percent',0);
begin
 if not (is_admin() or is_vendor_member(p_vendor)) then raise exception 'Forbidden'; end if;
 select * into v from vendors where id=p_vendor;
 if not found then raise exception 'Restaurant not found'; end if;
 with o as (select * from orders where vendor_id=p_vendor and created_at>=p_from and created_at<p_to)
 select jsonb_build_object(
  'vendor',to_jsonb(v),'is_open',vendor_is_open(v.opening_hours,v.is_active,v.temporarily_closed),
  'orders',(select count(*) from o),
  'awaiting_payment',(select count(*) from o where status in ('pending_payment','payment_review')),
  'new_orders',(select count(*) from o where status='vendor_confirmation'),
  'preparing',(select count(*) from o where status='preparing'),
  'ready_for_pickup',(select count(*) from o where status='ready_for_pickup'),
  'in_delivery',(select count(*) from o where status in ('assigned','picked_up','out_for_delivery')),
  'completed',(select count(*) from o where status='delivered'),
  'cancelled',(select count(*) from o where status in ('cancelled','rejected','refunded')),
  'sales_paise',(select coalesce(sum(items_subtotal_paise),0) from o where status='delivered'),
  'commission_paise',(select coalesce(round(sum(items_subtotal_paise)*commission/100),0) from o where status='delivered'),
  'average_order_paise',(select coalesce(round(avg(items_subtotal_paise)),0) from o where status='delivered'),
  'popular_items',coalesce((select jsonb_agg(jsonb_build_object('name',name,'quantity',qty,'sales_paise',sales) order by qty desc)
     from (select i.product_name as name, sum(i.quantity) as qty, sum(i.line_total_paise) as sales from order_items i join o on o.id=i.order_id
           where o.status='delivered' group by i.product_name order by sum(i.quantity) desc limit 5) t),'[]'::jsonb),
  'rating_avg',v.rating_avg,'rating_count',v.rating_count,
  'active_deliveries',coalesce((select jsonb_agg(jsonb_build_object('order_id',x.id,'order_number',x.order_number,'status',x.status,
       'partner',coalesce(dp.legal_name,pp.display_name,'Partner'),'partner_phone',coalesce(dp.phone,pp.phone),'vehicle',dp.vehicle_number))
     from orders x join delivery_assignments a on a.order_id=x.id and a.status='accepted'
     left join delivery_partner_profiles dp on dp.user_id=a.partner_id left join profiles pp on pp.id=a.partner_id
     where x.vendor_id=p_vendor and x.status in ('assigned','picked_up','out_for_delivery')),'[]'::jsonb)
 ) into res;
 return res;
end; $$;

create or replace function order_breakdown(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare o orders; e delivery_earnings; po partner_payouts; commission numeric := app_setting_number('platform_commission_percent',0); is_partner boolean;
begin
 select * into o from orders where id=p_order;
 if not found then raise exception 'Order not found'; end if;
 is_partner := exists(select 1 from delivery_assignments where order_id=p_order and partner_id=auth.uid() and status='accepted');
 if not (is_admin() or is_vendor_member(o.vendor_id) or is_partner) then raise exception 'Forbidden'; end if;
 select * into e from delivery_earnings where order_id=p_order;
 if e.payout_id is not null then select * into po from partner_payouts where id=e.payout_id; end if;
 return jsonb_build_object(
  'items_subtotal_paise',o.items_subtotal_paise,'tax_paise',o.tax_paise,'discount_paise',o.discount_paise,
  'delivery_fee_paise',o.delivery_fee_paise,'total_paise',o.total_payable_paise,
  'commission_percent',commission,'platform_commission_paise',round(o.items_subtotal_paise*commission/100),
  'restaurant_payable_paise',o.items_subtotal_paise-round(o.items_subtotal_paise*commission/100),
  'partner_earning_paise',coalesce(e.net_paise, case when o.status<>'delivered' then partner_earning_for_fee(o.delivery_fee_paise) end),
  'partner_earning_final',e.id is not null,'adjustments_paise',coalesce(e.adjustments_paise,0),
  'partner_paid_paise',case when po.status='paid' then e.net_paise else 0 end,
  'partner_remaining_paise',case when e.id is null then null when po.status='paid' then 0 else e.net_paise end,
  'payout_status',po.status,'payout_reference',case when is_admin() or is_partner then po.reference end);
end; $$;

-- =====================================================================
-- Support tickets: notify the other side of the conversation
-- =====================================================================

do $$ begin
 if not exists(select 1 from pg_constraint where conname='support_tickets_status_check') then
   alter table support_tickets add constraint support_tickets_status_check check (status in ('open','in_progress','resolved','closed')) not valid;
 end if;
 if not exists(select 1 from pg_constraint where conname='support_text_length') then
   alter table support_tickets add constraint support_text_length check (length(description) between 5 and 2000 and length(category) between 2 and 40) not valid;
 end if;
 if not exists(select 1 from pg_constraint where conname='support_message_length') then
   alter table support_messages add constraint support_message_length check (length(message) between 1 and 2000) not valid;
 end if;
end $$;

create or replace function guard_support_ticket() returns trigger language plpgsql set search_path=public as $$
begin
 if is_trusted_context() or is_admin() then return new; end if;
 if TG_OP='INSERT' then
   if new.status<>'open' or new.assigned_admin is not null then raise exception 'New tickets start open'; end if;
 elsif (new.customer_id,new.order_id,new.category,new.description,new.assigned_admin) is distinct from
       (old.customer_id,old.order_id,old.category,old.description,old.assigned_admin)
    or (new.status is distinct from old.status and new.status<>'closed') then
   raise exception 'Only support staff can change this ticket';
 end if;
 return new;
end; $$;
drop trigger if exists guard_support_ticket on support_tickets;
create trigger guard_support_ticket before insert or update on support_tickets for each row execute function guard_support_ticket();

create or replace function on_support_activity() returns trigger language plpgsql security definer set search_path=public as $$
declare t support_tickets;
begin
 if TG_TABLE_NAME='support_tickets' then
   perform notify_admins('support','New support request',new.category||': '||left(new.description,100),new.order_id);
   return new;
 end if;
 select * into t from support_tickets where id=new.ticket_id;
 if new.sender_id=t.customer_id then
   perform notify_admins('support','Support reply from user',left(new.message,100),t.order_id);
 else
   insert into notifications(user_id,type,title,body,order_id) values(t.customer_id,'support','Support replied',left(new.message,140),t.order_id);
 end if;
 return new;
end; $$;
drop trigger if exists on_support_ticket on support_tickets;
create trigger on_support_ticket after insert on support_tickets for each row execute function on_support_activity();
drop trigger if exists on_support_message on support_messages;
create trigger on_support_message after insert on support_messages for each row execute function on_support_activity();

-- =====================================================================
-- Storage and realtime
-- =====================================================================

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('promo-posters','promo-posters',true,5242880,array['image/jpeg','image/png','image/webp']),
 ('vendor-images','vendor-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
drop policy if exists "poster image read" on storage.objects;
drop policy if exists "poster image write" on storage.objects;
drop policy if exists "poster image delete" on storage.objects;
drop policy if exists "vendor image read" on storage.objects;
drop policy if exists "vendor image write" on storage.objects;
create policy "poster image read" on storage.objects for select using(bucket_id='promo-posters');
create policy "poster image write" on storage.objects for insert to authenticated with check(bucket_id='promo-posters' and is_admin());
create policy "poster image delete" on storage.objects for delete to authenticated using(bucket_id='promo-posters' and is_admin());
create policy "vendor image read" on storage.objects for select using(bucket_id='vendor-images');
create policy "vendor image write" on storage.objects for insert to authenticated with check(
 bucket_id='vendor-images' and (is_admin() or exists(select 1 from vendors v where v.id::text=(storage.foldername(name))[1] and is_vendor_member(v.id))));

do $$ declare t text; begin
 foreach t in array array['promo_posters','vendors','delivery_partner_profiles','partner_payouts','payments','delivery_earnings','reviews'] loop
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
 select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t)
 then execute format('alter publication supabase_realtime add table public.%I',t); end if;
 end loop;
end $$;

-- Server-only helpers are not part of the client API.
revoke all on function partner_event(uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function partner_earning_for_fee(integer) from public,anon,authenticated;

commit;
