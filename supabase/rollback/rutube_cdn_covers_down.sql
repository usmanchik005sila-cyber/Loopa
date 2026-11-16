begin;
do $patch$
declare definition text:=pg_get_functiondef('public.loopa_history27(text,text,text,text,text,double precision)'::regprocedure);
begin
 if position($old$if length(picture)>1500 or (picture<>'' and picture !~ '^https://([a-zA-Z0-9-]+\.)*(ytimg\.com|youtube\.com|userapi\.com|vk\.com|vkvideo\.ru|rutube\.ru|rtbcdn\.ru)/') then picture:=''; end if;$old$ in definition)=0 then raise exception 'History validation changed; review before applying'; end if;
 execute replace(definition,$old$if length(picture)>1500 or (picture<>'' and picture !~ '^https://([a-zA-Z0-9-]+\.)*(ytimg\.com|youtube\.com|userapi\.com|vk\.com|vkvideo\.ru|rutube\.ru|rtbcdn\.ru)/') then picture:=''; end if;$old$,$new$if length(picture)>1500 or (picture<>'' and picture !~ '^https://([a-zA-Z0-9-]+\.)*(ytimg\.com|youtube\.com|userapi\.com|vk\.com|vkvideo\.ru|rutube\.ru)/') then picture:=''; end if;$new$);
end $patch$;
notify pgrst,'reload schema';
commit;
