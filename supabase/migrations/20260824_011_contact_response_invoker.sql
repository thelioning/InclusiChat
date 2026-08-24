-- REP-001 follow-up: contact response RPCs do not require elevated privileges.
-- They operate on rows already authorized by RLS. The privileged reciprocal
-- contact insertion remains inside the private trigger function.

begin;

alter function public.accept_contact_request(uuid) security invoker;
alter function public.reject_contact_request(uuid) security invoker;

revoke execute on function public.accept_contact_request(uuid) from public, anon;
revoke execute on function public.reject_contact_request(uuid) from public, anon;
grant execute on function public.accept_contact_request(uuid) to authenticated;
grant execute on function public.reject_contact_request(uuid) to authenticated;

commit;
