-- Metadata only: no customer records or secrets.
select jsonb_build_object(
 'columns',(select jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',udt_name,'nullable',is_nullable)) from information_schema.columns where table_schema='public'),
 'policies',(select jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'command',cmd,'qual',qual,'check',with_check)) from pg_policies where schemaname in('public','storage')),
 'functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'definition',pg_get_functiondef(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('create_order','verify_payment','vendor_set_order_status','partner_set_order_status','accept_delivery','is_admin','is_vendor_member')),
 'views',(select jsonb_agg(jsonb_build_object('name',c.relname,'options',c.reloptions)) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='v'),
 'buckets',(select jsonb_agg(jsonb_build_object('id',id,'public',public)) from storage.buckets)
) as audit;
