-- Webhook credentials live in Vault, never in app-readable settings.
begin;
create or replace function public.on_notification_insert_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_url text; v_token text;
begin
 select decrypted_secret into v_url from vault.decrypted_secrets where name='dastak_push_url' limit 1;
 select decrypted_secret into v_token from vault.decrypted_secrets where name='dastak_push_token' limit 1;
 if coalesce(v_url,'')='' or coalesce(v_token,'')='' then
   raise warning 'Dastak push webhook is not configured';
   return new;
 end if;
 perform net.http_post(url:=v_url,
   headers:=jsonb_build_object('content-type','application/json','authorization','Bearer '||v_token),
   body:=jsonb_build_object('notification_id',new.id,'user_id',new.user_id,'title',new.title,
     'body',new.body,'order_id',new.order_id,'type',new.type),timeout_milliseconds:=10000);
 return new;
end; $$;
revoke all on function public.on_notification_insert_push() from public,anon,authenticated;
commit;
