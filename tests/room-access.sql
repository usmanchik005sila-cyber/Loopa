-- Run against an isolated database with the room migrations applied.
begin;

insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000101'),
  ('00000000-0000-4000-8000-000000000102'),
  ('00000000-0000-4000-8000-000000000103');

insert into public.profiles(id, display_name) values
  ('00000000-0000-4000-8000-000000000101', 'Host'),
  ('00000000-0000-4000-8000-000000000102', 'Guest'),
  ('00000000-0000-4000-8000-000000000103', 'Friend')
on conflict (id) do nothing;

insert into public.friend_requests(sender_id, receiver_id, status) values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000103', 'accepted');

set local role authenticated;

do $test$
declare
  host_id constant uuid := '00000000-0000-4000-8000-000000000101';
  guest_id constant uuid := '00000000-0000-4000-8000-000000000102';
  friend_id constant uuid := '00000000-0000-4000-8000-000000000103';
  room_code text;
  state jsonb;
  invite_id uuid;
begin
  perform set_config('request.jwt.claim.sub', host_id::text, true);
  room_code := public.loopa_room16(op => 'create')->>'code';

  perform set_config('request.jwt.claim.sub', guest_id::text, true);
  perform public.loopa_room16(op => 'join', room => room_code);
  begin
    perform public.loopa_room16(op => 'access', room => room_code, media => '{"mode":"private","ids":[]}');
    raise exception 'Guest changed room access';
  exception when raise_exception then
    if sqlerrm <> 'Нет доступа' then raise; end if;
  end;
  begin
    perform public.loopa_invite25(action => 'send', room_code => room_code, peer => friend_id);
    raise exception 'Guest sent a room invitation';
  exception when raise_exception then
    if sqlerrm <> 'Приглашать может ведущий комнаты' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', host_id::text, true);
  perform public.loopa_room16(op => 'access', room => room_code, media => '{"mode":"friends","ids":[]}');
  perform set_config('request.jwt.claim.sub', guest_id::text, true);
  if public.loopa_room16(op => 'list') ? room_code then
    raise exception 'Friends-only room still listed for a non-friend';
  end if;
  perform set_config('request.jwt.claim.sub', friend_id::text, true);
  perform public.loopa_room16(op => 'join', room => room_code);

  perform set_config('request.jwt.claim.sub', host_id::text, true);
  state := public.loopa_room16(op => 'access', room => room_code,
    media => jsonb_build_object('mode', 'private', 'ids', array[guest_id])::text);
  if state->'allowed' is distinct from to_jsonb(array[guest_id]) then
    raise exception 'Host could not save the private room allow-list';
  end if;
  invite_id := (public.loopa_invite25(action => 'send', room_code => room_code, peer => friend_id)->>'id')::uuid;

  perform set_config('request.jwt.claim.sub', guest_id::text, true);
  state := public.loopa_room16(op => 'read', room => room_code);
  if state->'allowed' is distinct from '[]'::jsonb then
    raise exception 'Guest received the room allow-list';
  end if;

  perform set_config('request.jwt.claim.sub', friend_id::text, true);
  begin
    perform public.loopa_room16(op => 'read', room => room_code);
    raise exception 'Existing participant kept access after the room was made private';
  exception when raise_exception then
    if sqlerrm <> 'Комната недоступна' then raise; end if;
  end;
  perform public.loopa_invite25(action => 'accept', invitation => invite_id);
  perform public.loopa_room16(op => 'read', room => room_code);

  perform set_config('request.jwt.claim.sub', host_id::text, true);
  perform public.loopa_room16(op => 'access', room => room_code, media => '{"mode":"code","ids":[]}');
  perform set_config('request.jwt.claim.sub', guest_id::text, true);
  perform public.loopa_room16(op => 'read', room => room_code);
end;
$test$;

reset role;

do $test$
begin
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.loopa_rooms16'::regclass
      and conname = 'loopa_rooms16_allowed_members_valid' and convalidated) then
    raise exception 'Room allow-list constraint is missing or unvalidated';
  end if;
end;
$test$;

rollback;
