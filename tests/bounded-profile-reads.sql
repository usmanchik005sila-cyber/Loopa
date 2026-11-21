begin;

do $test$
declare
  viewer uuid := gen_random_uuid();
  peer uuid := gen_random_uuid();
  extra uuid[] := array(select gen_random_uuid() from generate_series(1,17));
  result jsonb;
begin
  insert into auth.users(id) values (viewer), (peer);
  insert into public.profiles(id, display_name, username) values
    (viewer,'Viewer',null), (peer,'Фикстура поиска','search_fixture')
  on conflict (id) do update set display_name = excluded.display_name, username = excluded.username;
  insert into auth.users(id) select unnest(extra);
  insert into public.profiles(id,display_name) select unnest(extra),'Fixture sample'
  on conflict (id) do update set display_name = excluded.display_name;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub',viewer::text,true);
  result := public.loopa_search_profiles('@SEARCH_FIXTURE');
  if result->'profiles'->0->>'id' is distinct from peer::text then
    raise exception 'Exact username not found';
  end if;
  result := public.loopa_search_profiles('ПОИ');
  if result->'profiles'->0->>'id' is distinct from peer::text then
    raise exception 'Case-insensitive display name search failed';
  end if;
  result := public.loopa_search_profiles('fixture');
  if jsonb_array_length(result->'profiles') <> 15 then
    raise exception 'Display name search must stay within its result limit';
  end if;
  if (select count(*) from public.loopa_profiles_by_ids(array[peer])) <> 1
     or exists (select 1 from public.loopa_profiles_by_ids(array_fill(peer,array[151]))) then
    raise exception 'Profile ID lookup does not honor its batch bound';
  end if;
  if has_function_privilege('authenticated','public.loopa_public_profiles()','execute')
     or has_function_privilege('anon','public.loopa_profiles_by_ids(uuid[])','execute')
     or has_function_privilege('anon','public.loopa_search_profiles(text)','execute') then
    raise exception 'Unexpected public profile RPC access';
  end if;

  reset role;
  update loopa_private.request_budgets set tokens=0,updated_at=clock_timestamp()+interval '1 hour'
    where user_id=viewer and scope='user_search';
  set local role authenticated;
  result := public.loopa_search_profiles('поиск');
  if (result->>'retry_after')::integer is null or result->'profiles' <> '[]'::jsonb
     or (select count(*) from public.loopa_profiles_by_ids(array[peer])) <> 1 then
    raise exception 'Search quota should not prevent loading known profiles';
  end if;
end;
$test$;

rollback;
