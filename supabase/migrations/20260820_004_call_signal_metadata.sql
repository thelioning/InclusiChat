-- Required by the stage-1 call signaling client.
-- Additive and safe for existing text/media messages.
begin;

alter table public.messages
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create index if not exists messages_call_signal_lookup_idx
  on public.messages ((metadata ->> 'call_id'), created_at desc)
  where type = 'system' and metadata @> '{"call_signal": true}'::jsonb;

commit;

notify pgrst, 'reload schema';
