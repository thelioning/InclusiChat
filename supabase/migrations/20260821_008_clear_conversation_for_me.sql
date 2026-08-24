-- Hide a conversation history for one participant without deleting shared data.
begin;

alter table public.conversation_participants
  add column if not exists cleared_at timestamptz;

create or replace function public.clear_conversation_for_me(
  target_conversation_id uuid
)
returns timestamptz
language plpgsql
security invoker
set search_path = ''
as $$
declare
  cleared_timestamp timestamptz := clock_timestamp();
begin
  update public.conversation_participants
  set cleared_at = cleared_timestamp
  where conversation_id = target_conversation_id
    and user_id = auth.uid()
    and left_at is null;

  if not found then
    raise exception 'Active conversation membership not found';
  end if;

  return cleared_timestamp;
end;
$$;

revoke all on function public.clear_conversation_for_me(uuid) from public;
grant execute on function public.clear_conversation_for_me(uuid) to authenticated;

create or replace function public.get_conversation_message_summaries()
returns table (
  conversation_id uuid,
  id uuid,
  sender_id uuid,
  content text,
  created_at timestamptz,
  metadata jsonb,
  is_deleted boolean,
  unread_count bigint,
  receipt_status text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    mine.conversation_id,
    latest.id,
    latest.sender_id,
    latest.content,
    latest.created_at,
    latest.metadata,
    latest.is_deleted,
    coalesce(unread.total, 0)::bigint as unread_count,
    case
      when latest.sender_id <> auth.uid() then null
      when exists (
        select 1 from public.message_receipts receipt
        where receipt.message_id = latest.id
          and receipt.user_id <> auth.uid()
          and receipt.status = 'read'
      ) then 'read'
      when exists (
        select 1 from public.message_receipts receipt
        where receipt.message_id = latest.id
          and receipt.user_id <> auth.uid()
          and receipt.status in ('delivered', 'read')
      ) then 'delivered'
      else 'sent'
    end as receipt_status
  from public.conversation_participants mine
  left join lateral (
    select message.*
    from public.messages message
    where message.conversation_id = mine.conversation_id
      and message.is_deleted is not true
      and (mine.cleared_at is null or message.created_at > mine.cleared_at)
      and not (
        coalesce(message.metadata -> 'deleted_for', '[]'::jsonb)
        ? auth.uid()::text
      )
    order by message.created_at desc, message.id desc
    limit 1
  ) latest on true
  left join lateral (
    select count(*) as total
    from public.messages message
    where message.conversation_id = mine.conversation_id
      and message.sender_id <> auth.uid()
      and message.is_deleted is not true
      and (mine.cleared_at is null or message.created_at > mine.cleared_at)
      and not (
        coalesce(message.metadata -> 'deleted_for', '[]'::jsonb)
        ? auth.uid()::text
      )
      and not exists (
        select 1 from public.message_receipts receipt
        where receipt.message_id = message.id
          and receipt.user_id = auth.uid()
          and receipt.status = 'read'
      )
  ) unread on true
  where mine.user_id = auth.uid() and mine.left_at is null;
$$;

revoke all on function public.get_conversation_message_summaries() from public;
grant execute on function public.get_conversation_message_summaries() to authenticated;

commit;
