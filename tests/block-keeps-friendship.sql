begin;

insert into auth.users(id)
values ('10000000-0000-4000-8000-000000000001'),
       ('10000000-0000-4000-8000-000000000002'),
       ('10000000-0000-4000-8000-000000000003');

insert into public.profiles(id, display_name, dm_policy)
select id, 'Test account', 'friends' from auth.users
where id in ('10000000-0000-4000-8000-000000000001',
             '10000000-0000-4000-8000-000000000002',
             '10000000-0000-4000-8000-000000000003');

insert into public.user_presence(user_id)
select id from public.profiles
where id in ('10000000-0000-4000-8000-000000000001',
             '10000000-0000-4000-8000-000000000002');

insert into public.friend_requests(sender_id, receiver_id, status)
values ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'accepted'),
       ('10000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'pending');

set local role authenticated;
do $$
declare
  actor constant uuid := '10000000-0000-4000-8000-000000000001';
  friend constant uuid := '10000000-0000-4000-8000-000000000002';
  requester constant uuid := '10000000-0000-4000-8000-000000000003';
begin
  perform set_config('request.jwt.claim.sub', actor::text, true);
  perform public.loopa_block_user(friend);
  perform public.loopa_block_user(friend);
  perform public.loopa_block_user(requester);

  if not exists (select 1 from public.friend_requests where sender_id=actor and receiver_id=friend and status='accepted') then
    raise exception 'Blocking must retain accepted friendships';
  end if;
  if exists (select 1 from public.friend_requests where sender_id=requester and receiver_id=actor) then
    raise exception 'Blocking must clear pending requests for the pair';
  end if;

  for direction in 1..2 loop
    if direction=2 then
      perform set_config('request.jwt.claim.sub', friend::text, true);
    end if;
    declare peer uuid := case when direction=1 then friend else actor end;
    begin
      if public.loopa_dm_may_send_v87(peer) or public.loopa_avatar_can_read(peer)
         or exists (select 1 from public.loopa_friend_stats_v87(peer))
         or exists (select 1 from public.loopa_friend_stats_v88(peer))
         or exists (select 1 from public.loopa_visible_presence(array[peer])) then
        raise exception 'Messaging, avatars, statistics and presence must stay restricted in both directions';
      end if;
    end;
  end loop;

  perform set_config('request.jwt.claim.sub', actor::text, true);
  perform public.loopa_unblock_user(friend);
  if not public.loopa_dm_may_send_v87(friend) or not public.loopa_avatar_can_read(friend)
     or not exists (select 1 from public.loopa_friend_stats_v87(friend))
     or not exists (select 1 from public.loopa_friend_stats_v88(friend))
     or not exists (select 1 from public.loopa_visible_presence(array[friend])) then
    raise exception 'Unblocking must restore access under the original friendship';
  end if;
end;
$$;

rollback;
