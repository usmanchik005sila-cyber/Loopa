-- Run inside BEGIN/ROLLBACK after migration. No persistent fixtures.
do $test$
declare h uuid:=gen_random_uuid(); g uuid:=gen_random_uuid(); test_code text; gen bigint; v text:='https://www.youtube.com/embed/dQw4w9WgXcQ'; result jsonb; first_seq bigint;
begin
 insert into auth.users(id) values(h),(g);
 perform set_config('request.jwt.claim.sub',h::text,true);
 test_code:=public.loopa_room16(op=>'create')->>'code';
 perform public.loopa_room16(op=>'video',room=>test_code,media=>v);
 perform public.loopa_collab27(action=>'mode',room_code=>test_code,enabled=>true);
 select control_generation into gen from public.loopa_rooms16 where loopa_rooms16.code=test_code;
 perform public.loopa_collab27(action=>'renew',room_code=>test_code);
 perform public.loopa_room16(op=>'pause',room=>test_code,seconds=>5);
 if (select control_generation from public.loopa_rooms16 where loopa_rooms16.code=test_code)<>gen then raise exception 'Renew changed generation'; end if;
 perform set_config('request.jwt.claim.sub',g::text,true);
 perform public.loopa_room16(op=>'join',room=>test_code);
 if has_function_privilege('authenticated','loopa_private.loopa_collab27(text,text,boolean,double precision,boolean,bigint)','EXECUTE') then
  raise exception 'Guest role can execute room control implementation directly';
 end if;
 begin
  perform public.loopa_collab27(action=>'control',room_code=>test_code,position_seconds=>100,is_playing=>false);
  raise exception 'TEST context-free command accepted';
 exception when others then if sqlerrm<>'Команда недоступна. Обнови LOOPA' then raise; end if; end;
 result:=public.loopa_control_v2(test_code,v,gen,100,false);first_seq:=(result->>'seq')::bigint;
 perform public.loopa_control_v2(test_code,v,gen,200,false);
 perform set_config('request.jwt.claim.sub',h::text,true);
 result:=public.loopa_collab27(action=>'ack',room_code=>test_code,sequence=>first_seq);
 if (result->>'applied')::boolean then raise exception 'Old ACK accepted'; end if;
 perform public.loopa_collab27(action=>'mode',room_code=>test_code,enabled=>false);
 perform public.loopa_collab27(action=>'mode',room_code=>test_code,enabled=>true);
 perform set_config('request.jwt.claim.sub',g::text,true);
 begin
  perform public.loopa_control_v2(test_code,v,gen,300,false);
  raise exception 'TEST stale grant accepted';
 exception when others then if sqlerrm<>'Комната или разрешение изменились' then raise; end if; end;
 select control_generation into gen from public.loopa_rooms16 where loopa_rooms16.code=test_code;
 begin
  perform public.loopa_control_v2(test_code,'old-video',gen,300,false);
  raise exception 'TEST stale video accepted';
 exception when others then if sqlerrm<>'Комната или разрешение изменились' then raise; end if; end;
end $test$;
