-- Deploy before publishing the client that uses the public directory.
begin;
create or replace function public.loopa_public_profiles()
returns table(id uuid, display_name text, username text, avatar_path text, updated_at timestamptz)
language sql stable security definer set search_path = ''
as $$
 select p.id,p.display_name,p.username,p.avatar_path,p.updated_at
 from public.profiles p where (select auth.uid()) is not null;
$$;
revoke all on function public.loopa_public_profiles() from public,anon;
grant execute on function public.loopa_public_profiles() to authenticated;
comment on function public.loopa_public_profiles() is
 'Public profile projection for signed-in users including authenticated guests. Never add private settings.';
notify pgrst, 'reload schema';
commit;
