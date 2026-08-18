-- ==============================================================================
-- INCLUSICHAT: ESQUEMA DE BASE DE DATOS Y SEGURIDAD SUPABASE (POSTGRESQL)
-- Modelo de coste cero, máxima privacidad, RLS y funciones RPC seguras.
-- ==============================================================================

-- 1. EXTENSIONES
create extension if not exists "uuid-ossp";

-- 2. TABLA DE PERFILES PÚBLICOS / IDENTIDAD
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  username text unique not null,
  avatar_url text,
  bio text,
  pronouns text,
  is_verified boolean default false,
  is_searchable boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Asegurar columnas si la tabla ya existía previamente
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists pronouns text;
alter table public.profiles add column if not exists is_verified boolean default false;
alter table public.profiles add column if not exists is_searchable boolean default true;
alter table public.profiles add column if not exists created_at timestamptz default now();
alter table public.profiles add column if not exists updated_at timestamptz default now();

-- Habilitar RLS en profiles
alter table public.profiles enable row level security;

drop policy if exists "Perfiles visibles para usuarios autenticados" on public.profiles;
create policy "Perfiles visibles para usuarios autenticados"
  on public.profiles for select
  to authenticated
  using (true);

drop policy if exists "Los usuarios pueden actualizar su propio perfil" on public.profiles;
drop policy if exists "Los usuarios pueden insertar su propio perfil" on public.profiles;
drop policy if exists "Los usuarios pueden gestionar su propio perfil" on public.profiles;

create policy "Los usuarios pueden gestionar su propio perfil"
  on public.profiles for all
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Crear perfiles para usuarios existentes en auth.users si no los tienen
insert into public.profiles (id, display_name, username)
select 
  u.id, 
  coalesce(u.raw_user_meta_data->>'display_name', split_part(u.email, '@', 1), 'Usuario'),
  coalesce(u.raw_user_meta_data->>'username', 'user_' || substr(u.id::text, 1, 8))
from auth.users u
on conflict (id) do nothing;

-- Trigger para crear perfil automáticamente al registrarse en Auth
create or replace function public.handle_new_user()
returns trigger as $$
declare
  raw_username text;
  final_username text;
  raw_display_name text;
begin
  raw_username := coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1));
  raw_display_name := coalesce(new.raw_user_meta_data->>'display_name', raw_username);
  
  -- Sanitizar username
  final_username := lower(regexp_replace(raw_username, '[^a-zA-Z0-9_]', '', 'g'));
  if length(final_username) < 3 then
    final_username := 'user_' || substr(new.id::text, 1, 8);
  end if;

  -- Si el username ya existe, añadir un sufijo aleatorio
  if exists (select 1 from public.profiles where username = final_username) then
    final_username := final_username || '_' || substr(new.id::text, 1, 4);
  end if;

  insert into public.profiles (id, display_name, username, avatar_url)
  values (
    new.id,
    raw_display_name,
    final_username,
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do update
  set
    display_name = excluded.display_name,
    username = coalesce(public.profiles.username, excluded.username);

  return new;
end;
$$ language plpgsql security definer;

-- Asociar trigger a auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3. TABLA DE CONTACTOS Y CÍRCULOS
create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  contact_user_id uuid not null references public.profiles(id) on delete cascade,
  nickname text,
  circle_category text default 'general' check (circle_category in ('general', 'trusted', 'collective')),
  is_favorite boolean default false,
  created_at timestamptz default now(),
  unique (user_id, contact_user_id)
);

alter table public.contacts enable row level security;

drop policy if exists "Los usuarios ven solo sus propios contactos" on public.contacts;
create policy "Los usuarios ven solo sus propios contactos"
  on public.contacts for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Los usuarios pueden agregar o eliminar sus contactos" on public.contacts;
create policy "Los usuarios pueden agregar o eliminar sus contactos"
  on public.contacts for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 4. TABLA DE SOLICITUDES DE CONTACTO
create table if not exists public.contact_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (sender_id, receiver_id)
);

alter table public.contact_requests enable row level security;

drop policy if exists "Ver solicitudes enviadas o recibidas" on public.contact_requests;
create policy "Ver solicitudes enviadas o recibidas"
  on public.contact_requests for select
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id);

drop policy if exists "Enviar solicitudes de contacto" on public.contact_requests;
create policy "Enviar solicitudes de contacto"
  on public.contact_requests for insert
  to authenticated
  with check (auth.uid() = sender_id);

drop policy if exists "Actualizar solicitudes recibidas o enviadas" on public.contact_requests;
create policy "Actualizar solicitudes recibidas o enviadas"
  on public.contact_requests for update
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- 5. CONVERSACIONES Y PARTICIPANTES
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  type text default 'direct' check (type in ('direct', 'circle', 'collective')),
  title text,
  avatar_url text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  last_activity_at timestamptz default now()
);

alter table public.conversations enable row level security;

create table if not exists public.conversation_participants (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text default 'member' check (role in ('admin', 'member')),
  joined_at timestamptz default now(),
  left_at timestamptz,
  unique (conversation_id, user_id)
);

alter table public.conversation_participants enable row level security;

-- Helper security definer para comprobar pertenencia a conversación sin causar recursión RLS (Error 42P17)
create or replace function public.is_conversation_participant(conv_id uuid, u_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.conversation_participants
    where conversation_id = conv_id
      and user_id = u_id
      and left_at is null
  );
$$;

drop policy if exists "Participantes pueden ver sus conversaciones" on public.conversations;
create policy "Participantes pueden ver sus conversaciones"
  on public.conversations for select
  to authenticated
  using (public.is_conversation_participant(id, auth.uid()));

drop policy if exists "Participantes pueden ver datos de miembros" on public.conversation_participants;
create policy "Participantes pueden ver datos de miembros"
  on public.conversation_participants for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.is_conversation_participant(conversation_id, auth.uid())
  );

-- 6. MENSAJES Y RECIBOS DE ENTREGA/LECTURA
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  type text default 'text' check (type in ('text', 'image', 'audio', 'system')),
  content text,
  metadata jsonb default '{}'::jsonb,
  is_deleted boolean default false,
  created_at timestamptz default now()
);

alter table public.messages enable row level security;

drop policy if exists "Participantes pueden leer mensajes" on public.messages;
create policy "Participantes pueden leer mensajes"
  on public.messages for select
  to authenticated
  using (public.is_conversation_participant(conversation_id, auth.uid()));

drop policy if exists "Participantes pueden enviar mensajes" on public.messages;
create policy "Participantes pueden enviar mensajes"
  on public.messages for insert
  to authenticated
  with check (
    auth.uid() = sender_id
    and public.is_conversation_participant(conversation_id, auth.uid())
  );

create table if not exists public.message_receipts (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text default 'delivered' check (status in ('sent', 'delivered', 'read')),
  status_at timestamptz default now(),
  unique (message_id, user_id)
);

alter table public.message_receipts enable row level security;

drop policy if exists "Ver recibos de mensajes en conversaciones compartidas" on public.message_receipts;
create policy "Ver recibos de mensajes en conversaciones compartidas"
  on public.message_receipts for select
  to authenticated
  using (true);

drop policy if exists "Actualizar o insertar propios recibos" on public.message_receipts;
create policy "Actualizar o insertar propios recibos"
  on public.message_receipts for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Trigger para actualizar last_activity_at en conversations cuando llega un mensaje
create or replace function public.update_conversation_last_activity()
returns trigger as $$
begin
  update public.conversations
  set last_activity_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_message_created on public.messages;
create trigger on_message_created
  after insert on public.messages
  for each row execute function public.update_conversation_last_activity();

-- 7. FUNCIONES RPC DE UTILIDAD (RPCs)

-- A. Crear o recuperar conversación directa entre dos usuarios
create or replace function public.create_direct_conversation(other_user_id uuid)
returns uuid as $$
declare
  existing_conv_id uuid;
  new_conv_id uuid;
begin
  if auth.uid() = other_user_id then
    raise exception 'No puedes iniciar una conversación contigo mismo.';
  end if;

  -- Buscar si ya existe una conversación directa activa entre ambos
  select cp1.conversation_id into existing_conv_id
  from public.conversation_participants cp1
  join public.conversation_participants cp2 on cp1.conversation_id = cp2.conversation_id
  join public.conversations c on c.id = cp1.conversation_id
  where c.type = 'direct'
    and cp1.user_id = auth.uid() and cp1.left_at is null
    and cp2.user_id = other_user_id and cp2.left_at is null
  limit 1;

  if existing_conv_id is not null then
    return existing_conv_id;
  end if;

  -- Crear nueva conversación
  insert into public.conversations (type, created_by)
  values ('direct', auth.uid())
  returning id into new_conv_id;

  -- Agregar a ambos participantes
  insert into public.conversation_participants (conversation_id, user_id, role)
  values
    (new_conv_id, auth.uid(), 'admin'),
    (new_conv_id, other_user_id, 'member');

  return new_conv_id;
end;
$$ language plpgsql security definer;

-- B. Búsqueda segura de perfiles por username o display_name
create or replace function public.search_profiles(query_text text)
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_url text,
  is_verified boolean
) as $$
begin
  return query
  select
    p.id,
    p.display_name,
    p.username,
    p.avatar_url,
    p.is_verified
  from public.profiles p
  where p.id != auth.uid()
    and p.is_searchable = true
    and (
      p.username ilike '%' || query_text || '%'
      or p.display_name ilike '%' || query_text || '%'
    )
  limit 20;
end;
$$ language plpgsql security definer;

-- C. Enviar solicitud de contacto por username
create or replace function public.send_contact_request(target_username text)
returns jsonb as $$
declare
  target_profile record;
  req_id uuid;
begin
  select id, display_name, username into target_profile
  from public.profiles
  where lower(username) = lower(trim(target_username))
  limit 1;

  if target_profile.id is null then
    return jsonb_build_object('success', false, 'message', 'Usuario no encontrado.');
  end if;

  if target_profile.id = auth.uid() then
    return jsonb_build_object('success', false, 'message', 'No puedes agregarte a ti mismo.');
  end if;

  -- Comprobar si ya son contactos
  if exists (select 1 from public.contacts where user_id = auth.uid() and contact_user_id = target_profile.id) then
    return jsonb_build_object('success', false, 'message', 'Este usuario ya está en tus contactos.');
  end if;

  insert into public.contact_requests (sender_id, receiver_id, status)
  values (auth.uid(), target_profile.id, 'pending')
  on conflict (sender_id, receiver_id) do update
  set status = 'pending', updated_at = now()
  returning id into req_id;

  return jsonb_build_object(
    'success', true,
    'message', 'Solicitud enviada a @' || target_profile.username,
    'request_id', req_id
  );
end;
$$ language plpgsql security definer;

-- D. Aceptar solicitud de contacto
create or replace function public.accept_contact_request(request_id uuid)
returns boolean as $$
declare
  req record;
begin
  select * into req
  from public.contact_requests
  where id = request_id and receiver_id = auth.uid() and status = 'pending';

  if req.id is null then
    return false;
  end if;

  -- Actualizar estado de la solicitud
  update public.contact_requests
  set status = 'accepted', updated_at = now()
  where id = request_id;

  -- Agregar contactos bidireccionales
  insert into public.contacts (user_id, contact_user_id)
  values
    (req.receiver_id, req.sender_id),
    (req.sender_id, req.receiver_id)
  on conflict do nothing;

  return true;
end;
$$ language plpgsql security definer;

-- E. Rechazar solicitud de contacto
create or replace function public.reject_contact_request(request_id uuid)
returns boolean as $$
begin
  update public.contact_requests
  set status = 'rejected', updated_at = now()
  where id = request_id and receiver_id = auth.uid() and status = 'pending';
  return found;
end;
$$ language plpgsql security definer;

-- F. Eliminar cuenta de usuario (Derecho al olvido y eliminación total)
create or replace function public.delete_user_account()
returns boolean as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return false;
  end if;

  delete from public.message_receipts where user_id = uid;
  delete from public.contact_requests where sender_id = uid or receiver_id = uid;
  delete from public.contacts where user_id = uid or contact_user_id = uid;
  delete from public.conversation_participants where user_id = uid;
  delete from public.messages where sender_id = uid;
  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;

  return true;
end;
$$ language plpgsql security definer;

-- Habilitar publicaciones Realtime de forma segura
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_receipts'
  ) then
    alter publication supabase_realtime add table public.message_receipts;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'contact_requests'
  ) then
    alter publication supabase_realtime add table public.contact_requests;
  end if;
end $$;

-- Recargar caché del esquema
notify pgrst, 'reload schema';
