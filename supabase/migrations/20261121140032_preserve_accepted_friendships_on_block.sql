begin;

create or replace function public.loopa_block_user(target_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare actor uuid := auth.uid();
begin
  if actor is null or target_user is null or target_user = actor then
    raise exception 'Invalid block target';
  end if;

  insert into public.blocked_users(blocker_id, blocked_id)
  values (actor, target_user) on conflict do nothing;

  delete from public.friend_requests
  where status = 'pending'
    and ((sender_id = actor and receiver_id = target_user)
      or (sender_id = target_user and receiver_id = actor));
end;
$$;

-- A retained friendship must not grant access to a blocked user's statistics.
CREATE OR REPLACE FUNCTION public.loopa_friend_stats_v87(peer_id uuid)
 RETURNS TABLE(total_seconds bigint, joined_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select u.total_seconds from public.loopa_usage_v87 u where u.user_id=peer_id),0),
        (select a.created_at from auth.users a where a.id=peer_id)
 where auth.uid() is not null and (peer_id = auth.uid() or (not public.loopa_pair_is_blocked(auth.uid(), peer_id) and exists (
   select 1 from public.friend_requests f
   where f.status='accepted'
     and ((f.sender_id=auth.uid() and f.receiver_id=peer_id)
       or (f.sender_id=peer_id and f.receiver_id=auth.uid()))
 )));
$function$;

CREATE OR REPLACE FUNCTION public.loopa_friend_stats_v88(peer_id uuid)
 RETURNS TABLE(total_seconds bigint, joined_at timestamp with time zone, history_synced boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select u.total_seconds from public.loopa_usage_v87 u where u.user_id=peer_id),0)::bigint,
         (select a.created_at from auth.users a where a.id=peer_id),
         coalesce((select u.history_synced from public.loopa_usage_v87 u where u.user_id=peer_id),false)
  where auth.uid() is not null and (peer_id = auth.uid() or (not public.loopa_pair_is_blocked(auth.uid(), peer_id) and exists (
    select 1 from public.friend_requests f
    where f.status = 'accepted'
      and ((f.sender_id=auth.uid() and f.receiver_id=peer_id)
        or (f.sender_id=peer_id and f.receiver_id=auth.uid()))
  )));
$function$;

revoke all on function public.loopa_block_user(uuid), public.loopa_friend_stats_v87(uuid),
  public.loopa_friend_stats_v88(uuid) from public, anon;
grant execute on function public.loopa_block_user(uuid), public.loopa_friend_stats_v87(uuid),
  public.loopa_friend_stats_v88(uuid) to authenticated;

commit;
