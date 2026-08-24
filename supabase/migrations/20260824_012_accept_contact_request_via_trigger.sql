-- REP-001 follow-up: keep accept_contact_request as SECURITY INVOKER.
-- The caller only changes their own received request from pending to accepted.
-- Reciprocal contact rows are created by private.create_contacts_after_acceptance().

begin;

create or replace function public.accept_contact_request(request_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.contact_requests
  set status = 'accepted'
  where id = request_id
    and receiver_id = auth.uid()
    and status = 'pending';

  return found;
end;
$$;

revoke execute on function public.accept_contact_request(uuid) from public, anon;
grant execute on function public.accept_contact_request(uuid) to authenticated;

commit;
