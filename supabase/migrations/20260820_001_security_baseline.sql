-- InclusiChat security baseline. Apply first outside production.
-- Rollback: restore the preceding policies/functions from a verified snapshot.
begin;

do $$
begin
  if exists (
    select direct_pair_key from public.conversations
    where direct_pair_key is not null
    group by direct_pair_key having count(*) > 1
  ) then
    raise exception 'Duplicate direct_pair_key values must be reviewed before migration';
  end if;
end $$;

create unique index if not exists conversations_direct_pair_key_uidx
  on public.conversations (direct_pair_key) where direct_pair_key is not null;
create index if not exists conversation_participants_user_active_idx
  on public.conversation_participants (user_id, conversation_id) where left_at is null;
create index if not exists messages_conversation_created_idx
  on public.messages (conversation_id, created_at desc);
create index if not exists message_receipts_user_status_idx
  on public.message_receipts (user_id, status, message_id);
create index if not exists contact_requests_receiver_status_idx
  on public.contact_requests (receiver_id, status, created_at desc);

create or replace function public.is_conversation_participant(
  target_conversation_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null and exists (
    select 1 from public.conversation_participants cp
    where cp.conversation_id = target_conversation_id
      and cp.user_id = target_user_id and cp.left_at is null
  );
$$;
revoke all on function public.is_conversation_participant(uuid, uuid) from public;
grant execute on function public.is_conversation_participant(uuid, uuid) to authenticated;

drop policy if exists "profiles_select_policy" on public.profiles;
drop policy if exists "Perfiles visibles para usuarios autenticados" on public.profiles;
create policy "profiles_select_authorized"
  on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1 from public.contacts c
      where c.user_id = auth.uid() and c.contact_user_id = profiles.id
    )
    or exists (
      select 1 from public.conversation_participants mine
      join public.conversation_participants other
        on other.conversation_id = mine.conversation_id
      where mine.user_id = auth.uid() and mine.left_at is null
        and other.user_id = profiles.id and other.left_at is null
    )
  );

drop policy if exists "conversation_participants_access_policy" on public.conversation_participants;
drop policy if exists "Participantes pueden ver datos de miembros" on public.conversation_participants;
drop policy if exists "Permitir insercion de participantes" on public.conversation_participants;
drop policy if exists "Permitir actualizar propios datos de participante" on public.conversation_participants;
create policy "participants_select_members"
  on public.conversation_participants for select to authenticated
  using (public.is_conversation_participant(conversation_id));
create policy "participants_update_self"
  on public.conversation_participants for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Participantes pueden ver sus conversaciones" on public.conversations;
drop policy if exists "conversations_access_policy" on public.conversations;
create policy "conversations_select_members"
  on public.conversations for select to authenticated
  using (public.is_conversation_participant(id));

drop policy if exists "messages_access_policy" on public.messages;
drop policy if exists "Participantes pueden leer mensajes" on public.messages;
drop policy if exists "Participantes pueden enviar mensajes" on public.messages;
create policy "messages_select_members"
  on public.messages for select to authenticated
  using (public.is_conversation_participant(conversation_id));
create policy "messages_insert_member_sender"
  on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_conversation_participant(conversation_id));
create policy "messages_update_sender"
  on public.messages for update to authenticated
  using (sender_id = auth.uid() and public.is_conversation_participant(conversation_id))
  with check (sender_id = auth.uid() and public.is_conversation_participant(conversation_id));

drop policy if exists "message_receipts_access_policy" on public.message_receipts;
drop policy if exists "Ver recibos de mensajes en conversaciones compartidas" on public.message_receipts;
drop policy if exists "Actualizar o insertar propios recibos" on public.message_receipts;
create policy "receipts_select_conversation_members"
  on public.message_receipts for select to authenticated
  using (exists (
    select 1 from public.messages m
    where m.id = message_id and public.is_conversation_participant(m.conversation_id)
  ));
create policy "receipts_insert_self"
  on public.message_receipts for insert to authenticated
  with check (
    user_id = auth.uid() and exists (
      select 1 from public.messages m
      where m.id = message_id and m.sender_id <> auth.uid()
        and public.is_conversation_participant(m.conversation_id)
    )
  );
create policy "receipts_update_self"
  on public.message_receipts for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.delete_message_for_me(target_message_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare target_conversation_id uuid;
begin
  select m.conversation_id into target_conversation_id
  from public.messages m where m.id = target_message_id;
  if target_conversation_id is null
     or not public.is_conversation_participant(target_conversation_id, auth.uid()) then
    return false;
  end if;
  update public.messages
  set metadata = jsonb_set(
    coalesce(metadata, '{}'::jsonb), '{deleted_for}',
    coalesce(metadata->'deleted_for', '[]'::jsonb) || to_jsonb(auth.uid()::text), true
  )
  where id = target_message_id
    and not (coalesce(metadata->'deleted_for', '[]'::jsonb) ? auth.uid()::text);
  return true;
end;
$$;
revoke all on function public.delete_message_for_me(uuid) from public;
grant execute on function public.delete_message_for_me(uuid) to authenticated;

alter function public.handle_new_user() set search_path = '';
alter function public.update_conversation_last_activity() set search_path = '';
alter function public.create_direct_conversation(uuid) set search_path = '';
alter function public.search_profiles(text) set search_path = '';
alter function public.send_contact_request(text) set search_path = '';
alter function public.accept_contact_request(uuid) set search_path = '';
alter function public.reject_contact_request(uuid) set search_path = '';
alter function public.delete_user_account() set search_path = '';

commit;
