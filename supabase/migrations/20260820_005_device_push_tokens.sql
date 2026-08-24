-- Store FCM registration tokens without exposing them to other app users.
begin;

create table if not exists public.device_push_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens (user_id, updated_at desc);

alter table public.device_push_tokens enable row level security;

drop policy if exists "push_tokens_select_self" on public.device_push_tokens;
drop policy if exists "push_tokens_insert_self" on public.device_push_tokens;
drop policy if exists "push_tokens_update_self" on public.device_push_tokens;
drop policy if exists "push_tokens_delete_self" on public.device_push_tokens;

create policy "push_tokens_select_self"
  on public.device_push_tokens for select to authenticated
  using (user_id = auth.uid());
create policy "push_tokens_insert_self"
  on public.device_push_tokens for insert to authenticated
  with check (user_id = auth.uid());
create policy "push_tokens_update_self"
  on public.device_push_tokens for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "push_tokens_delete_self"
  on public.device_push_tokens for delete to authenticated
  using (user_id = auth.uid());

commit;

notify pgrst, 'reload schema';
