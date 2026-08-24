-- REP-001 staging-only structural baseline captured from the deployed project.
-- DO NOT APPLY TO PRODUCTION.
-- No user data is included. This intentionally reproduces current schema drift
-- and permissive policies so the reconciliation migration can be verified.

begin;

create extension if not exists citext with schema public;

do $$ begin create type public.contact_request_status as enum ('pending','accepted','rejected'); exception when duplicate_object then null; end $$;
do $$ begin create type public.conversation_type as enum ('direct','group','community'); exception when duplicate_object then null; end $$;
do $$ begin create type public.message_type as enum ('text','image','video','audio','file','location','system'); exception when duplicate_object then null; end $$;
do $$ begin create type public.participant_role as enum ('owner','admin','member'); exception when duplicate_object then null; end $$;
do $$ begin create type public.profile_visibility as enum ('private','contacts','everyone'); exception when duplicate_object then null; end $$;
do $$ begin create type public.receipt_status as enum ('delivered','read'); exception when duplicate_object then null; end $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username public.citext unique,
  display_name text,
  avatar_url text,
  bio text,
  is_verified boolean not null default false,
  is_suspended boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  pronouns text,
  is_searchable boolean default true,
  constraint username_length check (username is null or (char_length(username::text) between 3 and 30)),
  constraint display_name_length check (display_name is null or (char_length(display_name) between 1 and 80)),
  constraint bio_length check (bio is null or char_length(bio) <= 300)
);

create table public.profile_identity (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  pronouns text,
  gender_identity text,
  sexual_orientation text,
  visibility public.profile_visibility not null default 'contacts',
  updated_at timestamptz not null default now(),
  constraint pronouns_length check (pronouns is null or char_length(pronouns) <= 50),
  constraint gender_identity_length check (gender_identity is null or char_length(gender_identity) <= 80),
  constraint orientation_length check (sexual_orientation is null or char_length(sexual_orientation) <= 80)
);

create table public.privacy_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  profile_visibility public.profile_visibility not null default 'contacts',
  show_online_status public.profile_visibility not null default 'contacts',
  show_last_seen public.profile_visibility not null default 'contacts',
  allow_contact_requests boolean not null default true,
  allow_group_invites boolean not null default true,
  read_receipts_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_user_id),
  constraint different_block_users check (blocker_id <> blocked_user_id)
);

create table public.contacts (
  user_id uuid not null references public.profiles(id) on delete cascade,
  contact_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, contact_user_id),
  constraint different_contact_users check (user_id <> contact_user_id)
);

create table public.contact_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status public.contact_request_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint different_request_users check (sender_id <> receiver_id),
  constraint unique_contact_request unique (sender_id, receiver_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  type public.conversation_type not null,
  title text,
  avatar_url text,
  created_by uuid not null references public.profiles(id),
  direct_pair_key text unique,
  last_activity_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversation_title_length check (title is null or (char_length(title) between 1 and 100))
);

create table public.conversation_participants (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.participant_role not null default 'member',
  is_muted boolean not null default false,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  cleared_at timestamptz,
  primary key (conversation_id, user_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id),
  type public.message_type not null default 'text',
  content text,
  reply_to_message_id uuid references public.messages(id) on delete set null,
  is_deleted boolean not null default false,
  edited_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint message_content_length check (content is null or char_length(content) <= 10000),
  constraint messages_type_check check (type = any (array['text'::public.message_type,'image'::public.message_type,'audio'::public.message_type,'file'::public.message_type,'system'::public.message_type]))
);

create table public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  storage_path text not null,
  file_name text,
  mime_type text,
  file_size_bytes bigint,
  width integer,
  height integer,
  duration_seconds integer,
  created_at timestamptz not null default now(),
  constraint valid_dimensions check ((width is null or width > 0) and (height is null or height > 0)),
  constraint valid_duration check (duration_seconds is null or duration_seconds >= 0),
  constraint valid_file_size check (file_size_bytes is null or file_size_bytes >= 0)
);

create table public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id),
  constraint emoji_length check (char_length(emoji) between 1 and 20)
);

create table public.message_receipts (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status public.receipt_status not null,
  status_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create table public.device_push_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null,
  updated_at timestamptz not null default now(),
  constraint device_push_tokens_platform_check check (platform = any (array['android'::text,'ios'::text,'web'::text]))
);

create index contacts_contact_user_idx on public.contacts(contact_user_id);
create index contact_requests_receiver_status_idx on public.contact_requests(receiver_id,status);
create index conversation_participants_user_idx on public.conversation_participants(user_id,left_at);
create index conversations_last_activity_idx on public.conversations(last_activity_at desc);
create index device_push_tokens_user_idx on public.device_push_tokens(user_id,updated_at desc);
create index message_attachments_message_idx on public.message_attachments(message_id);
create index message_receipts_user_idx on public.message_receipts(user_id,status);
create index messages_conversation_created_idx on public.messages(conversation_id,created_at desc);
create index messages_expires_idx on public.messages(expires_at) where expires_at is not null;
create index messages_sender_idx on public.messages(sender_id);
create index messages_call_signal_lookup_idx on public.messages ((metadata->>'call_id'),created_at desc)
  where type='system'::public.message_type and metadata @> '{"call_signal": true}'::jsonb;
create index user_blocks_blocked_user_idx on public.user_blocks(blocked_user_id);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;

create or replace function public.is_conversation_member(requested_conversation_id uuid, requested_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.conversation_participants where conversation_id=requested_conversation_id and user_id=requested_user_id and left_at is null);
$$;

create or replace function public.is_conversation_admin(requested_conversation_id uuid, requested_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.conversation_participants where conversation_id=requested_conversation_id and user_id=requested_user_id and role in ('owner','admin') and left_at is null);
$$;

create or replace function public.can_send_to_conversation(requested_conversation_id uuid, requested_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select public.is_conversation_member(requested_conversation_id,requested_user_id)
  and (
    not exists(select 1 from public.conversations where id=requested_conversation_id and type='direct')
    or not exists(
      select 1 from public.conversation_participants cp
      join public.user_blocks ub on ((ub.blocker_id=requested_user_id and ub.blocked_user_id=cp.user_id) or (ub.blocker_id=cp.user_id and ub.blocked_user_id=requested_user_id))
      where cp.conversation_id=requested_conversation_id and cp.user_id<>requested_user_id and cp.left_at is null
    )
  );
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
declare raw_username text; final_username text; raw_display_name text;
begin
 raw_username:=coalesce(new.raw_user_meta_data->>'username',split_part(new.email,'@',1));
 raw_display_name:=coalesce(new.raw_user_meta_data->>'display_name',raw_username);
 final_username:=lower(regexp_replace(raw_username,'[^a-zA-Z0-9_]','','g'));
 if length(final_username)<3 then final_username:='user_'||substr(new.id::text,1,8); end if;
 if exists(select 1 from public.profiles where username=final_username) then raise exception 'El alias de usuario ya está en uso.'; end if;
 insert into public.profiles(id,display_name,username,avatar_url)
 values(new.id,raw_display_name,final_username,new.raw_user_meta_data->>'avatar_url')
 on conflict(id) do update set display_name=excluded.display_name,username=coalesce(public.profiles.username,excluded.username);
 return new;
end $$;

create or replace function public.check_username_available(target_username text)
returns boolean language sql security definer set search_path=public as $$
 select not exists(select 1 from public.profiles where lower(username)=lower(regexp_replace(target_username,'[^a-zA-Z0-9_]','','g')));
$$;

create or replace function public.send_contact_request(target_username text)
returns jsonb language plpgsql security definer as $$
declare target_profile record; req_id uuid;
begin
 select id,display_name,username into target_profile from public.profiles where lower(username)=lower(trim(target_username)) limit 1;
 if target_profile.id is null then return jsonb_build_object('success',false,'message','Usuario no encontrado.'); end if;
 if target_profile.id=auth.uid() then return jsonb_build_object('success',false,'message','No puedes agregarte a ti mismo.'); end if;
 if exists(select 1 from public.contacts where user_id=auth.uid() and contact_user_id=target_profile.id) then return jsonb_build_object('success',false,'message','Este usuario ya está en tus contactos.'); end if;
 insert into public.contact_requests(sender_id,receiver_id,status) values(auth.uid(),target_profile.id,'pending')
 on conflict(sender_id,receiver_id) do update set status='pending',updated_at=now()
 returning id into req_id;
 return jsonb_build_object('success',true,'message','Solicitud enviada a @'||target_profile.username,'request_id',req_id);
end $$;

create or replace function public.accept_contact_request(request_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare req record;
begin
 select * into req from public.contact_requests where id=request_id and receiver_id=auth.uid() and status='pending';
 if req.id is null then return false; end if;
 update public.contact_requests set status='accepted',updated_at=now() where id=request_id;
 insert into public.contacts(user_id,contact_user_id) values(req.receiver_id,req.sender_id),(req.sender_id,req.receiver_id) on conflict do nothing;
 return true;
end $$;

create or replace function public.reject_contact_request(request_id uuid)
returns boolean language plpgsql security definer as $$
begin
 update public.contact_requests set status='rejected',updated_at=now() where id=request_id and receiver_id=auth.uid() and status='pending';
 return found;
end $$;

create or replace function public.create_contacts_after_acceptance()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status='accepted' and old.status='pending' then
   insert into public.contacts(user_id,contact_user_id) values(new.sender_id,new.receiver_id),(new.receiver_id,new.sender_id) on conflict do nothing;
   new.responded_at=now();
 elsif new.status='rejected' and old.status='pending' then new.responded_at=now(); end if;
 return new;
end $$;

create or replace function public.remove_contacts_after_block()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 delete from public.contacts where (user_id=new.blocker_id and contact_user_id=new.blocked_user_id) or (user_id=new.blocked_user_id and contact_user_id=new.blocker_id);
 delete from public.contact_requests where (sender_id=new.blocker_id and receiver_id=new.blocked_user_id) or (sender_id=new.blocked_user_id and receiver_id=new.blocker_id);
 return new;
end $$;

create or replace function public.create_direct_conversation(other_user_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare pair_key text; existing_conv_id uuid; new_conv_id uuid;
begin
 if auth.uid()=other_user_id then raise exception 'No puedes iniciar una conversación contigo mismo.'; end if;
 pair_key:=least(auth.uid()::text,other_user_id::text)||':'||greatest(auth.uid()::text,other_user_id::text);
 select id into existing_conv_id from public.conversations where direct_pair_key=pair_key limit 1;
 if existing_conv_id is null then
   select cp1.conversation_id into existing_conv_id
   from public.conversation_participants cp1 join public.conversation_participants cp2 on cp1.conversation_id=cp2.conversation_id
   join public.conversations c on c.id=cp1.conversation_id
   where c.type='direct' and cp1.user_id=auth.uid() and cp1.left_at is null and cp2.user_id=other_user_id and cp2.left_at is null limit 1;
 end if;
 if existing_conv_id is not null then
   insert into public.conversation_participants(conversation_id,user_id,role) values(existing_conv_id,auth.uid(),'admin'),(existing_conv_id,other_user_id,'member') on conflict do nothing;
   return existing_conv_id;
 end if;
 insert into public.conversations(type,created_by,direct_pair_key) values('direct',auth.uid(),pair_key) returning id into new_conv_id;
 insert into public.conversation_participants(conversation_id,user_id,role) values(new_conv_id,auth.uid(),'admin'),(new_conv_id,other_user_id,'member') on conflict do nothing;
 return new_conv_id;
end $$;

create or replace function public.prepare_message_update()
returns trigger language plpgsql as $$
begin
 if new.id<>old.id or new.conversation_id<>old.conversation_id or new.sender_id<>old.sender_id or new.type<>old.type or new.created_at<>old.created_at then raise exception 'Immutable message fields cannot be changed'; end if;
 if new.content is distinct from old.content then new.edited_at=now(); end if;
 if new.is_deleted and not old.is_deleted then new.content=null; new.edited_at=now(); end if;
 return new;
end $$;

create or replace function public.update_conversation_activity()
returns trigger language plpgsql security definer set search_path=public as $$ begin update public.conversations set last_activity_at=new.created_at where id=new.conversation_id; return new; end $$;

create or replace function public.update_conversation_last_activity()
returns trigger language plpgsql security definer as $$ begin update public.conversations set last_activity_at=new.created_at where id=new.conversation_id; return new; end $$;

create or replace function public.is_conversation_participant(conv_id uuid,u_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.conversation_participants where conversation_id=conv_id and user_id=u_id and left_at is null);
$$;

create or replace function public.get_conversation_message_summaries()
returns table(conversation_id uuid,id uuid,sender_id uuid,content text,created_at timestamptz,metadata jsonb,is_deleted boolean,unread_count bigint,receipt_status text)
language sql stable set search_path='' as $$
 select mine.conversation_id,latest.id,latest.sender_id,latest.content,latest.created_at,latest.metadata,latest.is_deleted,
        coalesce(unread.total,0)::bigint,
        case when latest.sender_id<>auth.uid() then null
             when exists(select 1 from public.message_receipts r where r.message_id=latest.id and r.user_id<>auth.uid() and r.status='read') then 'read'
             when exists(select 1 from public.message_receipts r where r.message_id=latest.id and r.user_id<>auth.uid() and r.status in ('delivered','read')) then 'delivered'
             else 'sent' end
 from public.conversation_participants mine
 left join lateral (
   select m.* from public.messages m where m.conversation_id=mine.conversation_id and m.is_deleted is not true
     and (mine.cleared_at is null or m.created_at>mine.cleared_at)
     and not (coalesce(m.metadata->'deleted_for','[]'::jsonb) ? auth.uid()::text)
   order by m.created_at desc,m.id desc limit 1
 ) latest on true
 left join lateral (
   select count(*) total from public.messages m where m.conversation_id=mine.conversation_id and m.sender_id<>auth.uid() and m.is_deleted is not true
     and (mine.cleared_at is null or m.created_at>mine.cleared_at)
     and not (coalesce(m.metadata->'deleted_for','[]'::jsonb) ? auth.uid()::text)
     and not exists(select 1 from public.message_receipts r where r.message_id=m.id and r.user_id=auth.uid() and r.status='read')
 ) unread on true
 where mine.user_id=auth.uid() and mine.left_at is null;
$$;

create or replace function public.clear_conversation_for_me(target_conversation_id uuid)
returns timestamptz language plpgsql set search_path='' as $$
declare cleared_timestamp timestamptz:=clock_timestamp();
begin
 update public.conversation_participants set cleared_at=cleared_timestamp
 where conversation_id=target_conversation_id and user_id=auth.uid() and left_at is null;
 if not found then raise exception 'Active conversation membership not found'; end if;
 return cleared_timestamp;
end $$;

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
create trigger contact_request_status_changed before update of status on public.contact_requests for each row execute function public.create_contacts_after_acceptance();
create trigger conversations_set_updated_at before update on public.conversations for each row execute function public.set_updated_at();
create trigger message_updates_conversation after insert on public.messages for each row execute function public.update_conversation_activity();
create trigger messages_prepare_update before update on public.messages for each row execute function public.prepare_message_update();
create trigger on_message_created after insert on public.messages for each row execute function public.update_conversation_last_activity();
create trigger privacy_settings_set_updated_at before update on public.privacy_settings for each row execute function public.set_updated_at();
create trigger profile_identity_set_updated_at before update on public.profile_identity for each row execute function public.set_updated_at();
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger user_block_created after insert on public.user_blocks for each row execute function public.remove_contacts_after_block();

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

create policy "profiles_select_policy" on public.profiles for select to anon,authenticated using (true);
create policy "Authenticated users can view public profiles" on public.profiles for select to authenticated using (not is_suspended);
create policy "Los usuarios pueden gestionar su propio perfil" on public.profiles for all to authenticated using (auth.uid()=id) with check (auth.uid()=id);
create policy "Users can update their own profile" on public.profiles for update to authenticated using (auth.uid()=id) with check (auth.uid()=id);

create policy "Users can view their own identity" on public.profile_identity for select to authenticated using (auth.uid()=user_id);
create policy "Users can update their own identity" on public.profile_identity for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "Users can view their own privacy settings" on public.privacy_settings for select to authenticated using (auth.uid()=user_id);
create policy "Users can update their own privacy settings" on public.privacy_settings for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "Users can view their blocks" on public.user_blocks for select to authenticated using (auth.uid()=blocker_id);
create policy "Users can block accounts" on public.user_blocks for insert to authenticated with check (auth.uid()=blocker_id and blocker_id<>blocked_user_id);
create policy "Users can unblock accounts" on public.user_blocks for delete to authenticated using (auth.uid()=blocker_id);

create policy "contacts_access_policy" on public.contacts for all to authenticated using (true) with check (true);
create policy "Los usuarios ven solo sus propios contactos" on public.contacts for select to authenticated using (auth.uid()=user_id);
create policy "Users can view their contacts" on public.contacts for select to authenticated using (auth.uid()=user_id);
create policy "Users can remove their contacts" on public.contacts for delete to authenticated using (auth.uid()=user_id);

create policy "contact_requests_access_policy" on public.contact_requests for all to authenticated using (true) with check (true);
create policy "Users can view related contact requests" on public.contact_requests for select to authenticated using (auth.uid()=sender_id or auth.uid()=receiver_id);
create policy "Users can send contact requests" on public.contact_requests for insert to authenticated with check (
 auth.uid()=sender_id and sender_id<>receiver_id and not exists(select 1 from public.user_blocks where (blocker_id=sender_id and blocked_user_id=receiver_id) or (blocker_id=receiver_id and blocked_user_id=sender_id))
);
create policy "Receivers can respond to contact requests" on public.contact_requests for update to authenticated
 using (auth.uid()=receiver_id and status='pending') with check (auth.uid()=receiver_id and status in ('accepted','rejected'));
create policy "Senders can cancel contact requests" on public.contact_requests for delete to authenticated using (auth.uid()=sender_id and status='pending');

create policy "conversations_access_policy" on public.conversations for all to authenticated using (true) with check (true);
create policy "Members can view conversations" on public.conversations for select to authenticated using (public.is_conversation_member(id));
create policy "Creators can create conversations" on public.conversations for insert to authenticated with check (auth.uid()=created_by);
create policy "Admins can update conversations" on public.conversations for update to authenticated using (public.is_conversation_admin(id)) with check (public.is_conversation_admin(id));

create policy "conversation_participants_access_policy" on public.conversation_participants for all to authenticated using (true) with check (true);
create policy "Members can view participants" on public.conversation_participants for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "Admins can add participants" on public.conversation_participants for insert to authenticated with check (
 public.is_conversation_admin(conversation_id) or exists(select 1 from public.conversations where id=conversation_id and created_by=auth.uid())
);
create policy "Users can update their participation" on public.conversation_participants for update to authenticated
 using (auth.uid()=user_id or public.is_conversation_admin(conversation_id))
 with check (auth.uid()=user_id or public.is_conversation_admin(conversation_id));

create policy "messages_access_policy" on public.messages for all to authenticated using (true) with check (true);
create policy "Members can view messages" on public.messages for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "Members can send messages" on public.messages for insert to authenticated with check (auth.uid()=sender_id and public.can_send_to_conversation(conversation_id));
create policy "Senders can edit their messages" on public.messages for update to authenticated
 using (auth.uid()=sender_id and public.is_conversation_member(conversation_id))
 with check (auth.uid()=sender_id and public.is_conversation_member(conversation_id));

create policy "Members can view attachments" on public.message_attachments for select to authenticated using (
 exists(select 1 from public.messages where id=message_id and public.is_conversation_member(conversation_id))
);
create policy "Senders can add attachments" on public.message_attachments for insert to authenticated with check (
 exists(select 1 from public.messages where id=message_id and sender_id=auth.uid())
);

create policy "Members can view reactions" on public.message_reactions for select to authenticated using (
 exists(select 1 from public.messages where id=message_id and public.is_conversation_member(conversation_id))
);
create policy "Members can add reactions" on public.message_reactions for insert to authenticated with check (
 auth.uid()=user_id and exists(select 1 from public.messages where id=message_id and public.is_conversation_member(conversation_id))
);
create policy "Users can change their reactions" on public.message_reactions for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "Users can remove their reactions" on public.message_reactions for delete to authenticated using (auth.uid()=user_id);

create policy "Ver recibos de mensajes en conversaciones compartidas" on public.message_receipts for select to authenticated using (true);
create policy "Actualizar o insertar propios recibos" on public.message_receipts for all to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "Members can view receipts" on public.message_receipts for select to authenticated using (
 exists(select 1 from public.messages where id=message_id and public.is_conversation_member(conversation_id))
);
create policy "Users can create their receipts" on public.message_receipts for insert to authenticated with check (
 auth.uid()=user_id and exists(select 1 from public.messages where id=message_id and public.is_conversation_member(conversation_id))
);
create policy "Users can update their receipts" on public.message_receipts for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);

create policy "push_tokens_select_self" on public.device_push_tokens for select to authenticated using (user_id=auth.uid());
create policy "push_tokens_insert_self" on public.device_push_tokens for insert to authenticated with check (user_id=auth.uid());
create policy "push_tokens_update_self" on public.device_push_tokens for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "push_tokens_delete_self" on public.device_push_tokens for delete to authenticated using (user_id=auth.uid());

grant all on all tables in schema public to anon,authenticated,service_role;
grant usage on schema public to anon,authenticated,service_role;
grant execute on all functions in schema public to anon,authenticated,service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('chat-media','chat-media',false,15728640,array[
 'image/jpeg','image/png','image/webp','image/gif','audio/mpeg','audio/mp4','audio/aac','audio/ogg','audio/wav',
 'application/pdf','text/plain','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document'
]) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create policy "chat_media_select_members" on storage.objects for select to authenticated using (
 bucket_id='chat-media' and public.is_conversation_participant((storage.foldername(name))[1]::uuid,auth.uid())
);
create policy "chat_media_insert_members" on storage.objects for insert to authenticated with check (
 bucket_id='chat-media' and (storage.foldername(name))[2]=auth.uid()::text and public.is_conversation_participant((storage.foldername(name))[1]::uuid,auth.uid())
);
create policy "chat_media_delete_owner" on storage.objects for delete to authenticated using (
 bucket_id='chat-media' and owner_id=auth.uid()::text
);

commit;
