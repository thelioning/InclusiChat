-- Serialize direct-conversation creation and make it an all-or-nothing operation.
-- Depends on 20260820_001_security_baseline.sql.
begin;

create or replace function public.create_direct_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  pair_key text;
  conversation_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;
  if other_user_id is null or caller_id = other_user_id then
    raise exception 'Invalid conversation participant';
  end if;
  if not exists (select 1 from public.profiles p where p.id = other_user_id) then
    raise exception 'Profile not found';
  end if;

  pair_key := least(caller_id::text, other_user_id::text) || ':' ||
              greatest(caller_id::text, other_user_id::text);
  perform pg_advisory_xact_lock(hashtextextended(pair_key, 0));

  select c.id into conversation_id
  from public.conversations c
  where c.direct_pair_key = pair_key
  limit 1;

  if conversation_id is null then
    insert into public.conversations (type, created_by, direct_pair_key)
    values ('direct', caller_id, pair_key)
    returning id into conversation_id;
  end if;

  insert into public.conversation_participants (conversation_id, user_id, role)
  values
    (conversation_id, caller_id, 'admin'),
    (conversation_id, other_user_id, 'member')
  on conflict do nothing;

  return conversation_id;
end;
$$;

revoke all on function public.create_direct_conversation(uuid) from public;
grant execute on function public.create_direct_conversation(uuid) to authenticated;

commit;
