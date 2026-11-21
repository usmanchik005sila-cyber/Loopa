begin;

create function public.loopa_visible_presence(p_users uuid[])
returns table(user_id uuid, last_active_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select p.user_id, p.last_active_at from public.user_presence p
  where (select auth.uid()) is not null and p.user_id = any(p_users)
    and (p.user_id = (select auth.uid()) or (
      p.visible and not public.loopa_pair_is_blocked((select auth.uid()), p.user_id)
    ));
$$;
revoke all on function public.loopa_visible_presence(uuid[]) from public, anon;
grant execute on function public.loopa_visible_presence(uuid[]) to authenticated;

create or replace function public.loopa_public_profiles()
returns table(id uuid, display_name text, username text, avatar_path text, updated_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.display_name, p.username,
    case when not public.loopa_pair_is_blocked((select auth.uid()), p.id) then p.avatar_path end,
    p.updated_at
  from public.profiles p where (select auth.uid()) is not null;
$$;

-- Also cover profile avatars that predate the public directory.
create function public.loopa_avatar_can_read(p_owner uuid)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select case when (select auth.uid()) is null or p_owner is null then false
    else not public.loopa_pair_is_blocked((select auth.uid()), p_owner)
  end;
$$;
revoke all on function public.loopa_avatar_can_read(uuid) from public, anon;
grant execute on function public.loopa_avatar_can_read(uuid) to authenticated;

-- A blocked pair cannot see each other's live room heartbeat either.
do $patch$
declare
  definition text := pg_get_functiondef('public.loopa_room16(text,text,text,double precision)'::regprocedure);
  old_online constant text := 'coalesce(m.seen>stamp-interval ''20 seconds'',false)';
begin
  if position(old_online in definition) = 0 then raise exception 'Unexpected room heartbeat definition'; end if;
  execute replace(definition, old_online,
    'coalesce(m.seen>stamp-interval ''20 seconds'',false) and (m.member=u or (
      not public.loopa_pair_is_blocked(u,m.member) and not exists (
        select 1 from public.user_presence pr where pr.user_id=m.member and not pr.visible
      )
    ))');
end;
$patch$;

notify pgrst, 'reload schema';
commit;
