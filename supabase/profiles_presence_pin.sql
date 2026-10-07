-- Run after setup.sql. Adds editable profiles, last-seen/online status,
-- and a shared four-digit app lock on top of email/password authentication.
create extension if not exists pgcrypto with schema extensions;

create table if not exists private.chat_pin_settings (
  singleton boolean primary key default true check (singleton),
  pin_hash text not null,
  created_at timestamptz not null default now()
);
create table if not exists private.chat_pin_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  failed_attempts integer not null default 0 check (failed_attempts between 0 and 5),
  locked_until timestamptz,
  primary key (user_id)
);
-- Make lockouts persist across sign-outs and new email sessions.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'private' and table_name = 'chat_pin_attempts' and column_name = 'session_id'
  ) then
    alter table private.chat_pin_attempts drop constraint if exists chat_pin_attempts_pkey;
    alter table private.chat_pin_attempts drop column session_id;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'private.chat_pin_attempts'::regclass and conname = 'chat_pin_attempts_pkey'
  ) then
    alter table private.chat_pin_attempts add constraint chat_pin_attempts_pkey primary key (user_id);
  end if;
end;
$$;
create table if not exists private.chat_pin_unlocks (
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  unlocked_until timestamptz not null,
  primary key (user_id, session_id)
);
alter table private.chat_pin_settings enable row level security;
alter table private.chat_pin_attempts enable row level security;
alter table private.chat_pin_unlocks enable row level security;
revoke all on table private.chat_pin_settings, private.chat_pin_attempts, private.chat_pin_unlocks
  from public, anon, authenticated;

create table if not exists public.chat_profiles (
  user_id uuid primary key references public.chat_members(user_id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 40),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.chat_profiles enable row level security;
revoke all on public.chat_profiles from anon, authenticated;
grant select on public.chat_profiles to authenticated;
grant update (display_name, last_seen_at, updated_at) on public.chat_profiles to authenticated;

insert into public.chat_profiles (user_id, display_name)
select member.user_id,
       left(coalesce(nullif(trim(auth_user.raw_user_meta_data ->> 'display_name'), ''), split_part(member.email, '@', 1)), 40)
from public.chat_members as member
join auth.users as auth_user on auth_user.id = member.user_id
on conflict (user_id) do nothing;

create or replace function private.is_chat_pin_unlocked()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.chat_pin_unlocks as unlock
    where unlock.user_id = (select auth.uid())
      and unlock.session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
      and unlock.unlocked_until > now()
  );
$$;
revoke all on function private.is_chat_pin_unlocked() from public, anon, authenticated;
grant execute on function private.is_chat_pin_unlocked() to authenticated;

create or replace function private.is_chat_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.chat_members where user_id = (select auth.uid())
  ) and (select private.is_chat_pin_unlocked());
$$;
revoke all on function private.is_chat_member() from public, anon, authenticated;
grant execute on function private.is_chat_member() to authenticated;

create or replace function public.chat_pin_status()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from public.chat_members where user_id = (select auth.uid())
  ) then
    return 'denied';
  end if;
  if not exists (select 1 from private.chat_pin_settings where singleton) then
    return 'setup';
  end if;
  if (select private.is_chat_pin_unlocked()) then
    return 'unlocked';
  end if;
  return 'locked';
end;
$$;

create or replace function public.lock_chat_pin()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then return false; end if;
  delete from private.chat_pin_unlocks
  where user_id = (select auth.uid())
    and session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid;
  return true;
end;
$$;

create or replace function public.setup_chat_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_created boolean := false;
begin
  if (select auth.uid()) is null or v_session_id is null or not exists (
    select 1 from public.chat_members where user_id = (select auth.uid())
  ) or p_pin !~ '^[0-9]{4}$' then
    return false;
  end if;

  insert into private.chat_pin_settings (singleton, pin_hash)
  values (true, extensions.crypt(p_pin, extensions.gen_salt('bf', 12)))
  on conflict (singleton) do nothing
  returning true into v_created;

  if coalesce(v_created, false) then
    insert into private.chat_pin_unlocks (user_id, session_id, unlocked_until)
    values ((select auth.uid()), v_session_id, now() + interval '30 minutes')
    on conflict (user_id, session_id) do update set unlocked_until = excluded.unlocked_until;
    return true;
  end if;
  return false;
end;
$$;

create or replace function public.verify_chat_pin(p_pin text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_hash text;
  v_attempts integer := 0;
  v_locked_until timestamptz;
begin
  if v_user_id is null or v_session_id is null or not exists (
    select 1 from public.chat_members where user_id = v_user_id
  ) then
    return 'denied';
  end if;

  select pin_hash into v_hash from private.chat_pin_settings where singleton;
  if v_hash is null then return 'setup_required'; end if;

  insert into private.chat_pin_attempts (user_id, failed_attempts)
  values (v_user_id, 0)
  on conflict (user_id) do nothing;
  select failed_attempts, locked_until into v_attempts, v_locked_until
  from private.chat_pin_attempts
  where user_id = v_user_id
  for update;
  if v_locked_until > now() then return 'locked'; end if;
  if p_pin !~ '^[0-9]{4}$' then p_pin := ''; end if;

  if extensions.crypt(p_pin, v_hash) = v_hash then
    insert into private.chat_pin_attempts (user_id, failed_attempts, locked_until)
    values (v_user_id, 0, null)
    on conflict (user_id) do update set failed_attempts = 0, locked_until = null;
    insert into private.chat_pin_unlocks (user_id, session_id, unlocked_until)
    values (v_user_id, v_session_id, now() + interval '30 minutes')
    on conflict (user_id, session_id) do update set unlocked_until = excluded.unlocked_until;
    return 'verified';
  end if;

  v_attempts := least(coalesce(v_attempts, 0) + 1, 5);
  insert into private.chat_pin_attempts (user_id, failed_attempts, locked_until)
  values (v_user_id, v_attempts,
          case when v_attempts >= 5 then now() + interval '15 minutes' else null end)
  on conflict (user_id) do update
    set failed_attempts = excluded.failed_attempts, locked_until = excluded.locked_until;
  if v_attempts >= 5 then return 'locked'; end if;
  return 'incorrect';
end;
$$;

revoke all on function public.chat_pin_status() from public, anon;
revoke all on function public.lock_chat_pin() from public, anon;
revoke all on function public.setup_chat_pin(text) from public, anon;
revoke all on function public.verify_chat_pin(text) from public, anon;
grant execute on function public.chat_pin_status() to authenticated;
grant execute on function public.lock_chat_pin() to authenticated;
grant execute on function public.setup_chat_pin(text) to authenticated;
grant execute on function public.verify_chat_pin(text) to authenticated;

drop policy if exists "Only members can read chat messages" on public.chat_messages;
create policy "Only members can read chat messages"
  on public.chat_messages for select to authenticated
  using ((select private.is_chat_member()));
drop policy if exists "Members can send their own messages" on public.chat_messages;
create policy "Members can send their own messages"
  on public.chat_messages for insert to authenticated
  with check (
    (select private.is_chat_member())
    and sender_id = (select auth.uid())
    and downloaded_at is null
    and downloaded_by is null
  );

drop policy if exists "Chat members can view profiles" on public.chat_profiles;
create policy "Chat members can view profiles"
  on public.chat_profiles for select to authenticated
  using ((select private.is_chat_member()));
drop policy if exists "Members can update their own profile" on public.chat_profiles;
create policy "Members can update their own profile"
  on public.chat_profiles for update to authenticated
  using (user_id = (select auth.uid()) and (select private.is_chat_member()))
  with check (user_id = (select auth.uid()) and (select private.is_chat_member()));

create or replace function private.enroll_allowed_chat_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is null or not exists (
    select 1 from private.chat_allowed_emails where email = lower(new.email)
  ) then
    raise exception using errcode = '42501', message = 'This email is not approved for this chat.';
  end if;
  insert into public.chat_members (user_id, email)
  values (new.id, lower(new.email))
  on conflict (user_id) do nothing;
  insert into public.chat_profiles (user_id, display_name)
  values (
    new.id,
    left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1)), 40)
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;
revoke all on function private.enroll_allowed_chat_user() from public, anon, authenticated;

drop policy if exists "Chat members can read chat files" on storage.objects;
create policy "Chat members can read chat files"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat-files' and (select private.is_chat_member()));
drop policy if exists "Chat members can upload their own files" on storage.objects;
create policy "Chat members can upload their own files"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-files'
    and (select private.is_chat_member())
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
drop policy if exists "Recipients can delete received files" on storage.objects;
create policy "Recipients can delete received files"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-files'
    and (select private.is_chat_member())
    and (storage.foldername(name))[1] <> (select auth.uid()::text)
  );
drop policy if exists "Senders can delete unlinked uploads" on storage.objects;
create policy "Senders can delete unlinked uploads"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-files'
    and (select private.is_chat_member())
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and not exists (select 1 from public.chat_messages where file_path = name)
  );

drop policy if exists "Chat members can listen to online presence" on realtime.messages;
create policy "Chat members can listen to online presence"
  on realtime.messages for select to authenticated
  using (
    extension = 'presence'
    and (select realtime.topic()) = 'just-us-presence'
    and (select private.is_chat_member())
  );
drop policy if exists "Chat members can publish online presence" on realtime.messages;
create policy "Chat members can publish online presence"
  on realtime.messages for insert to authenticated
  with check (
    extension = 'presence'
    and (select realtime.topic()) = 'just-us-presence'
    and (select private.is_chat_member())
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_profiles'
  ) then
    alter publication supabase_realtime add table public.chat_profiles;
  end if;
end;
$$;
