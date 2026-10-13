import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

// Runs real PostgreSQL SQL/RLS locally. Auth/Storage schemas emulate Supabase;
// pg_net delivery and a deployed Supabase gateway are deliberately not simulated.
const db = new PGlite();
await db.exec(`
create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create schema storage;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select nullif(current_setting('request.jwt.claim.role',true),'') $$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
alter table storage.objects enable row level security;
create function storage.foldername(text) returns text[] language sql immutable as $$ select string_to_array($1,'/') $$;
grant usage on schema public,auth,storage to anon,authenticated,service_role;
grant execute on all functions in schema auth,storage to anon,authenticated,service_role;
alter default privileges in schema public grant select,insert,update,delete on tables to anon,authenticated,service_role;
`);
for (const name of ['0001_init','0002_functions','0003_rls','0004_admin','0005_vendor_notifications','0006_delivery','0008_fcm_tokens','0009_fix_rls_recursion','0010_mobile_security']) {
 let sql=await readFile(new URL(`../../supabase/migrations/${name}.sql`,import.meta.url),'utf8');
 sql=sql.replace('create extension if not exists "pgcrypto";','');
 await db.exec(sql);
}
let count=0;
async function check(name,work){await work();console.log(`PASS ${++count}: ${name}`);}
const uid=(n)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const customer=uid(1), other=uid(2), admin=uid(3), vendorUser=uid(4), partner=uid(5), store=uid(10), product=uid(11), option=uid(12);
async function as(role,id=''){await db.exec(`reset role; select set_config('request.jwt.claim.sub','${id}',false),set_config('request.jwt.claim.role','${role}',false); set role ${role};`);}
async function root(){await db.exec("reset role; select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim.role','service_role',false);");}
async function scalar(sql,params=[]){return Object.values((await db.query(sql,params)).rows[0])[0];}
async function denied(sql,params=[]){await assert.rejects(()=>db.query(sql,params));}
await root();
for(const id of [customer,other,admin,vendorUser,partner])await db.query('insert into auth.users(id,email) values($1,$2)',[id,`${id}@test.invalid`]);
await db.query("update profiles set role='admin' where id=$1",[admin]);
await db.query("update profiles set role='vendor' where id=$1",[vendorUser]);
await db.query("update profiles set role='delivery' where id=$1",[partner]);
await db.query("insert into vendors(id,name,dispatch_address,latitude,longitude,service_radius_km) values($1,'Test kitchen','Test address',28.89,76.60,9)",[store]);
await db.query('insert into vendor_members(user_id,vendor_id) values($1,$2)',[vendorUser,store]);
await db.query("insert into products(id,vendor_id,name,price_paise,stock) values($1,$2,'Test item',10000,10)",[product,store]);
await db.query("insert into product_options(id,product_id,group_name,label,price_delta_paise) values($1,$2,'Add-ons','Cheese',500)",[option,product]);
await db.query('insert into delivery_partner_profiles(user_id,approved_at,is_online) values($1,now(),true)',[partner]);
const items=[{product_id:product,quantity:2,options:[{option_id:option,price_delta_paise:-999999}]}];
const args=[customer,uid(20),store,'Test house, Rohtak',28.89,76.61,1,JSON.stringify(items),null,22500];
const place='select mobile_place_order($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10)';
await check('mobile checkout disabled until coordinated deployment is complete',async()=>{assert.equal((await scalar('select mobile_checkout_capabilities()')).version,0);});
await check('customer cannot promote or reactivate their profile',async()=>{await as('authenticated',customer);await denied("update profiles set role='admin' where id=$1",[customer]);await denied("update profiles set status='suspended' where id=$1",[customer]);});
await check('self profile display name edit works',async()=>{await db.query("update profiles set display_name='Customer' where id=$1",[customer]);assert.equal(await scalar('select display_name from profiles where id=$1',[customer]),'Customer');});
await check('client cannot use trusted distance RPC or price resolver',async()=>{await denied('select resolve_checkout($1,$2::jsonb,1)',[store,JSON.stringify(items)]);await denied("select create_order($1,'Test address',28,76,0,'google',$2::jsonb,null)",[store,JSON.stringify(items)]);await denied(place,args);});
await check('direct order insertion is rejected',async()=>{await denied("insert into orders(customer_id,vendor_id,category,destination_address,destination_lat,destination_lng,total_payable_paise) values($1,$2,'food','test',28,76,1)",[customer,store]);});
await check('admin metrics denied to customer',async()=>{await denied('select mobile_admin_metrics()');});
let order;
await check('server ignores client option prices and decrements stock',async()=>{await as('service_role');order=await scalar(place,args);assert.equal(await scalar('select total_payable_paise from orders where id=$1',[order]),22500);assert.equal(await scalar('select stock from products where id=$1',[product]),8);});
await check('retry returns same order and never decrements stock twice',async()=>{assert.equal(await scalar(place,args),order);assert.equal(await scalar('select stock from products where id=$1',[product]),8);});
await check('reusing request ID for a different address is rejected',async()=>{const changed=[...args];changed[3]='Different address';await denied(place,changed);});
await check('insufficient stock rejects transaction without partial order',async()=>{const changed=[...args];changed[1]=uid(21);changed[7]=JSON.stringify([{product_id:product,quantity:99}]);await denied(place,changed);assert.equal(await scalar('select count(*)::int from orders'),1);});
await check('another customer cannot read or pay this order',async()=>{await as('authenticated',other);assert.equal(await scalar('select count(*)::int from orders where id=$1',[order]),0);await denied("select submit_payment_proof($1,'123456789012',null)",[order]);});
await check('customer reads their items and rejects invalid UTR',async()=>{await as('authenticated',customer);assert.equal(await scalar('select count(*)::int from order_items where order_id=$1',[order]),1);await denied("select submit_payment_proof($1,'invalid',null)",[order]);});
let payment;
await check('UTR submission stays under review and duplicate blocked',async()=>{payment=await scalar("select submit_payment_proof($1,'123456789012',null)",[order]);assert.equal(await scalar('select payment_status from orders where id=$1',[order]),'submitted');await denied("select submit_payment_proof($1,'123456789012',null)",[order]);await denied('select verify_payment($1,true,null)',[payment]);});
await check('admin verification succeeds exactly once',async()=>{await as('authenticated',admin);await db.query('select verify_payment($1,true,null)',[payment]);await denied('select verify_payment($1,true,null)',[payment]);});
await check('vendor cannot skip preparation',async()=>{await as('authenticated',vendorUser);await denied("select vendor_set_order_status($1,'ready_for_pickup',null)",[order]);await db.query("select vendor_set_order_status($1,'preparing',null)",[order]);await db.query("select vendor_set_order_status($1,'ready_for_pickup',null)",[order]);});
await check('vendor edits availability but cannot alter ranking',async()=>{await db.query('update vendors set is_active=false where id=$1',[store]);await denied('update vendors set sort_priority=1 where id=$1',[store]);await db.query('update vendors set is_active=true where id=$1',[store]);});
await check('unrelated customer cannot edit vendor products',async()=>{await as('authenticated',other);assert.equal((await db.query("update products set price_paise=1 where id=$1 returning id",[product])).rows.length,0);});
await check('partner cannot self approve',async()=>{await as('authenticated',partner);await denied('update delivery_partner_profiles set approved_at=null where user_id=$1',[partner]);});
await check('partner accepts and cannot skip pickup',async()=>{await db.query('select accept_delivery($1)',[order]);await denied("select partner_set_order_status($1,'delivered')",[order]);});
await check('delivery completes with one earnings record',async()=>{for(const status of ['picked_up','out_for_delivery','delivered'])await db.query('select partner_set_order_status($1,$2::order_status)',[order,status]);assert.equal(await scalar('select net_paise from delivery_earnings where order_id=$1',[order]),1500);});
await check('document cannot be preapproved or point to someone else',async()=>{await denied("insert into partner_documents(partner_id,doc_type,file_path,status) values($1,'id_proof',$2,'active')",[partner,`${partner}/id.jpg`]);await denied("insert into partner_documents(partner_id,doc_type,file_path) values($1,'id_proof',$2)",[partner,`${other}/id.jpg`]);});
await check('fee boundary schedule preserved',async()=>{await as('authenticated',customer);for(const [km,fee] of [[0,1500],[1,1500],[1.5,2000],[3,3300],[9,9000],[9.1,9500],[11,10000]])assert.equal(await scalar('select calc_delivery_fee_paise($1)',[km]),fee);});
await check('rate replacement with gaps rejected atomically',async()=>{await as('authenticated',admin);await denied('select admin_replace_rate_table($1::jsonb)',[JSON.stringify([{min_km:0,max_km:1,fee_paise:1500},{min_km:2,max_km:9,fee_paise:9000}])]);assert.equal(await scalar('select count(*)::int from delivery_rate_rules'),17);});
console.log(`${count} PostgreSQL checks passed. No remote database was accessed.`);
await db.close();
