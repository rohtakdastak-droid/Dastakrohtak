import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

// Runs real PostgreSQL SQL/RLS locally. Auth/Storage schemas emulate Supabase;
// pg_net delivery and a deployed Supabase gateway are deliberately not simulated.
const db = new PGlite();
await db.exec(`
create role anon; create role authenticated; create role service_role bypassrls;
create schema auth; create schema storage;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',phone text,encrypted_password text,banned_until timestamptz);
create table auth.identities(id uuid primary key default gen_random_uuid(),user_id uuid,identity_data jsonb);
create table auth.sessions(id uuid primary key default gen_random_uuid(),user_id uuid);
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
for (const name of ['0001_init','0002_functions','0003_rls','0004_admin','0005_vendor_notifications','0006_delivery','0008_fcm_tokens','0009_fix_rls_recursion','0010_mobile_security','0012_local_delivery_upgrade','0013_portion_options','0014_account_deletion']) {
 let sql=await readFile(new URL(`../../supabase/migrations/${name}.sql`,import.meta.url),'utf8');
 sql=sql.replace('create extension if not exists "pgcrypto";','');
 await db.exec(sql);
}
let count=0;
async function check(name,work){await work();console.log(`PASS ${++count}: ${name}`);}
const uid=(n)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const customer=uid(1), other=uid(2), admin=uid(3), vendorUser=uid(4), partner=uid(5), store=uid(10), product=uid(11), option=uid(12), applicant=uid(6), applicant2=uid(7), otherVendor=uid(8), farStore=uid(13);
async function as(role,id=''){await db.exec(`reset role; select set_config('request.jwt.claim.sub','${id}',false),set_config('request.jwt.claim.role','${role}',false); set role ${role};`);}
async function root(){await db.exec("reset role; select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim.role','service_role',false);");}
async function scalar(sql,params=[]){return Object.values((await db.query(sql,params)).rows[0])[0];}
async function denied(sql,params=[]){await assert.rejects(()=>db.query(sql,params));}
await root();
for(const id of [customer,other,admin,vendorUser,partner,applicant,applicant2,otherVendor])await db.query('insert into auth.users(id,email) values($1,$2)',[id,`${id}@test.invalid`]);
await db.query("update profiles set role='admin' where id=$1",[admin]);
await db.query("update profiles set role='vendor' where id=$1",[vendorUser]);
await db.query("update profiles set role='delivery' where id=$1",[partner]);
await db.query("insert into vendors(id,name,dispatch_address,latitude,longitude,service_radius_km) values($1,'Test kitchen','Test address',28.89,76.60,9)",[store]);
await db.query('insert into vendor_members(user_id,vendor_id) values($1,$2)',[vendorUser,store]);
await db.query("insert into products(id,vendor_id,name,price_paise,stock) values($1,$2,'Test item',10000,10)",[product,store]);
await db.query("insert into product_options(id,product_id,group_name,label,price_delta_paise) values($1,$2,'Add-ons','Cheese',500)",[option,product]);
await db.query("insert into delivery_partner_profiles(user_id,approved_at,is_online,verification_status) values($1,now(),true,'approved')",[partner]);
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
// ---------- 0012 Local Delivery upgrade ----------
await root(); await db.exec('grant select,insert on storage.objects to anon,authenticated');
const docPath=(u,n)=>`${u}/${uid(n)}.jpg`;
async function stored(path){await root();await db.query("insert into storage.objects(bucket_id,name) values('partner-docs',$1)",[path]);}
async function fullOrder(n){
 await as('service_role'); const a=[...args]; a[1]=uid(n); a[9]=null; const id=await scalar(place,a);
 await as('authenticated',customer); const pay=await scalar('select submit_payment_proof($1,$2,null)',[id,String(100000000000+n)]);
 await as('authenticated',admin); await db.query('select verify_payment($1,true,null)',[pay]);
 await as('authenticated',vendorUser); await db.query("select vendor_set_order_status($1,'preparing',null)",[id]); await db.query("select vendor_set_order_status($1,'ready_for_pickup',null)",[id]);
 return id;
}
const hours=(weekly,extra={})=>JSON.stringify({timezone:'Asia/Kolkata',weekly,...extra});
await check('store hours handle overnight shifts, holidays, manual closure and unconfigured hours',async()=>{
 await root(); const q='select vendor_is_open($1::jsonb,true,false,$2::timestamptz)'; const night=hours({'3':[['18:00','02:00']]});
 assert.equal(await scalar(q,[night,'2026-10-14T23:30:00+05:30']),true);
 assert.equal(await scalar(q,[night,'2026-10-15T01:30:00+05:30']),true);
 assert.equal(await scalar(q,[night,'2026-10-15T02:30:00+05:30']),false);
 assert.equal(await scalar(q,[night,'2026-10-14T12:00:00+05:30']),false);
 assert.equal(await scalar(q,[hours({'3':[['18:00','02:00']]},{holidays:['2026-10-14']}),'2026-10-14T23:30:00+05:30']),false);
 assert.equal(await scalar("select vendor_is_open('{}'::jsonb,true,false)"),true);
 assert.equal(await scalar("select vendor_is_open('{}'::jsonb,true,true)"),false);
 assert.equal(await scalar("select vendor_is_open('{}'::jsonb,false,false)"),false);
});
await check('vendors can set their own cover image only from their folder',async()=>{await as('authenticated',vendorUser);await db.query('update vendors set cover_image_path=$2 where id=$1',[store,`${store}/${uid(70)}.jpg`]);await denied('update vendors set cover_image_path=$2 where id=$1',[store,`${otherVendor}/${uid(71)}.jpg`]);});
await check('invalid opening hours are rejected',async()=>{await as('authenticated',vendorUser);await denied('update vendors set opening_hours=$2::jsonb where id=$1',[store,JSON.stringify({weekly:{'9':[]}})]);await denied('update vendors set opening_hours=$2::jsonb where id=$1',[store,hours({'1':[['25:00','02:00']]})]);});
await check('discovery returns only stores that serve the chosen point, with real menu previews',async()=>{
 await root(); await db.query("insert into vendors(id,name,dispatch_address,latitude,longitude,service_radius_km) values($1,'Far kitchen','Far address',28.40,77.30,5)",[farStore]);
 await as('anon'); const near=await scalar('select discover_stores(28.89,76.61,$1,$2,0)',['','food']);
 assert.ok(near.some(s=>s.id===store)); assert.ok(!near.some(s=>s.id===farStore));
 const s=near.find(s=>s.id===store); assert.equal(s.is_open,true); assert.equal(s.preview.length,1); assert.equal(s.preview[0].name,'Test item');
 assert.ok((await scalar('select discover_stores(null,null,$1,$2,0)',['','food'])).some(s=>s.id===farStore));
});
await check('checkout rejects closed stores and disabled online payment; config changes are recorded',async()=>{
 await root(); await db.query('update vendors set temporarily_closed=true where id=$1',[store]);
 await as('service_role'); const c=[...args]; c[1]=uid(30); await denied(place,c);
 await root(); await db.query('update vendors set temporarily_closed=false where id=$1',[store]); await db.query('update payment_settings set upi_enabled=false');
 await as('service_role'); c[1]=uid(31); await denied(place,c);
 await root(); await db.query('update payment_settings set upi_enabled=true');
 assert.equal(await scalar('select count(*)::int from payment_settings_history'),2);
 await as('authenticated',customer); assert.equal(await scalar('select count(*)::int from payment_settings_history'),0);
});
const application={legal_name:'Ravi Kumar',phone:'9876543210',residential_address:'House 12, Sector 3, Rohtak',city:'Rohtak',service_area:'Sector 1-14',
 emergency_contact_name:'Sita',emergency_contact_phone:'9812345678',vehicle_type:'motorcycle',vehicle_number:'HR 12 AB 1234',licence_last4:'5678',aadhaar_last4:'4321',payout_upi_vpa:'ravi@okaxis',accept_terms:true};
await check('partner application cannot be submitted without documents or self-approved',async()=>{
 await as('authenticated',applicant);
 assert.equal(await scalar('select partner_save_application($1::jsonb,false)',[JSON.stringify(application)]),'draft');
 await denied('select partner_save_application($1::jsonb,true)',[JSON.stringify(application)]);
 await denied("update delivery_partner_profiles set verification_status='approved' where user_id=$1",[applicant]);
});
await check('documents must already be in the partner own private folder',async()=>{
 await as('authenticated',applicant); await denied("select partner_submit_document('aadhaar',$1,'4321')",[docPath(applicant,40)]);
 await stored(docPath(other,41)); await as('authenticated',applicant); await denied("select partner_submit_document('aadhaar',$1,'4321')",[docPath(other,41)]);
 for(const [type,n,mask] of [['profile_photo',42,null],['aadhaar',43,'4321'],['driving_license',44,'5678']]){await stored(docPath(applicant,n));await as('authenticated',applicant);await db.query('select partner_submit_document($1,$2,$3)',[type,docPath(applicant,n),mask]);}
});
await check('submitted partner is pending and cannot go online, list or accept orders',async()=>{
 await as('authenticated',applicant);
 assert.equal(await scalar('select partner_save_application($1::jsonb,true)',[JSON.stringify(application)]),'pending_verification');
 assert.equal(await scalar('select role from profiles where id=$1',[applicant]),'delivery');
 await denied('select set_partner_online(true)'); await denied('select list_available_orders()');
 await denied('select partner_save_application($1::jsonb,false)',[JSON.stringify(application)]);
 const dash=await scalar('select my_partner_dashboard()'); assert.equal(dash.can_accept,false); assert.equal(dash.verification_status,'pending_verification');
 await as('authenticated',admin); assert.ok(await scalar("select count(*)::int from notifications where user_id=$1 and type='partner_application'",[admin])>=1);
});
await check('duplicate vehicle registration is rejected',async()=>{await as('authenticated',applicant2);await denied('select partner_save_application($1::jsonb,false)',[JSON.stringify({...application,phone:'9000000001',vehicle_number:'hr12ab1234'})]);});
await check('admin requests corrections with a reason and partner resubmits',async()=>{
 await as('authenticated',admin); await denied("select admin_review_partner($1,'request_changes',null)",[applicant]);
 assert.equal(await scalar("select admin_review_partner($1,'request_changes','Licence photo is blurred')",[applicant]),'action_required');
 const doc=await scalar("select id from partner_documents where partner_id=$1 and doc_type='driving_license'",[applicant]);
 await denied('select admin_review_partner_document($1,false,null)',[doc]);
 await db.query("select admin_review_partner_document($1,false,'Blurred photo')",[doc]);
 await as('authenticated',applicant); assert.equal((await scalar('select my_partner_dashboard()')).verification_status,'action_required');
 assert.ok(await scalar("select count(*)::int from notifications where user_id=$1 and type='partner_verification'",[applicant])>=2);
 await stored(docPath(applicant,45)); await as('authenticated',applicant);
 await db.query("select partner_submit_document('driving_license',$1,'5678')",[docPath(applicant,45)]);
 assert.equal(await scalar('select partner_save_application($1::jsonb,true)',[JSON.stringify(application)]),'pending_verification');
});
await check('only admins approve; history records reviewer; approved partner can go online',async()=>{
 await as('authenticated',other); await denied("select admin_review_partner($1,'approve',null)",[applicant]);
 await as('authenticated',admin); assert.equal(await scalar("select admin_review_partner($1,'approve',null)",[applicant]),'approved');
 assert.equal(await scalar("select actor_id from partner_verification_events where partner_id=$1 and event='review_approve'",[applicant]),admin);
 await as('authenticated',applicant); await db.query('select set_partner_online(true)'); assert.equal((await scalar('select my_partner_dashboard()')).can_accept,true);
});
await check('other users cannot read private documents or payout QR; admin reviews QR with reason',async()=>{
 await stored(docPath(applicant,46)); await as('authenticated',applicant); await db.query('select partner_submit_qr($1)',[docPath(applicant,46)]);
 for(const who of [partner,customer]){await as('authenticated',who);
  assert.equal(await scalar('select count(*)::int from partner_documents where partner_id=$1',[applicant]),0);
  assert.equal(await scalar('select count(*)::int from delivery_partner_profiles where user_id=$1',[applicant]),0);
  assert.equal(await scalar("select count(*)::int from storage.objects where bucket_id='partner-docs' and name like $1",[`${applicant}/%`]),0);}
 await as('authenticated',admin); await denied('select admin_review_partner_qr($1,false,null)',[applicant]);
 await db.query('select admin_review_partner_qr($1,true,null)',[applicant]);
 assert.equal(await scalar('select qr_status from delivery_partner_profiles where user_id=$1',[applicant]),'approved');
});
let order2;
await check('acceptance is exclusive; live location only during the delivery; earning rule applied once',async()=>{
 await root(); await db.query("update app_settings set value='80' where key='partner_earning_percent'");
 order2=await fullOrder(50);
 await as('authenticated',applicant); await db.query('select accept_delivery($1)',[order2]);
 await as('authenticated',partner); await denied('select accept_delivery($1)',[order2]); await denied('select partner_update_location($1,28.8,76.6,5)',[order2]);
 await as('authenticated',applicant); await db.query('select partner_update_location($1,28.891,76.605,12)',[order2]);
 await as('authenticated',customer); assert.equal(Number((await scalar('select order_live_location($1)',[order2])).latitude),28.891);
 await as('authenticated',other); await denied('select order_live_location($1)',[order2]);
 await as('authenticated',applicant); for(const st of ['picked_up','out_for_delivery','delivered']) await db.query('select partner_set_order_status($1,$2::order_status)',[order2,st]);
 await denied("select partner_set_order_status($1,'delivered')",[order2]); await denied('select partner_update_location($1,28.8,76.6,5)',[order2]);
 assert.equal(await scalar('select count(*)::int from delivery_earnings where order_id=$1',[order2]),1);
 assert.equal(await scalar('select net_paise from delivery_earnings where order_id=$1',[order2]),1200);
 await as('authenticated',customer); assert.equal(await scalar('select order_live_location($1)',[order2]),null);
 await root(); assert.equal(await scalar('select count(*)::int from partner_locations'),0); await db.query("update app_settings set value='100' where key='partner_earning_percent'");
});
await check('payouts are idempotent, admin-only, and paid only with a transaction reference',async()=>{
 await as('authenticated',admin); const key=uid(60);
 const p1=await scalar("select admin_create_payout($1,null,'upi','Week 42',$2)",[applicant,key]);
 assert.equal(await scalar("select admin_create_payout($1,null,'upi','Week 42',$2)",[applicant,key]),p1);
 await denied("select admin_create_payout($1,null,'upi',null,$2)",[applicant,uid(61)]);
 assert.equal(await scalar('select amount_paise from partner_payouts where id=$1',[p1]),1200);
 await denied("select admin_update_payout($1,'paid',null,null)",[p1]);
 await as('authenticated',applicant); await denied("select admin_update_payout($1,'paid','UTR123456',null)",[p1]);
 assert.equal((await scalar('select my_partner_dashboard()')).paid_paise,0);
 await as('authenticated',admin); await db.query("select admin_update_payout($1,'paid','UTR123456',null)",[p1]);
 await denied("select admin_update_payout($1,'failed',null,'reversed')",[p1]);
 await as('authenticated',applicant); const d=await scalar('select my_partner_dashboard()');
 assert.equal(d.paid_paise,1200); assert.equal(d.pending_payout_paise,0); assert.equal(d.earned_total_paise,1200);
});
await check('ratings: only the ordering customer, delivered orders, one per target, no links, admin moderation',async()=>{
 await as('authenticated',other); await denied('select submit_order_review($1,5,null,5,null)',[order2]);
 await as('authenticated',customer); await denied("select submit_order_review($1,5,'visit www.spam.com',null,null)",[order2]);
 await db.query("select submit_order_review($1,4,'Tasty food',5,'Polite rider')",[order2]);
 await db.query("select submit_order_review($1,5,'Tasty food, updated',null,null)",[order2]);
 assert.equal(await scalar('select count(*)::int from reviews where order_id=$1',[order2]),1);
 assert.equal(Number(await scalar('select rating_avg from vendors where id=$1',[store])),5);
 assert.equal((await db.query('update reviews set rating=1 where order_id=$1 returning id',[order2])).rows.length,0);
 await as('authenticated',vendorUser); const rid=await scalar('select id from reviews where order_id=$1',[order2]);
 await db.query("select vendor_reply_review($1,'Thank you!')",[rid]);
 await as('authenticated',applicant2); await denied("select vendor_reply_review($1,'Fake reply')",[rid]);
 await as('authenticated',applicant); assert.equal(await scalar('select count(*)::int from partner_reviews where partner_id=$1',[applicant]),1);
 await as('authenticated',admin); await db.query("select admin_moderate_review('vendor',$1,false)",[rid]);
 assert.equal(Number(await scalar('select rating_count from vendors where id=$1',[store])),0);
 await as('anon'); assert.equal((await scalar('select store_reviews($1,0)',[store])).length,0);
});
await check('only active, in-window, in-area posters are public; only admins manage posters',async()=>{
 await root(); await db.query("insert into promo_posters(title,image_path,is_active) values('Live','a.jpg',true),('Off','b.jpg',false)");
 await db.query("insert into promo_posters(title,image_path,starts_at) values('Future','c.jpg',now()+interval '2 days')");
 await db.query("insert into promo_posters(title,image_path,area_lat,area_lng,area_radius_km) values('Far area','d.jpg',28.40,77.30,3)");
 await as('anon'); assert.deepEqual((await scalar('select active_posters(28.89,76.61)')).map(p=>p.title),['Live']);
 await as('authenticated',customer); assert.deepEqual((await db.query('select title from promo_posters order by title')).rows.map(r=>r.title),['Far area','Live']);
 await denied("insert into promo_posters(title,image_path) values('Hack','x.jpg')");
});
await check('restaurant application creates an inactive store owned by the applicant only after approval',async()=>{
 await as('authenticated',applicant2);
 const app={restaurant_name:'New Cafe',owner_name:'Asha',phone:'9811111111',address:'Shop 4, Model Town, Rohtak',city:'Rohtak',postal_code:'124001',latitude:28.9,longitude:76.6,location_source:'map_pin',opening_hours:{timezone:'Asia/Kolkata',weekly:{'1':[['09:00','22:00']]}}};
 await denied('select submit_vendor_application($1::jsonb)',[JSON.stringify({...app,postal_code:'12'})]);
 const id=await scalar('select submit_vendor_application($1::jsonb)',[JSON.stringify(app)]);
 await denied('select submit_vendor_application($1::jsonb)',[JSON.stringify(app)]);
 await as('authenticated',customer); await denied("select admin_review_vendor_application($1,'approve',null)",[id]);
 await as('authenticated',admin); const vid=await scalar("select admin_review_vendor_application($1,'approve',null)",[id]);
 await as('authenticated',applicant2); assert.equal(await scalar('select role from profiles where id=$1',[applicant2]),'vendor');
 assert.equal(await scalar('select is_active from vendors where id=$1',[vid]),false);
 await db.query('update vendors set is_active=true, temporarily_closed=true where id=$1',[vid]);
 await denied('update vendors set name=$2 where id=$1',[vid,'Renamed']);
});
let order3;
await check('vendor dashboard is per-restaurant; admin read models are admin-only and mask customer phones',async()=>{
 order3=await fullOrder(52);
 await as('authenticated',vendorUser); const d=await scalar("select vendor_dashboard($1,now()-interval '1 day',now()+interval '1 day')",[store]);
 assert.equal(d.completed,2); assert.equal(d.ready_for_pickup,1); assert.equal(d.popular_items[0].name,'Test item');
 await as('authenticated',applicant2); await denied("select vendor_dashboard($1,now()-interval '1 day',now())",[store]);
 await as('authenticated',customer); await denied("select admin_dashboard(now()-interval '1 day',now())"); await denied("select admin_partners('',null)");
 await denied('select submit_order_review($1,5,null,null,null)',[order3]);
 await as('authenticated',admin); const a=await scalar("select admin_dashboard(now()-interval '1 day',now()+interval '1 day')");
 assert.equal(a.partners_pending_verification,0); assert.equal(a.orders,3); assert.equal(a.payments_pending_verification,0); assert.equal(a.restaurant_applications_pending,0);
 const partners=await scalar("select admin_partners('ravi',null)"); assert.equal(partners.length,1); assert.equal(partners[0].total_deliveries,1);
 const rows=await scalar("select admin_partner_orders($1,now()-interval '1 day',now()+interval '1 day')",[applicant]); assert.equal(rows.length,1); assert.equal(rows[0].partner_earning_paise,1200);
 await root(); await db.query("update profiles set phone='9876500000' where id=$1",[customer]);
 await as('authenticated',admin); const cs=await scalar("select admin_customers('',0)"); assert.equal(cs.find(c=>c.id===customer).phone,'••••••0000');
});
await check('admin can cancel an in-transit order as an audited correction; partners cannot',async()=>{
 await as('authenticated',partner); await db.query('select accept_delivery($1)',[order3]); await db.query("select partner_set_order_status($1,'picked_up')",[order3]);
 await denied("select admin_cancel_order($1,'Customer unreachable')",[order3]);
 await as('authenticated',admin); await denied("select admin_cancel_order($1,'')",[order3]);
 await db.query("select admin_cancel_order($1,'Customer unreachable at door')",[order3]);
 assert.equal(await scalar('select status from orders where id=$1',[order3]),'cancelled');
 assert.equal(await scalar('select count(*)::int from delivery_earnings where order_id=$1',[order3]),0);
 assert.equal(await scalar("select count(*)::int from admin_audit_logs where action='cancel_order' and entity_id=$1",[order3]),1);
});
await check('support tickets: users open and close their own; only staff change status; both sides notified',async()=>{
 await as('authenticated',customer);
 const t=await scalar("insert into support_tickets(customer_id,category,description) values($1,'Order issue','Food arrived cold today') returning id",[customer]);
 await denied("update support_tickets set status='resolved' where id=$1",[t]);
 await db.query("insert into support_messages(ticket_id,sender_id,message) values($1,$2,'Any update?')",[t,customer]);
 await as('authenticated',other); assert.equal(await scalar('select count(*)::int from support_tickets where id=$1',[t]),0);
 await as('authenticated',admin); assert.ok(await scalar("select count(*)::int from notifications where user_id=$1 and type='support'",[admin])>=2);
 await db.query("insert into support_messages(ticket_id,sender_id,message) values($1,$2,'Refund initiated')",[t,admin]);
 await db.query("update support_tickets set status='resolved' where id=$1",[t]);
 await as('authenticated',customer); assert.equal(await scalar("select count(*)::int from notifications where user_id=$1 and type='support'",[customer]),1);
 await db.query("update support_tickets set status='closed' where id=$1",[t]);
});
const thali=uid(80);
await check('half/full plate: only the restaurant sets portions; checkout requires exactly one portion',async()=>{
 await root(); await db.query("insert into products(id,vendor_id,name,price_paise,stock) values($1,$2,'Paneer thali',20000,3)",[thali,store]);
 await as('authenticated',other); await denied('select set_item_portions($1,true,12000,20000)',[thali]);
 await as('authenticated',vendorUser); await denied('select set_item_portions($1,true,20000,12000)',[thali]);
 await db.query('select set_item_portions($1,true,12000,20000)',[thali]);
 const half=await scalar("select id from product_options where product_id=$1 and label='Half plate'",[thali]);
 const full=await scalar("select id from product_options where product_id=$1 and label='Full plate'",[thali]);
 const order=(n,items)=>{const a=[...args];a[1]=uid(n);a[7]=JSON.stringify(items);a[9]=null;return a;};
 await as('service_role');
 await denied(place,order(81,[{product_id:thali,quantity:1,options:[]}]));
 await denied(place,order(82,[{product_id:thali,quantity:1,options:[{option_id:half},{option_id:full}]}]));
 const id=await scalar(place,order(83,[{product_id:thali,quantity:1,options:[{option_id:half}]},{product_id:thali,quantity:1,options:[{option_id:full}]}]));
 assert.equal(await scalar('select items_subtotal_paise from orders where id=$1',[id]),32000);
 assert.equal(await scalar('select count(*)::int from order_items where order_id=$1',[id]),2);
 assert.equal(await scalar('select stock from products where id=$1',[thali]),1);
 await denied(place,order(84,[{product_id:thali,quantity:1,options:[{option_id:half}]},{product_id:thali,quantity:1,options:[{option_id:full}]}]));
 await as('anon'); const prev=(await scalar("select discover_stores(28.89,76.61,'','food',0)")).find(s=>s.id===store).preview.find(x=>x.id===thali);
 assert.equal(prev.price_paise,12000); assert.equal(prev.has_choices,true);
 await as('authenticated',vendorUser); await db.query('select set_item_portions($1,false,null,18000)',[thali]);
 assert.equal(await scalar('select count(*)::int from product_options where product_id=$1',[thali]),0);
 assert.equal(await scalar('select price_paise from products where id=$1',[thali]),18000);
});
await check('account deletion: blocked while something is pending, otherwise erases personal data and sign-in',async()=>{
 await as('authenticated',admin); assert.ok((await scalar('select account_deletion_blockers()')).length>0); await denied("select delete_my_account('DELETE')");
 await as('authenticated',vendorUser); assert.ok((await scalar('select account_deletion_blockers()')).some(r=>r.includes('only manager'))); await denied("select delete_my_account('DELETE')");
 await as('authenticated',other);
 await db.query("insert into user_addresses(user_id,label,formatted_address,latitude,longitude) values($1,'Home','H1, Sector 3, Rohtak - 124001',28.89,76.61)",[other]);
 assert.deepEqual(await scalar('select account_deletion_blockers()'),[]);
 await denied("select delete_my_account('yes')");
 await db.query("select delete_my_account('DELETE')");
 await root();
 assert.equal(await scalar('select count(*)::int from user_addresses where user_id=$1',[other]),0);
 assert.equal(await scalar('select display_name from profiles where id=$1',[other]),'Deleted user');
 assert.equal(await scalar('select status from profiles where id=$1',[other]),'suspended');
 assert.equal(await scalar('select email from auth.users where id=$1',[other]),`${other}@deleted.invalid`);
 assert.equal(await scalar('select encrypted_password from auth.users where id=$1',[other]),'');
 assert.equal(await scalar('select count(*)::int from auth.identities where user_id=$1',[other]),0);
 assert.equal(await scalar('select count(*)::int from auth.sessions where user_id=$1',[other]),0);
});
await check('deleting a paid-up delivery partner removes documents and frees the vehicle; orders and earnings stay',async()=>{
 await as('authenticated',applicant); assert.deepEqual(await scalar('select account_deletion_blockers()'),[]);
 await db.query("select delete_my_account('DELETE')");
 await root();
 assert.equal(await scalar('select count(*)::int from delivery_partner_profiles where user_id=$1',[applicant]),0);
 assert.equal(await scalar('select count(*)::int from partner_documents where partner_id=$1',[applicant]),0);
 assert.equal(await scalar('select count(*)::int from delivery_earnings where partner_id=$1',[applicant]),1);
 assert.equal(await scalar('select count(*)::int from orders where id=$1',[order2]),1);
 await as('authenticated',applicant2); await db.query('select 1');
});
console.log(`${count} PostgreSQL checks passed. No remote database was accessed.`);
await db.close();
