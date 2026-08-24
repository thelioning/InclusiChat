-- Add real private document messages while retaining the 15 MB bucket limit.
begin;

alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages add constraint messages_type_check
  check (type in ('text', 'image', 'audio', 'file', 'system'));

update storage.buckets
set allowed_mime_types = array[
  'image/jpeg', 'image/png', 'image/webp',
  'audio/mp4', 'audio/mpeg', 'audio/ogg', 'audio/webm', 'audio/x-m4a',
  'application/pdf', 'text/plain', 'text/csv', 'application/zip',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation'
]
where id = 'chat-media';

commit;
