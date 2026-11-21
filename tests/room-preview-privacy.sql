begin;

insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000211'),
  ('00000000-0000-4000-8000-000000000212'),
  ('00000000-0000-4000-8000-000000000213');
insert into public.profiles(id, display_name) values
  ('00000000-0000-4000-8000-000000000211', 'Host'),
  ('00000000-0000-4000-8000-000000000212', 'Participant'),
  ('00000000-0000-4000-8000-000000000213', 'Viewer')
on conflict (id) do nothing;
insert into public.friend_requests(sender_id, receiver_id, status) values
  ('00000000-0000-4000-8000-000000000211', '00000000-0000-4000-8000-000000000212', 'accepted'),
  ('00000000-0000-4000-8000-000000000212', '00000000-0000-4000-8000-000000000213', 'accepted');
insert into public.user_presence(user_id, visible, share_room_activity)
values ('00000000-0000-4000-8000-000000000212', true, true)
on conflict (user_id) do update set visible = true, share_room_activity = true;

do $test$
declare
  host_id constant uuid := '00000000-0000-4000-8000-000000000211';
  participant_id constant uuid := '00000000-0000-4000-8000-000000000212';
  viewer_id constant uuid := '00000000-0000-4000-8000-000000000213';
  video_url constant text := 'https://www.youtube.com/embed/dQw4w9WgXcQ';
  room_key text;
  preview jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', host_id::text, true);
  room_key := public.loopa_room16('create')->>'code';
  perform public.loopa_room16('video', room_key, video_url);
  perform public.loopa_activity26('title', room_code => room_key, media => video_url, title => 'Fixture video');

  perform set_config('request.jwt.claim.sub', participant_id::text, true);
  perform public.loopa_room16('join', room_key);
  perform set_config('request.jwt.claim.sub', viewer_id::text, true);
  preview := public.loopa_activity26('friends')->0;
  if preview->>'title' is distinct from 'Fixture video' or preview->>'private' is distinct from 'false' then
    raise exception 'Code room preview missing';
  end if;

  perform set_config('request.jwt.claim.sub', host_id::text, true);
  perform public.loopa_room16('access', room_key, '{"mode":"friends","ids":[]}');
  perform set_config('request.jwt.claim.sub', viewer_id::text, true);
  preview := public.loopa_activity26('friends')->0;
  if preview->>'private' is distinct from 'true' or preview->>'state' is distinct from 'in_room'
     or preview->'title' is distinct from 'null'::jsonb then
    raise exception 'Friends-only room preview should be limited';
  end if;

  reset role;
  insert into public.friend_requests(sender_id, receiver_id, status) values (host_id, viewer_id, 'accepted');
  update public.loopa_titles26 set image = 'fixture-cover' where loopa_titles26.code = room_key;
  set local role authenticated;

  perform set_config('request.jwt.claim.sub', viewer_id::text, true);
  preview := public.loopa_activity26('friends')->0;
  if preview->>'title' is distinct from 'Fixture video' then raise exception 'Host friend preview missing'; end if;

  perform set_config('request.jwt.claim.sub', host_id::text, true);
  perform public.loopa_room16('access', room_key,
    jsonb_build_object('mode', 'private', 'ids', array[participant_id])::text);
  perform public.loopa_invite25('send', room_key, viewer_id);
  perform set_config('request.jwt.claim.sub', viewer_id::text, true);
  preview := public.loopa_invite25('inbox')->0;
  if preview->>'watch_title' is distinct from 'Закрытая комната'
     or preview->'watch_image' is distinct from 'null'::jsonb
     or preview->'participant_count' is distinct from 'null'::jsonb then
    raise exception 'Private invitation preview should be limited';
  end if;
  perform public.loopa_invite25('accept', invitation => (preview->>'id')::uuid);
  preview := public.loopa_activity26('friends')->0;
  if preview->>'title' is distinct from 'Fixture video' then
    raise exception 'Private room authorization should restore the friend preview';
  end if;
end;
$test$;

rollback;
