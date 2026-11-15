begin;
create or replace function public.loopa_allowed_video_url(value text)
returns boolean language sql immutable set search_path = ''
as $$
 select coalesce(length(value) between 10 and 1500 and (
 value ~ '^https://www\.youtube\.com/embed/[A-Za-z0-9_-]{11}(\?[A-Za-z0-9_.~%=&-]{1,250})?$'
 or value ~ '^https://rutube\.ru/play/embed/[A-Fa-f0-9]{32}/$'
 or value ~ '^https://vkvideo\.ru/video_ext\.php\?oid=-?[0-9]+&id=[0-9]+&js_api=1(&hash=[A-Za-z0-9_.~%!-]{1,250})?$'
 ), false);
$$;
revoke all on function public.loopa_allowed_video_url(text) from public, anon;
grant execute on function public.loopa_allowed_video_url(text) to authenticated;

-- Patch only the validation clause; abort if the current RPC has changed.
do $patch$
declare definition text := pg_get_functiondef('public.loopa_room16(text,text,text,double precision)'::regprocedure);
begin
 if position($old$if op='video' and length(media) not between 10 and 1500 then raise exception 'Проверь ссылку'; end if;$old$ in definition)=0 then
   raise exception 'Unexpected loopa_room16 definition: review migration before applying';
 end if;
 execute replace(definition,$old$if op='video' and length(media) not between 10 and 1500 then raise exception 'Проверь ссылку'; end if;$old$,$new$if op='video' and (media is null or length(media) not between 10 and 1500 or not public.loopa_allowed_video_url(media)) then raise exception 'Разрешены только ссылки YouTube, VK Видео и RUTUBE'; end if;$new$);
end $patch$;
notify pgrst, 'reload schema';
commit;
