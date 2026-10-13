-- Portion choices (e.g. Half plate / Full plate): single-choice, required option groups.
-- The same item may appear on separate cart lines with different options.
-- Additive: existing options default to 'multi' and keep their current behaviour.
begin;

alter table product_options add column if not exists selection text not null default 'multi';
do $$ begin
 if not exists(select 1 from pg_constraint where conname='product_options_selection_check') then
   alter table product_options add constraint product_options_selection_check check (selection in ('multi','single_required'));
 end if;
end $$;

create or replace function resolve_checkout(p_vendor_id uuid,p_items jsonb,p_distance numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v vendors; p products; i jsonb; opt product_options; opts jsonb; lines jsonb:='[]';
 qty integer; unit integer; subtotal integer:=0; fee integer; tax integer; pct numeric; ids uuid[]; g record;
begin
 select * into v from vendors where id=p_vendor_id and is_active and archived_at is null;
 if not found then raise exception 'Store is unavailable'; end if;
 if not vendor_is_open(v.opening_hours,v.is_active,v.temporarily_closed) then raise exception 'Store is closed right now'; end if;
 if not coalesce((select upi_enabled from payment_settings where id),false) then raise exception 'Online payment is temporarily unavailable'; end if;
 if p_distance is null or p_distance<0 or p_distance>v.service_radius_km then raise exception 'Outside delivery area'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Invalid cart'; end if;
 -- A line is one product with one exact option set; the same product may repeat with other options.
 if (select count(*)<>count(distinct (x->>'product_id')||'|'||coalesce((
       select string_agg(o->>'option_id',',' order by o->>'option_id') from jsonb_array_elements(coalesce(x->'options','[]')) o),''))
     from jsonb_array_elements(p_items) x) then raise exception 'Duplicate product lines'; end if;
 perform id from products where id in(select (x->>'product_id')::uuid from jsonb_array_elements(p_items) x) order by id for update;
 for i in select * from jsonb_array_elements(p_items) loop
   select * into p from products where id=(i->>'product_id')::uuid and vendor_id=p_vendor_id and is_available;
   if not found then raise exception 'Product is unavailable'; end if;
   qty:=(i->>'quantity')::integer;
   if qty is null or qty not between 1 and 99 then raise exception 'Invalid quantity or insufficient stock'; end if;
   unit:=coalesce(p.sale_price_paise,p.price_paise); opts:='[]';
   if jsonb_typeof(coalesce(i->'options','[]'))<>'array' then raise exception 'Invalid options'; end if;
   ids:=array(select (x->>'option_id')::uuid from jsonb_array_elements(coalesce(i->'options','[]')) x);
   if cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception 'Duplicate options'; end if;
   if exists(select 1 from unnest(ids) x where x is null) then raise exception 'Option ID required'; end if;
   for opt in select * from product_options where id=any(ids) and product_id=p.id and is_available order by group_name, sort_priority loop
     unit:=unit+opt.price_delta_paise;
     opts:=opts||jsonb_build_array(jsonb_build_object('option_id',opt.id,'group',opt.group_name,'label',opt.label,'price_delta_paise',opt.price_delta_paise));
   end loop;
   if jsonb_array_length(opts)<>cardinality(ids) or unit<0 then raise exception 'Option unavailable'; end if;
   for g in select group_name from product_options where product_id=p.id and is_available and selection='single_required' group by group_name loop
     if (select count(*) from product_options where id=any(ids) and product_id=p.id and group_name=g.group_name)<>1 then
       raise exception 'Choose one % for %', lower(g.group_name), p.name;
     end if;
   end loop;
   subtotal:=subtotal+unit*qty;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',p.id,'product_name',p.name,'quantity',qty,'unit_price_paise',unit,'options',opts,'line_total_paise',unit*qty));
 end loop;
 -- Stock is per product across all of its lines.
 if exists(select 1 from (select (x->>'product_id')::uuid pid, sum((x->>'quantity')::integer) q from jsonb_array_elements(p_items) x group by 1) t
           join products pr on pr.id=t.pid where pr.stock is not null and pr.stock<t.q) then
   raise exception 'Invalid quantity or insufficient stock'; end if;
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

-- Restaurant card previews show the lowest required-portion price as "from".
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
    'preview',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,
        'price_paise',coalesce(p.sale_price_paise,p.price_paise)+coalesce((
          select sum(m.least_delta) from (select min(o.price_delta_paise) least_delta from product_options o
            where o.product_id=p.id and o.is_available and o.selection='single_required' group by o.group_name) m),0),
        'has_choices',exists(select 1 from product_options o where o.product_id=p.id and o.is_available and o.selection='single_required'),
        'image_path',p.image_path,'diet',p.diet,'available',(p.stock is null or p.stock>0)) order by p.sort_priority,p.name)
      from (select * from products where vendor_id=r.id and is_available order by sort_priority,name limit 4) p),'[]'::jsonb)
  ) order by r.is_open desc, r.sort_priority, r.distance_km nulls last, r.name),'[]'::jsonb) from ranked r
$$;
grant execute on function discover_stores(numeric,numeric,text,text,integer) to anon,authenticated;

-- Restaurants (and admins) set an item's Half/Full prices in one atomic step.
create or replace function set_item_portions(p_product uuid, p_enabled boolean, p_half_paise integer default null, p_full_paise integer default null)
returns void language plpgsql security definer set search_path=public as $$
declare p products;
begin
 select * into p from products where id=p_product for update;
 if not found or not (is_admin() or is_vendor_member(p.vendor_id)) then raise exception 'Forbidden'; end if;
 delete from product_options where product_id=p_product and group_name='Portion';
 if not p_enabled then
   if p_full_paise is not null then
     if p_full_paise<=0 then raise exception 'Enter a valid price'; end if;
     update products set price_paise=p_full_paise, sale_price_paise=null, updated_at=now() where id=p_product;
   end if;
   return;
 end if;
 if p_half_paise is null or p_full_paise is null or p_half_paise<=0 or p_full_paise<=0 then raise exception 'Enter both half and full plate prices'; end if;
 if p_half_paise>=p_full_paise then raise exception 'Half plate price must be lower than full plate price'; end if;
 -- The item price becomes the half-plate price; Full plate adds the difference.
 update products set price_paise=p_half_paise, sale_price_paise=null, updated_at=now() where id=p_product;
 insert into product_options(product_id,group_name,label,price_delta_paise,is_available,sort_priority,selection) values
   (p_product,'Portion','Half plate',0,true,1,'single_required'),
   (p_product,'Portion','Full plate',p_full_paise-p_half_paise,true,2,'single_required');
end; $$;
revoke all on function set_item_portions(uuid,boolean,integer,integer) from public,anon;
grant execute on function set_item_portions(uuid,boolean,integer,integer) to authenticated;

commit;
