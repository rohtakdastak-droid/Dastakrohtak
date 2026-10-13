-- Self-service account deletion (required by Google Play for apps with sign-up).
-- Personal data is erased and sign-in is disabled. Orders, payments and earnings are kept for
-- accounting but no longer link to a name, phone or email.
begin;

create or replace function account_deletion_blockers() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare me uuid := auth.uid(); p profiles; reasons jsonb := '[]'::jsonb;
begin
 if me is null then raise exception 'Please sign in'; end if;
 select * into p from profiles where id=me;
 if p.role='admin' then reasons:=reasons||jsonb_build_array('Admin accounts must be removed by another admin.'); end if;
 if exists(select 1 from orders where customer_id=me and status in
   ('pending_payment','payment_review','vendor_confirmation','preparing','ready_for_pickup','assigned','picked_up','out_for_delivery')) then
   reasons:=reasons||jsonb_build_array('You have an order in progress. Wait until it is delivered or cancelled.'); end if;
 if exists(select 1 from payments py join orders o on o.id=py.order_id where o.customer_id=me and py.status='submitted') then
   reasons:=reasons||jsonb_build_array('A payment of yours is still being verified.'); end if;
 if exists(select 1 from delivery_assignments a join orders o on o.id=a.order_id
   where a.partner_id=me and a.status='accepted' and o.status in ('assigned','picked_up','out_for_delivery')) then
   reasons:=reasons||jsonb_build_array('Complete your active delivery first.'); end if;
 if exists(select 1 from delivery_earnings where partner_id=me and not settled) then
   reasons:=reasons||jsonb_build_array('You have unpaid delivery earnings. Contact support so we can pay you first.'); end if;
 if exists(select 1 from vendor_members m join vendors v on v.id=m.vendor_id
   where m.user_id=me and m.status='active' and v.archived_at is null
     and not exists(select 1 from vendor_members o where o.vendor_id=m.vendor_id and o.user_id<>me and o.status='active')) then
   reasons:=reasons||jsonb_build_array('You are the only manager of a restaurant. Ask support to transfer or close it first.'); end if;
 return reasons;
end; $$;

create or replace function delete_my_account(p_confirm text) returns void
language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); blockers jsonb;
begin
 if me is null then raise exception 'Please sign in'; end if;
 if upper(trim(coalesce(p_confirm,'')))<>'DELETE' then raise exception 'Type DELETE to confirm'; end if;
 perform 1 from profiles where id=me for update;
 blockers := account_deletion_blockers();
 if jsonb_array_length(blockers)>0 then raise exception '%', blockers->>0; end if;

 delete from user_addresses where user_id=me;
 delete from fcm_tokens where user_id=me;
 if to_regclass('public.push_subscriptions') is not null then
   execute 'delete from public.push_subscriptions where user_id=$1' using me;
 end if;
 delete from notifications where user_id=me;
 delete from support_tickets where customer_id=me;
 delete from vendor_members where user_id=me;
 delete from vendor_applications where applicant_id=me;
 delete from partner_locations where partner_id=me;
 delete from partner_documents where partner_id=me;
 delete from delivery_partner_profiles where user_id=me;
 update reviews set comment=null where customer_id=me;
 update partner_reviews set comment=null where customer_id=me;
 update orders set customer_note=null where customer_id=me;
 update profiles set display_name='Deleted user', phone=null, phone_verified=false, avatar_path=null,
   role='customer', status='suspended', updated_at=now() where id=me;

 -- Sign-in data: no email, no password, no identities or sessions remain.
 update auth.users set email=me::text||'@deleted.invalid', phone=null, encrypted_password='',
   raw_user_meta_data='{}'::jsonb, banned_until='infinity' where id=me;
 if to_regclass('auth.identities') is not null then execute 'delete from auth.identities where user_id=$1' using me; end if;
 if to_regclass('auth.sessions') is not null then execute 'delete from auth.sessions where user_id=$1' using me; end if;

 insert into admin_audit_logs(actor_id,action,entity,entity_id,reason) values(me,'account_deleted_by_user','profiles',me::text,null);
end; $$;
revoke all on function delete_my_account(text) from public,anon;
grant execute on function delete_my_account(text) to authenticated;
revoke all on function account_deletion_blockers() from public,anon;
grant execute on function account_deletion_blockers() to authenticated;

-- People remove their own private document files before deletion (Storage forbids SQL deletes).
drop policy if exists "partner document delete own" on storage.objects;
create policy "partner document delete own" on storage.objects for delete to authenticated using(
  bucket_id='partner-docs' and (storage.foldername(name))[1]=auth.uid()::text);

commit;
