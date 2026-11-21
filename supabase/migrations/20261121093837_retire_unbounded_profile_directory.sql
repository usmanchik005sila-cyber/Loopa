-- Apply after the client uses bounded profile lookups and search.
begin;

revoke execute on function public.loopa_public_profiles() from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
