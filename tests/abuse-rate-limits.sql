-- Run in BEGIN/ROLLBACK. All users, messages, rooms and budgets are temporary.
do $test$
declare actor uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); r text; result jsonb; i integer;
begin
 insert into auth.users(id) values(actor),(peer);
 insert into public.profiles(id,display_name) values(actor,'Quota fixture'),(peer,'Quota fixture') on conflict do nothing;
 insert into public.loopa_rooms16(host) values(actor) returning code into r;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 for i in 1..8 loop
  insert into public.loopa_dm_messages_v87(sender_id,recipient_id,body) values(actor,peer,'quota fixture');
 end loop;
 -- Freeze a drained bucket to make assertions independent of test runtime.
 update loopa_private.request_budgets set tokens=0,updated_at=clock_timestamp()+interval '1 hour' where user_id=actor and scope='message';
 begin
  insert into public.loopa_dm_messages_v87(sender_id,recipient_id,body) values(actor,peer,'blocked');
  raise exception 'TEST message flood was accepted';
 exception when raise_exception then
  if sqlerrm not like 'Слишком много сообщений.%' then raise; end if;
 end;
 begin
  insert into public.loopa_chat18(code,author,body) values(r,actor,'blocked');
  raise exception 'TEST room chat bypassed shared message budget';
 exception when raise_exception then
  if sqlerrm not like 'Слишком много сообщений.%' then raise; end if;
 end;
 update loopa_private.request_budgets set tokens=0,updated_at=clock_timestamp()-interval '2 seconds' where user_id=actor and scope='message';
 insert into public.loopa_chat18(code,author,body) values(r,actor,'refilled');
 for i in 1..5 loop perform public.loopa_room16('create'); end loop;
 update loopa_private.request_budgets set tokens=0,updated_at=clock_timestamp()+interval '1 hour' where user_id=actor and scope='room_create';
 begin
  perform public.loopa_room16('create');raise exception 'TEST room flood was accepted';
 exception when raise_exception then
  if sqlerrm not like 'Слишком часто создаёшь комнаты.%' then raise; end if;
 end;
 for i in 1..10 loop
  result:=public.loopa_search_budget('search');
  if not (result->>'allowed')::boolean then raise exception 'TEST normal search was blocked'; end if;
 end loop;
 update loopa_private.request_budgets set tokens=0,updated_at=clock_timestamp()+interval '1 hour' where user_id=actor and scope='search';
 result:=public.loopa_search_budget('search');
 if (result->>'allowed')::boolean or (result->>'retry_after')::integer<1 then raise exception 'TEST search flood was accepted'; end if;
 -- Typing uses a separate, larger allowance from full catalog searches.
 for i in 1..30 loop
  result:=public.loopa_search_budget('suggest');
  if not (result->>'allowed')::boolean then raise exception 'TEST autocomplete blocked too early'; end if;
 end loop;
 perform set_config('request.jwt.claim.sub',peer::text,true);
 result:=public.loopa_search_budget('search');
 if not (result->>'allowed')::boolean then raise exception 'TEST one actor consumed another actor budget'; end if;
 if has_function_privilege('anon','public.loopa_search_budget(text)','execute')
 or has_function_privilege('authenticated','loopa_private.consume_budget(text)','execute')
 or has_table_privilege('authenticated','loopa_private.request_budgets','update') then
  raise exception 'TEST application can bypass budget internals';
 end if;
end $test$;
