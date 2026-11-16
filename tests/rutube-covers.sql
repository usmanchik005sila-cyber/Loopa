-- Run inside BEGIN/ROLLBACK after migration. Fixtures do not persist.
do $test$
declare actor uuid:=gen_random_uuid(); room_id text; v text:='https://rutube.ru/play/embed/75a422e3c56aa800c252411c07752204/'; img text;
begin
 insert into auth.users(id) values(actor);
 perform set_config('request.jwt.claim.sub',actor::text,true);
 room_id:=public.loopa_room16(op=>'create')->>'code';
 perform public.loopa_room16(op=>'video',room=>room_id,media=>v);
 perform public.loopa_history27(op=>'meta',room_code=>room_id,media=>v,caption=>'Cover test',picture=>'https://pic.rtbcdn.ru/video/cover.jpg');
 select image into img from public.loopa_titles26 where code=room_id;
 if img<>'https://pic.rtbcdn.ru/video/cover.jpg' then raise exception 'RUTUBE CDN cover discarded'; end if;
 -- Change video first so invalid metadata cannot inherit an existing safe cover.
 perform public.loopa_room16(op=>'video',room=>room_id,media=>'https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/');
 perform public.loopa_history27(op=>'meta',room_code=>room_id,media=>'https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/',caption=>'Unsafe cover',picture=>'https://rtbcdn.ru.evil.test/cover.jpg');
 select image into img from public.loopa_titles26 where code=room_id;
 if img<>'' then raise exception 'Foreign cover domain accepted'; end if;
end $test$;
