create or replace function public.get_conversation_message_summaries()
returns table(
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
set search_path = ''
as $function$
  select
    mine.conversation_id,
    latest.id,
    latest.sender_id,
    latest.content,
    latest.created_at,
    latest.metadata,
    latest.is_deleted,
    coalesce(unread.total, 0)::bigint,
    case
      when latest.sender_id <> auth.uid() then null
      when exists (
        select 1
        from public.message_receipts r
        where r.message_id = latest.id
          and r.user_id <> auth.uid()
          and r.status = 'read'
      ) then 'read'
      when exists (
        select 1
        from public.message_receipts r
        where r.message_id = latest.id
          and r.user_id <> auth.uid()
          and r.status in ('delivered', 'read')
      ) then 'delivered'
      else 'sent'
    end
  from public.conversation_participants mine
  left join lateral (
    select m.*
    from public.messages m
    where m.conversation_id = mine.conversation_id
      and m.is_deleted is not true
      and (mine.cleared_at is null or m.created_at > mine.cleared_at)
      and not (coalesce(m.metadata->'deleted_for', '[]'::jsonb) ? auth.uid()::text)
      and not (
        m.type = 'system'
        and coalesce(m.metadata->>'call_signal', 'false') = 'true'
      )
    order by m.created_at desc, m.id desc
    limit 1
  ) latest on true
  left join lateral (
    select count(*) total
    from public.messages m
    where m.conversation_id = mine.conversation_id
      and m.sender_id <> auth.uid()
      and m.is_deleted is not true
      and (mine.cleared_at is null or m.created_at > mine.cleared_at)
      and not (coalesce(m.metadata->'deleted_for', '[]'::jsonb) ? auth.uid()::text)
      and not (
        m.type = 'system'
        and coalesce(m.metadata->>'call_signal', 'false') = 'true'
      )
      and not exists (
        select 1
        from public.message_receipts r
        where r.message_id = m.id
          and r.user_id = auth.uid()
          and r.status = 'read'
      )
  ) unread on true
  where mine.user_id = auth.uid()
    and mine.left_at is null;
$function$;

revoke all on function public.get_conversation_message_summaries() from public;
grant execute on function public.get_conversation_message_summaries() to authenticated;
grant execute on function public.get_conversation_message_summaries() to service_role;
