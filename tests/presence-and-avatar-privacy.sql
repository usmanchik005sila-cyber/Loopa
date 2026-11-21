begin;

insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000511'),
  ('00000000-0000-4000-8000-000000000512'),
  ('00000000-0000-4000-8000-000000000513');
insert into public.profiles(id, display_name, avatar_path) values
  ('00000000-0000-4000-8000-000000000511', 'Visible user', '00000000-0000-4000-8000-000000000511/avatar.jpg'),
  ('00000000-0000-4000-8000-000000000512', 'Viewer', null),
  ('00000000-0000-4000-8000-000000000513', 'Hidden user', null)
on conflict (id) do update set display_name = excluded.display_name, avatar_path = excluded.avatar_path;
insert into public.user_presence(user_id, visible) values
  ('00000000-0000-4000-8000-000000000511', true),
  ('00000000-0000-4000-8000-000000000513', false)
on conflict (user_id) do update set visible = excluded.visible;

do $test$
declare
  owner_id constant uuid := '00000000-0000-4000-8000-000000000511';
  viewer_id constant uuid := '00000000-0000-4000-8000-000000000512';
  hidden_id constant uuid := '00000000-0000-4000-8000-000000000513';
  room_key text;
  roster jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', hidden_id::text, true);
  room_key := public.loopa_room16('create')->>'code';
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform public.loopa_room16('join', room_key);
  perform set_config('request.jwt.claim.sub', viewer_id::text, true);
  roster := public.loopa_room16('join', room_key)->'members';
  if not roster @> jsonb_build_array(jsonb_build_object('id', owner_id, 'online', true))
     or not roster @> jsonb_build_array(jsonb_build_object('id', hidden_id, 'online', false)) then
    raise exception 'Room online indicators must respect presence settings';
  end if;
  if (select count(*) from public.loopa_visible_presence(array[owner_id, hidden_id])) <> 1
     or not exists (select 1 from public.loopa_visible_presence(array[owner_id]))
     or public.loopa_avatar_can_read(owner_id) is distinct from true then
    raise exception 'Non-friend visibility did not follow owner settings';
  end if;
  if exists (select 1 from public.user_presence where user_id = owner_id) then
    raise exception 'Direct reads must only expose the viewer''s own presence settings';
  end if;

  reset role;
  insert into public.blocked_users(blocker_id, blocked_id) values (owner_id, viewer_id);
  set local role authenticated;

  roster := public.loopa_room16('read', room_key)->'members';
  if exists (select 1 from public.loopa_visible_presence(array[owner_id]))
     or exists (select 1 from public.loopa_public_profiles() where id = owner_id and avatar_path is not null)
     or public.loopa_avatar_can_read(owner_id) is distinct from false
     or not roster @> jsonb_build_array(jsonb_build_object('id', owner_id, 'online', false)) then
    raise exception 'The blocked viewer still has access';
  end if;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  if not exists (select 1 from public.loopa_visible_presence(array[owner_id]))
     or public.loopa_avatar_can_read(owner_id) is distinct from true then
    raise exception 'The owner lost access to their own data';
  end if;
end;
$test$;

rollback;
