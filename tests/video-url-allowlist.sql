-- Run inside BEGIN/ROLLBACK after the migration; creates only transactional fixtures.
do $test$
declare actor uuid:=gen_random_uuid(); code text; address text;
begin
 insert into auth.users(id) values(actor);
 perform set_config('request.jwt.claim.sub',actor::text,true);
 code:=public.loopa_room16(op=>'create')->>'code';
 foreach address in array array[
 'https://www.youtube.com/embed/dQw4w9WgXcQ?enablejsapi=1&playsinline=1&controls=1&fs=1&origin=https%3A%2F%2Floopacinema.ru',
 'https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/',
 'https://vkvideo.ru/video_ext.php?oid=-123&id=456&js_api=1&hash=abc'
 ] loop
  if not public.loopa_allowed_video_url(address) then raise exception 'Valid URL rejected: %',address; end if;
  perform public.loopa_room16(op=>'video',room=>code,media=>address);
 end loop;
 foreach address in array array[
 'https://evil.example/embed/12345678901',
 'https://www.youtube.com.evil.example/embed/dQw4w9WgXcQ',
 'https://www.youtube.com@evil.example/embed/dQw4w9WgXcQ',
 'javascript:alert(1)',null,'','http://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/',
 'https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/#bad'
 ] loop
  if public.loopa_allowed_video_url(address) then raise exception 'Unsafe URL accepted'; end if;
  begin
   perform public.loopa_room16(op=>'video',room=>code,media=>address);
   raise exception 'TEST unsafe URL accepted by RPC';
  exception when others then
   if sqlerrm <> 'Разрешены только ссылки YouTube, VK Видео и RUTUBE' then raise; end if;
  end;
 end loop;
 perform public.loopa_room16(op=>'read',room=>code);
 perform public.loopa_room16(op=>'play',room=>code,seconds=>12);
 perform public.loopa_room16(op=>'pause',room=>code,seconds=>13);
 perform public.loopa_room16(op=>'chat',room=>code,media=>'allowlist regression test');
end $test$;
