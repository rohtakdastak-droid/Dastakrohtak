-- FCM token storage for native Android/iOS push notifications.

create table fcm_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android',
  created_at timestamptz not null default now()
);

create index fcm_tokens_user_idx on fcm_tokens(user_id);

alter table fcm_tokens enable row level security;

create policy "fcm tokens self" on fcm_tokens
  for all using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());
