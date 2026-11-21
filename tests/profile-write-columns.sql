-- Run on an isolated database with the profile RLS and directory applied.
begin;

insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000411'),
  ('00000000-0000-4000-8000-000000000412');

set local role authenticated;

do $test$
declare
  owner_id constant uuid := '00000000-0000-4000-8000-000000000411';
  viewer_id constant uuid := '00000000-0000-4000-8000-000000000412';
  created timestamptz;
  preview jsonb;
begin
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  insert into public.profiles(id, display_name, username)
  values (owner_id, 'Profile fixture', 'profile_fixture')
  on conflict (id) do update set id = excluded.id, display_name = excluded.display_name, username = excluded.username;
  select created_at into created from public.profiles where id = owner_id;
  if created is null then raise exception 'Owner creation time is missing'; end if;

  insert into public.profiles(id, display_name, username)
  values (owner_id, 'Edited fixture', 'edited_fixture')
  on conflict (id) do update set id = excluded.id, display_name = excluded.display_name, username = excluded.username;
  update public.profiles set dm_policy = 'friends', notification_sound = false,
      avatar_path = owner_id::text || '/avatar.jpg', updated_at = clock_timestamp()
    where id = owner_id;
  if not exists (select 1 from public.profiles where id = owner_id and created_at = created
      and display_name = 'Edited fixture' and dm_policy = 'friends' and not notification_sound) then
    raise exception 'Owner profile changes did not persist';
  end if;
  if has_column_privilege('authenticated','public.profiles','created_at','INSERT')
     or has_column_privilege('authenticated','public.profiles','created_at','UPDATE') then
    raise exception 'Profile creation time must be server assigned';
  end if;

  perform set_config('request.jwt.claim.sub', viewer_id::text, true);
  if exists (select 1 from public.profiles where id = owner_id) then
    raise exception 'Another user can read the private profile row';
  end if;
  select to_jsonb(p) into preview from public.loopa_profiles_by_ids(array[owner_id]) p where p.username = 'edited_fixture';
  if preview->>'display_name' is distinct from 'Edited fixture'
     or preview->>'avatar_path' is distinct from (owner_id::text || '/avatar.jpg')
     or (preview - array['id','display_name','username','avatar_path','updated_at']) is distinct from '{}'::jsonb then
    raise exception 'Unexpected profile search fields';
  end if;
  if has_function_privilege('anon','public.loopa_profiles_by_ids(uuid[])','EXECUTE') then
    raise exception 'Anonymous profile directory access';
  end if;
end;
$test$;

rollback;
