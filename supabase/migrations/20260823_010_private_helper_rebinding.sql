-- REP-001 follow-up discovered by staging runtime validation.
-- Rebind the moved authorization helper to the private schema and keep
-- contact request timestamps consistent for direct policy-authorized updates.

begin;

create or replace function private.can_send_to_conversation(
  requested_conversation_id uuid,
  requested_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_conversation_member(
      requested_conversation_id,
      requested_user_id
    )
    and (
      not exists (
        select 1
        from public.conversations c
        where c.id = requested_conversation_id
          and c.type = 'direct'
      )
      or not exists (
        select 1
        from public.conversation_participants cp
        join public.user_blocks ub
          on (
            (ub.blocker_id = requested_user_id and ub.blocked_user_id = cp.user_id)
            or
            (ub.blocker_id = cp.user_id and ub.blocked_user_id = requested_user_id)
          )
        where cp.conversation_id = requested_conversation_id
          and cp.user_id <> requested_user_id
          and cp.left_at is null
      )
    );
$$;

revoke all on function private.can_send_to_conversation(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.can_send_to_conversation(uuid, uuid)
  to authenticated;

drop trigger if exists contact_requests_set_updated_at
  on public.contact_requests;
create trigger contact_requests_set_updated_at
before update on public.contact_requests
for each row execute function private.set_updated_at();

commit;
