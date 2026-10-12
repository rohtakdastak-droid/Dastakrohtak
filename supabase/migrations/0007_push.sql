-- Dastak: Web Push subscriptions + outbound-call hook.
-- Requires pg_net (preinstalled on Supabase).

create extension if not exists pg_net;

create table push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  last_sent_at timestamptz
);
create index push_subscriptions_user_idx on push_subscriptions(user_id);

alter table push_subscriptions enable row level security;

create policy "push subs self" on push_subscriptions
  for all using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());

-- Trigger: whenever a notification row is inserted, call the send-push Edge
-- Function so it can fan out to all registered devices for that user.
-- The function URL + a shared secret must be configured as database settings:
--   alter database postgres set "app.push_webhook_url"   to 'https://<ref>.functions.supabase.co/send-push';
--   alter database postgres set "app.push_webhook_token" to '<random-long-string>';
-- (and matching PUSH_WEBHOOK_TOKEN secret for the Edge Function).
-- If the settings aren't configured the trigger silently does nothing — in-app
-- realtime notifications still work.

create or replace function on_notification_insert_push()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_url text;
  v_token text;
begin
  begin
    v_url := current_setting('app.push_webhook_url', true);
    v_token := current_setting('app.push_webhook_token', true);
  exception when others then
    return new;
  end;

  if v_url is null or v_url = '' then
    return new;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || coalesce(v_token, '')
    ),
    body := jsonb_build_object(
      'notification_id', new.id,
      'user_id', new.user_id,
      'title', new.title,
      'body', new.body,
      'order_id', new.order_id,
      'type', new.type
    )
  );

  return new;
end;
$$;

drop trigger if exists trg_notification_push on notifications;
create trigger trg_notification_push
  after insert on notifications
  for each row execute function on_notification_insert_push();
