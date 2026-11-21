begin;

do $test$
declare
  actor uuid := gen_random_uuid();
  targets uuid[] := array(select gen_random_uuid() from generate_series(1,7));
  peer uuid := targets[1];
  room_key text;
  invitation_id uuid;
begin
  insert into auth.users(id) select unnest(array_prepend(actor, targets));
  insert into public.profiles(id, display_name)
    select unnest(array_prepend(actor, targets)), 'Social quota fixture'
    on conflict (id) do nothing;
  insert into public.loopa_rooms16(host) values(actor) returning code into room_key;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', actor::text, true);
  for i in 1..5 loop
    insert into public.friend_requests(sender_id, receiver_id) values(actor, targets[i]);
  end loop;
  reset role;
  update loopa_private.request_budgets set tokens=0, updated_at=clock_timestamp()+interval '1 hour'
    where user_id=actor and scope='friend_request';
  set local role authenticated;
  begin
    insert into public.friend_requests(sender_id, receiver_id) values(actor, targets[6]);
    raise exception 'Friend request should respect its exhausted budget';
  exception when raise_exception then
    if sqlerrm not like 'Слишком много заявок в друзья.%' then raise; end if;
  end;
  reset role;
  update loopa_private.request_budgets set updated_at=clock_timestamp()-interval '13 seconds'
    where user_id=actor and scope='friend_request';
  set local role authenticated;
  insert into public.friend_requests(sender_id, receiver_id) values(actor, targets[6]);

  reset role;
  update public.friend_requests set status='accepted' where sender_id=actor and receiver_id=peer;
  set local role authenticated;
  invitation_id := (public.loopa_invite25('send', room_key, peer)->>'id')::uuid;
  perform set_config('request.jwt.claim.sub', peer::text, true);
  perform public.loopa_invite25('accept', invitation=>invitation_id);
  reset role;
  if not exists(select 1 from loopa_private.request_budgets
    where user_id=actor and scope='room_invite' and tokens<20)
     or exists(select 1 from loopa_private.request_budgets where user_id=peer and scope='room_invite') then
    raise exception 'Only sending should count toward the sender invitation budget';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  update public.loopa_invites25 set sent=now()-interval '2 minutes' where id=invitation_id;
  update loopa_private.request_budgets set tokens=0, updated_at=clock_timestamp()+interval '1 hour'
    where user_id=actor and scope='room_invite';

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', actor::text, true);
  begin
    perform public.loopa_invite25('send', room_key, peer);
    raise exception 'Invitation resend should respect the exhausted budget';
  exception when raise_exception then
    if sqlerrm not like 'Слишком много приглашений.%' then raise; end if;
  end;

  reset role;
  update loopa_private.request_budgets set updated_at=clock_timestamp()-interval '4 seconds'
    where user_id=actor and scope='room_invite';
  set local role authenticated;
  if (public.loopa_invite25('send', room_key, peer)->>'id')::uuid is distinct from invitation_id then
    raise exception 'Invitation resend should work after refill';
  end if;
end;
$test$;

rollback;
