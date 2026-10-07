-- Run this file in the Supabase SQL Editor before either person signs up.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table if not exists private.chat_allowed_emails (
  email text primary key check (email = lower(email)),
  created_at timestamptz not null default now()
);
alter table private.chat_allowed_emails enable row level security;
revoke all on table private.chat_allowed_emails from public, anon, authenticated;

-- Preserve the allowlist when upgrading from the earlier public-table setup.
do $$
begin
  if to_regclass('public.chat_allowed_emails') is not null then
    execute 'insert into private.chat_allowed_emails (email, created_at)
      select email, created_at from public.chat_allowed_emails
      on conflict (email) do nothing';
  end if;
end;
$$;

create table if not exists public.chat_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  joined_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.chat_members(user_id),
  sender_name text not null,
  body text,
  file_path text,
  file_name text,
  file_type text,
  file_size bigint,
  downloaded_at timestamptz,
  downloaded_by uuid references public.chat_members(user_id),
  created_at timestamptz not null default now(),
  constraint chat_message_shape check (
    (
      body is not null
      and char_length(body) between 1 and 4000
      and file_path is null
      and file_name is null
      and file_type is null
      and file_size is null
      and downloaded_at is null
      and downloaded_by is null
    )
    or
    (
      body is null
      and file_name is not null
      and char_length(file_name) between 1 and 200
      and file_type is not null
      and file_size between 1 and 20971520
      and (
        (
          file_path is not null
          and split_part(file_path, '/', 1) = sender_id::text
          and downloaded_at is null
          and downloaded_by is null
        )
        or
        (
          file_path is null
          and downloaded_at is not null
          and downloaded_by is not null
        )
      )
    )
  )
);

-- Private object storage for images and documents (20 MiB maximum per file).
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'chat-files',
  'chat-files',
  false,
  20971520,
  array[
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'application/pdf', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain', 'text/csv'
  ]
)
on conflict (id) do nothing;

alter table public.chat_members enable row level security;
alter table public.chat_messages enable row level security;

revoke all on public.chat_members from anon, authenticated;
revoke all on public.chat_messages from anon, authenticated;
grant select on public.chat_members to authenticated;
grant select, insert on public.chat_messages to authenticated;

create or replace function private.is_chat_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.chat_members
    where user_id = (select auth.uid())
  );
$$;

revoke all on function private.is_chat_member() from public, anon, authenticated;
grant execute on function private.is_chat_member() to authenticated;

drop policy if exists "Members can view their own membership" on public.chat_members;
create policy "Members can view their own membership"
  on public.chat_members for select to authenticated
  using (user_id = (select auth.uid()));

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

create or replace function private.enroll_allowed_chat_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is null or not exists (
    select 1
    from private.chat_allowed_emails
    where email = lower(new.email)
  ) then
    raise exception using
      errcode = '42501',
      message = 'This email is not approved for this chat.';
  end if;
  insert into public.chat_members (user_id, email)
  values (new.id, lower(new.email))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function private.enroll_allowed_chat_user() from public, anon, authenticated;

drop trigger if exists enroll_allowed_chat_user on auth.users;
create trigger enroll_allowed_chat_user
  after insert on auth.users
  for each row execute function private.enroll_allowed_chat_user();

drop function if exists public.enroll_allowed_chat_user();

create or replace function public.mark_chat_file_downloaded(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return false;
  end if;

  update public.chat_messages as message
  set file_path = null,
      downloaded_at = now(),
      downloaded_by = (select auth.uid())
  where message.id = p_message_id
    and message.sender_id <> (select auth.uid())
    and message.file_path is not null
    and message.downloaded_at is null
    and (select private.is_chat_member())
    and not exists (
      select 1
      from storage.objects as stored_file
      where stored_file.bucket_id = 'chat-files'
        and stored_file.name = message.file_path
    );
  return found;
end;
$$;

revoke all on function public.mark_chat_file_downloaded(uuid) from public, anon;
grant execute on function public.mark_chat_file_downloaded(uuid) to authenticated;

create index if not exists chat_messages_sender_id_idx
  on public.chat_messages(sender_id);
create index if not exists chat_messages_downloaded_by_idx
  on public.chat_messages(downloaded_by);

drop policy if exists "Chat members can read chat files" on storage.objects;
create policy "Chat members can read chat files"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-files'
    and (select private.is_chat_member())
  );

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
    and not exists (
      select 1
      from public.chat_messages
      where file_path = name
    )
  );

drop function if exists public.is_chat_member();
drop table if exists public.chat_allowed_emails;

-- Realtime subscriptions are scoped to chat_messages and still obey its RLS policy.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_messages'
  ) then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end;
$$;
