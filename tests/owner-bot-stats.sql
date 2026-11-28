-- Run after the owner statistics migration on the empty schema fixture.
insert into auth.users(id,email,email_confirmed_at,deleted_at,is_anonymous,raw_app_meta_data)
select ('10000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  case n when 9 then 'miniapp-555012@auth.loopacinema.invalid'
    when 10 then 'miniapp-555013@auth.loopacinema.invalid' else n || '@example.test' end,
  case n when 2 then now()-interval '2 days' when 3 then now()-interval '15 days'
    when 4 then now()-interval '31 days' when 6 then null else now() end,
  case when n = 8 then now() end, n = 7,
  case n when 5 then '{"loopa_test_account":true}'::jsonb
    when 9 then '{"loopa_telegram_registration":"555012"}'::jsonb
    when 10 then '{"loopa_telegram_registration":"555013"}'::jsonb else '{}'::jsonb end
from generate_series(1,10) n;
select public.loopa_complete_telegram_registration('555013');

insert into public.user_presence(user_id,last_active_at,visible)
select ('10000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid, now()-age, n <> 1
from (values (1, interval '30 seconds'), (2, interval '2 hours'), (3, interval '29 days'),
  (4, interval '31 days'), (6, interval '30 seconds'), (7, interval '30 seconds'),
  (8, interval '30 seconds'), (10, interval '1 day 1 hour')) t(n,age);

insert into public.loopa_rooms16(code,host,video) values
 ('001111111111','10000000-0000-4000-8000-000000000001','https://www.youtube.com/embed/jNQXAC9IVRw'),
 ('002222222222','10000000-0000-4000-8000-000000000002','https://vkvideo.ru/video_ext.php?oid=1&id=2&js_api=1'),
 ('003333333333','10000000-0000-4000-8000-000000000003','https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/'),
 ('004444444444','10000000-0000-4000-8000-000000000004','');
update public.loopa_rooms16 set video=video where code='001111111111';
update public.loopa_rooms16 set video='https://www.youtube.com/embed/aqz-KE-bpKQ' where code='004444444444';
update public.loopa_rooms16 set pos=7 where code='001111111111';
insert into loopa_private.bot_stats_room_events(occurred_at,kind) values
 (now()-interval '25 hours','created'),(now()-interval '31 days','youtube');

insert into public.loopa_members16(code,member,seen)
select code,('10000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid, now()-age
from (values ('001111111111',1,interval '1 second'),('001111111111',2,interval '1 second'),
 ('002222222222',2,interval '1 second'),('002222222222',3,interval '1 second'),
 ('003333333333',3,interval '1 second'),('003333333333',4,interval '1 second'),
 ('004444444444',4,interval '21 seconds'),('004444444444',3,interval '21 seconds')) t(code,n,age);
insert into public.loopa_playback57(code,video,pos,playing,stamp,owner)
select code,video,0,code <> '003333333333',now()-interval '1 second',host from public.loopa_rooms16;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select public.loopa_room16('create')->>'code' as created_code \gset
reset role;
-- A room demolished after creation still counts as a creation.
delete from public.loopa_rooms16 where code=:'created_code';

do $$
begin
  if has_function_privilege('anon','public.loopa_owner_bot_stats()','execute')
    or has_function_privilege('authenticated','public.loopa_owner_bot_stats()','execute')
    or has_function_privilege('authenticated','loopa_private.owner_bot_stats()','execute')
    or has_table_privilege('service_role','loopa_private.bot_stats_room_events','select')
    or not (select relrowsecurity from pg_class where oid='loopa_private.bot_stats_room_events'::regclass) then
    raise exception 'Unexpected statistics privileges';
  end if;
end;
$$;

set local role anon;
do $$
begin
  perform public.loopa_owner_bot_stats();
  raise exception 'Anonymous invocation unexpectedly succeeded';
exception when insufficient_privilege then null;
end;
$$;
reset role;

set local role authenticated;
do $$
begin
  perform public.loopa_owner_bot_stats();
  raise exception 'Authenticated invocation unexpectedly succeeded';
exception when insufficient_privilege then null;
end;
$$;
reset role;

set local role service_role;
do $$
declare
  report jsonb := public.loopa_owner_bot_stats();
  expected jsonb := '{
    "registered":6,"new_today":2,"new_7d":3,"new_30d":4,
    "online":1,"active_24h":2,"active_30d":4,"active_rooms":3,
    "watching_together":3,"rooms_created_24h":5,
    "providers":{"youtube":2,"vk":1,"rutube":1}
  }';
begin
  if not report @> expected
    or (report->>'room_tracking_started_at')::timestamptz > (report->>'as_of')::timestamptz then
    raise exception 'Unexpected owner report %', report;
  end if;
end;
$$;
reset role;

update public.loopa_playback57 set stamp=now()-interval '21 seconds' where code='001111111111';
update public.loopa_playback57 set video='https://www.youtube.com/embed/aqz-KE-bpKQ' where code='002222222222';
set local role service_role;
do $$
begin
  if public.loopa_owner_bot_stats()->>'watching_together' <> '0' then
    raise exception 'Stale and mismatched player state must not count';
  end if;
end;
$$;
reset role;
