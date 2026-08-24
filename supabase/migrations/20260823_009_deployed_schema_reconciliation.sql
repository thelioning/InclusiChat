-- REP-001: reconcile the actually deployed schema with the secure baseline.
-- Validate in InclusiChat-Staging before any production promotion.
-- This migration intentionally does NOT implement account deletion (REP-003)
-- or contact-consent enforcement in direct conversations (REP-004).

begin;

-- 1. Resolve deployed column drift used by contact RPCs.
alter table public.contact_requests
  add column if not exists updated_at timestamptz not null default now();

-- 2. Move the relocatable citext extension out of the exposed public schema.
do $$
begin
  if exists (
    select 1
    from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'citext' and n.nspname = 'public'
  ) then
    alter extension citext set schema extensions;
  end if;
end $$;

-- 3. Internal helper/trigger functions belong outside the exposed API schema.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

do $$
begin
  if to_regprocedure('public.set_updated_at()') is not null then
    alter function public.set_updated_at() set schema private;
  end if;
  if to_regprocedure('public.prepare_message_update()') is not null then
    alter function public.prepare_message_update() set schema private;
  end if;
  if to_regprocedure('public.update_conversation_activity()') is not null then
    alter function public.update_conversation_activity() set schema private;
  end if;
  if to_regprocedure('public.update_conversation_last_activity()') is not null then
    alter function public.update_conversation_last_activity() set schema private;
  end if;
  if to_regprocedure('public.create_contacts_after_acceptance()') is not null then
    alter function public.create_contacts_after_acceptance() set schema private;
  end if;
  if to_regprocedure('public.remove_contacts_after_block()') is not null then
    alter function public.remove_contacts_after_block() set schema private;
  end if;
  if to_regprocedure('public.handle_new_user()') is not null then
    alter function public.handle_new_user() set schema private;
  end if;
  if to_regprocedure('public.is_conversation_member(uuid,uuid)') is not null then
    alter function public.is_conversation_member(uuid,uuid) set schema private;
  end if;
  if to_regprocedure('public.is_conversation_admin(uuid,uuid)') is not null then
    alter function public.is_conversation_admin(uuid,uuid) set schema private;
  end if;
  if to_regprocedure('public.is_conversation_participant(uuid,uuid)') is not null then
    alter function public.is_conversation_participant(uuid,uuid) set schema private;
  end if;
  if to_regprocedure('public.can_send_to_conversation(uuid,uuid)') is not null then
    alter function public.can_send_to_conversation(uuid,uuid) set schema private;
  end if;
end $$;

-- Lock helper search paths after moving them.
alter function private.set_updated_at() set search_path = '';
alter function private.prepare_message_update() set search_path = '';
alter function private.update_conversation_activity() set search_path = '';
alter function private.update_conversation_last_activity() set search_path = '';
alter function private.create_contacts_after_acceptance() set search_path = '';
alter function private.remove_contacts_after_block() set search_path = '';
alter function private.handle_new_user() set search_path = '';
alter function private.is_conversation_member(uuid,uuid) set search_path = '';
alter function private.is_conversation_admin(uuid,uuid) set search_path = '';
alter function private.is_conversation_participant(uuid,uuid) set search_path = '';
alter function private.can_send_to_conversation(uuid,uuid) set search_path = '';

-- Trigger helpers must not be callable through the Data API.
revoke all on function private.set_updated_at() from public, anon, authenticated;
revoke all on function private.prepare_message_update() from public, anon, authenticated;
revoke all on function private.update_conversation_activity() from public, anon, authenticated;
revoke all on function private.update_conversation_last_activity() from public, anon, authenticated;
revoke all on function private.create_contacts_after_acceptance() from public, anon, authenticated;
revoke all on function private.remove_contacts_after_block() from public, anon, authenticated;
revoke all on function private.handle_new_user() from public, anon, authenticated;

-- RLS helper functions are callable by authenticated only, from a non-exposed schema.
revoke all on function private.is_conversation_member(uuid,uuid) from public, anon, authenticated;
revoke all on function private.is_conversation_admin(uuid,uuid) from public, anon, authenticated;
revoke all on function private.is_conversation_participant(uuid,uuid) from public, anon, authenticated;
revoke all on function private.can_send_to_conversation(uuid,uuid) from public, anon, authenticated;
grant execute on function private.is_conversation_member(uuid,uuid) to authenticated;
grant execute on function private.is_conversation_admin(uuid,uuid) to authenticated;
grant execute on function private.is_conversation_participant(uuid,uuid) to authenticated;
grant execute on function private.can_send_to_conversation(uuid,uuid) to authenticated;

-- 4. Public RPCs: safe search_path and explicit authentication where required.
create or replace function public.check_username_available(target_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1
    from public.profiles p
    where lower(p.username::text) = lower(
      pg_catalog.regexp_replace(target_username, '[^a-zA-Z0-9_]', '', 'g')
    )
  );
$$;

create or replace function public.search_profiles(query_text text)
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_url text,
  is_verified boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select p.id, p.display_name, p.username::text, p.avatar_url, p.is_verified
  from public.profiles p
  where p.id <> auth.uid()
    and p.is_searchable is true
    and p.is_suspended is false
    and (
      p.username::text ilike '%' || query_text || '%'
      or p.display_name ilike '%' || query_text || '%'
    )
  order by p.username
  limit 20;
end;
$$;

create or replace function public.send_contact_request(target_username text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile record;
  req_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select p.id, p.display_name, p.username::text as username
  into target_profile
  from public.profiles p
  where lower(p.username::text) = lower(trim(target_username))
    and p.is_searchable is true
    and p.is_suspended is false
  limit 1;

  if target_profile.id is null then
    return jsonb_build_object('success', false, 'message', 'Usuario no encontrado.');
  end if;

  if target_profile.id = auth.uid() then
    return jsonb_build_object('success', false, 'message', 'No puedes agregarte a ti mismo.');
  end if;

  if exists (
    select 1 from public.user_blocks ub
    where (ub.blocker_id = auth.uid() and ub.blocked_user_id = target_profile.id)
       or (ub.blocker_id = target_profile.id and ub.blocked_user_id = auth.uid())
  ) then
    return jsonb_build_object('success', false, 'message', 'No se puede enviar la solicitud.');
  end if;

  if exists (
    select 1 from public.contacts c
    where c.user_id = auth.uid() and c.contact_user_id = target_profile.id
  ) then
    return jsonb_build_object('success', false, 'message', 'Este usuario ya está en tus contactos.');
  end if;

  insert into public.contact_requests(sender_id, receiver_id, status, updated_at)
  values(auth.uid(), target_profile.id, 'pending', now())
  on conflict(sender_id, receiver_id) do update
    set status = 'pending', responded_at = null, updated_at = now()
  returning id into req_id;

  return jsonb_build_object(
    'success', true,
    'message', 'Solicitud enviada a @' || target_profile.username,
    'request_id', req_id
  );
end;
$$;

create or replace function public.accept_contact_request(request_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  req record;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cr.* into req
  from public.contact_requests cr
  where cr.id = request_id
    and cr.receiver_id = auth.uid()
    and cr.status = 'pending'
  for update;

  if req.id is null then
    return false;
  end if;

  update public.contact_requests
  set status = 'accepted', responded_at = now(), updated_at = now()
  where id = request_id;

  insert into public.contacts(user_id, contact_user_id)
  values (req.receiver_id, req.sender_id), (req.sender_id, req.receiver_id)
  on conflict do nothing;

  return true;
end;
$$;

create or replace function public.reject_contact_request(request_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.contact_requests
  set status = 'rejected', responded_at = now(), updated_at = now()
  where id = request_id
    and receiver_id = auth.uid()
    and status = 'pending';

  return found;
end;
$$;

-- Keep current direct-conversation product behavior for REP-004; only harden execution here.
create or replace function public.create_direct_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  pair_key text;
  existing_conv_id uuid;
  new_conv_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if auth.uid() = other_user_id then
    raise exception 'No puedes iniciar una conversación contigo mismo.';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = other_user_id and p.is_suspended is false
  ) then
    raise exception 'Usuario no disponible.';
  end if;

  pair_key := least(auth.uid()::text, other_user_id::text)
    || ':' || greatest(auth.uid()::text, other_user_id::text);

  perform pg_advisory_xact_lock(hashtextextended(pair_key, 0));

  select c.id into existing_conv_id
  from public.conversations c
  where c.direct_pair_key = pair_key
  limit 1;

  if existing_conv_id is null then
    select cp1.conversation_id into existing_conv_id
    from public.conversation_participants cp1
    join public.conversation_participants cp2
      on cp1.conversation_id = cp2.conversation_id
    join public.conversations c on c.id = cp1.conversation_id
    where c.type = 'direct'
      and cp1.user_id = auth.uid() and cp1.left_at is null
      and cp2.user_id = other_user_id and cp2.left_at is null
    limit 1;
  end if;

  if existing_conv_id is not null then
    insert into public.conversation_participants(conversation_id, user_id, role)
    values
      (existing_conv_id, auth.uid(), 'admin'),
      (existing_conv_id, other_user_id, 'member')
    on conflict do nothing;
    return existing_conv_id;
  end if;

  insert into public.conversations(type, created_by, direct_pair_key)
  values('direct', auth.uid(), pair_key)
  returning id into new_conv_id;

  insert into public.conversation_participants(conversation_id, user_id, role)
  values
    (new_conv_id, auth.uid(), 'admin'),
    (new_conv_id, other_user_id, 'member');

  return new_conv_id;
end;
$$;

-- Function intended by migration 001 but absent from the deployed database.
create or replace function public.delete_message_for_me(target_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_conversation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.conversation_id into target_conversation_id
  from public.messages m
  where m.id = target_message_id;

  if target_conversation_id is null
     or not private.is_conversation_participant(target_conversation_id, auth.uid()) then
    return false;
  end if;

  update public.messages
  set metadata = jsonb_set(
    coalesce(metadata, '{}'::jsonb),
    '{deleted_for}',
    coalesce(metadata->'deleted_for', '[]'::jsonb) || to_jsonb(auth.uid()::text),
    true
  )
  where id = target_message_id
    and not (coalesce(metadata->'deleted_for', '[]'::jsonb) ? auth.uid()::text);

  return true;
end;
$$;

alter function public.clear_conversation_for_me(uuid) set search_path = '';
alter function public.get_conversation_message_summaries() set search_path = '';

-- Explicit RPC grants. Username availability is intentionally callable before sign-up.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.check_username_available(text) to anon, authenticated;
grant execute on function public.search_profiles(text) to authenticated;
grant execute on function public.send_contact_request(text) to authenticated;
grant execute on function public.accept_contact_request(uuid) to authenticated;
grant execute on function public.reject_contact_request(uuid) to authenticated;
grant execute on function public.create_direct_conversation(uuid) to authenticated;
grant execute on function public.delete_message_for_me(uuid) to authenticated;
grant execute on function public.clear_conversation_for_me(uuid) to authenticated;
grant execute on function public.get_conversation_message_summaries() to authenticated;

-- 5. Replace permissive/overlapping RLS policies with an explicit authorization model.
drop policy if exists "profiles_select_policy" on public.profiles;
drop policy if exists "Authenticated users can view public profiles" on public.profiles;
drop policy if exists "Los usuarios pueden gestionar su propio perfil" on public.profiles;
drop policy if exists "Users can update their own profile" on public.profiles;
drop policy if exists "profiles_select_authorized" on public.profiles;
drop policy if exists "profiles_update_self" on public.profiles;

create policy "profiles_select_authorized"
on public.profiles for select to authenticated
using (
  id = auth.uid()
  or exists (
    select 1 from public.contacts c
    where c.user_id = auth.uid() and c.contact_user_id = profiles.id
  )
  or exists (
    select 1
    from public.conversation_participants mine
    join public.conversation_participants other
      on other.conversation_id = mine.conversation_id
    where mine.user_id = auth.uid() and mine.left_at is null
      and other.user_id = profiles.id and other.left_at is null
  )
);

create policy "profiles_update_self"
on public.profiles for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Contacts are server-created after acceptance; users only read/remove their own relation.
drop policy if exists "contacts_access_policy" on public.contacts;
drop policy if exists "Los usuarios ven solo sus propios contactos" on public.contacts;
drop policy if exists "Users can view their contacts" on public.contacts;
drop policy if exists "Users can remove their contacts" on public.contacts;
create policy "contacts_select_self" on public.contacts for select to authenticated
using (user_id = auth.uid());
create policy "contacts_delete_self" on public.contacts for delete to authenticated
using (user_id = auth.uid());

-- Contact request transition authority: sender creates/cancels; receiver accepts/rejects.
drop policy if exists "contact_requests_access_policy" on public.contact_requests;
drop policy if exists "Users can view related contact requests" on public.contact_requests;
drop policy if exists "Users can send contact requests" on public.contact_requests;
drop policy if exists "Receivers can respond to contact requests" on public.contact_requests;
drop policy if exists "Senders can cancel contact requests" on public.contact_requests;
create policy "contact_requests_select_related"
on public.contact_requests for select to authenticated
using (auth.uid() = sender_id or auth.uid() = receiver_id);
create policy "contact_requests_insert_sender"
on public.contact_requests for insert to authenticated
with check (
  auth.uid() = sender_id
  and sender_id <> receiver_id
  and not exists (
    select 1 from public.user_blocks ub
    where (ub.blocker_id = sender_id and ub.blocked_user_id = receiver_id)
       or (ub.blocker_id = receiver_id and ub.blocked_user_id = sender_id)
  )
);
create policy "contact_requests_update_receiver"
on public.contact_requests for update to authenticated
using (auth.uid() = receiver_id and status = 'pending')
with check (auth.uid() = receiver_id and status in ('accepted','rejected'));
create policy "contact_requests_delete_sender"
on public.contact_requests for delete to authenticated
using (auth.uid() = sender_id and status = 'pending');

-- Conversations and membership.
drop policy if exists "conversations_access_policy" on public.conversations;
drop policy if exists "Members can view conversations" on public.conversations;
drop policy if exists "Creators can create conversations" on public.conversations;
drop policy if exists "Admins can update conversations" on public.conversations;
create policy "conversations_select_members"
on public.conversations for select to authenticated
using (private.is_conversation_participant(id, auth.uid()));
create policy "conversations_insert_creator"
on public.conversations for insert to authenticated
with check (created_by = auth.uid());
create policy "conversations_update_admin"
on public.conversations for update to authenticated
using (private.is_conversation_admin(id, auth.uid()))
with check (private.is_conversation_admin(id, auth.uid()));

drop policy if exists "conversation_participants_access_policy" on public.conversation_participants;
drop policy if exists "Members can view participants" on public.conversation_participants;
drop policy if exists "Admins can add participants" on public.conversation_participants;
drop policy if exists "Users can update their participation" on public.conversation_participants;
create policy "participants_select_members"
on public.conversation_participants for select to authenticated
using (private.is_conversation_participant(conversation_id, auth.uid()));
create policy "participants_update_self"
on public.conversation_participants for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Messages.
drop policy if exists "messages_access_policy" on public.messages;
drop policy if exists "Members can view messages" on public.messages;
drop policy if exists "Members can send messages" on public.messages;
drop policy if exists "Senders can edit their messages" on public.messages;
create policy "messages_select_members"
on public.messages for select to authenticated
using (private.is_conversation_participant(conversation_id, auth.uid()));
create policy "messages_insert_member_sender"
on public.messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and private.can_send_to_conversation(conversation_id, auth.uid())
);
create policy "messages_update_sender"
on public.messages for update to authenticated
using (sender_id = auth.uid() and private.is_conversation_participant(conversation_id, auth.uid()))
with check (sender_id = auth.uid() and private.is_conversation_participant(conversation_id, auth.uid()));

-- Attachments and reactions use the same private membership helper.
drop policy if exists "Members can view attachments" on public.message_attachments;
drop policy if exists "Senders can add attachments" on public.message_attachments;
create policy "attachments_select_members"
on public.message_attachments for select to authenticated
using (
  exists (
    select 1 from public.messages m
    where m.id = message_id
      and private.is_conversation_participant(m.conversation_id, auth.uid())
  )
);
create policy "attachments_insert_sender"
on public.message_attachments for insert to authenticated
with check (
  exists (
    select 1 from public.messages m
    where m.id = message_id
      and m.sender_id = auth.uid()
      and private.is_conversation_participant(m.conversation_id, auth.uid())
  )
);

drop policy if exists "Members can view reactions" on public.message_reactions;
drop policy if exists "Members can add reactions" on public.message_reactions;
drop policy if exists "Users can change their reactions" on public.message_reactions;
drop policy if exists "Users can remove their reactions" on public.message_reactions;
create policy "reactions_select_members"
on public.message_reactions for select to authenticated
using (
  exists (
    select 1 from public.messages m
    where m.id = message_id
      and private.is_conversation_participant(m.conversation_id, auth.uid())
  )
);
create policy "reactions_insert_self"
on public.message_reactions for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and private.is_conversation_participant(m.conversation_id, auth.uid())
  )
);
create policy "reactions_update_self"
on public.message_reactions for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "reactions_delete_self"
on public.message_reactions for delete to authenticated
using (user_id = auth.uid());

-- Receipts: no universal SELECT and no receipts in another user's identity.
drop policy if exists "Ver recibos de mensajes en conversaciones compartidas" on public.message_receipts;
drop policy if exists "Actualizar o insertar propios recibos" on public.message_receipts;
drop policy if exists "Members can view receipts" on public.message_receipts;
drop policy if exists "Users can create their receipts" on public.message_receipts;
drop policy if exists "Users can update their receipts" on public.message_receipts;
create policy "receipts_select_conversation_members"
on public.message_receipts for select to authenticated
using (
  exists (
    select 1 from public.messages m
    where m.id = message_id
      and private.is_conversation_participant(m.conversation_id, auth.uid())
  )
);
create policy "receipts_insert_self"
on public.message_receipts for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and m.sender_id <> auth.uid()
      and private.is_conversation_participant(m.conversation_id, auth.uid())
  )
);
create policy "receipts_update_self"
on public.message_receipts for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Storage: rebind policies to the non-exposed membership helper.
drop policy if exists "chat_media_select_members" on storage.objects;
drop policy if exists "chat_media_insert_members" on storage.objects;
drop policy if exists "chat_media_delete_owner" on storage.objects;
create policy "chat_media_select_members"
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-media'
  and private.is_conversation_participant((storage.foldername(name))[1]::uuid, auth.uid())
);
create policy "chat_media_insert_members"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[2] = auth.uid()::text
  and private.is_conversation_participant((storage.foldername(name))[1]::uuid, auth.uid())
);
create policy "chat_media_delete_owner"
on storage.objects for delete to authenticated
using (bucket_id = 'chat-media' and owner_id = auth.uid()::text);

-- 6. Replace broad Data API grants with normal DML access subject to RLS.
revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;

-- 7. Reconcile indexes that existed with the same names but different definitions.
drop index if exists public.contact_requests_receiver_status_idx;
create index contact_requests_receiver_status_idx
  on public.contact_requests(receiver_id, status, created_at desc);
create index if not exists conversation_participants_user_active_idx
  on public.conversation_participants(user_id, conversation_id)
  where left_at is null;
create index if not exists message_receipts_user_status_idx
  on public.message_receipts(user_id, status, message_id);

-- Ensure RLS remains enabled for every exposed application table.
alter table public.profiles enable row level security;
alter table public.profile_identity enable row level security;
alter table public.privacy_settings enable row level security;
alter table public.user_blocks enable row level security;
alter table public.contacts enable row level security;
alter table public.contact_requests enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;
alter table public.message_reactions enable row level security;
alter table public.message_receipts enable row level security;
alter table public.device_push_tokens enable row level security;

commit;
