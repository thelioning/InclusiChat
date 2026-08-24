-- Private media storage. Requires 20260820_001_security_baseline.sql.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-media',
  'chat-media',
  false,
  15728640,
  array['image/jpeg', 'image/png', 'image/webp', 'audio/mp4',
        'audio/mpeg', 'audio/ogg', 'audio/webm', 'audio/x-m4a']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "chat_media_select_members" on storage.objects;
drop policy if exists "chat_media_insert_members" on storage.objects;
drop policy if exists "chat_media_delete_owner" on storage.objects;

create policy "chat_media_select_members"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-media'
    and public.is_conversation_participant(
      ((storage.foldername(name))[1])::uuid,
      auth.uid()
    )
  );

create policy "chat_media_insert_members"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.is_conversation_participant(
      ((storage.foldername(name))[1])::uuid,
      auth.uid()
    )
  );

create policy "chat_media_delete_owner"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-media'
    and owner_id = auth.uid()::text
  );

commit;
