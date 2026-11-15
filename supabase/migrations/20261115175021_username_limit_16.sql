begin;
-- Never truncate or rename existing usernames. Abort on incompatible data.
do $$ begin
 if exists(select 1 from public.profiles where length(username)>16) then
  raise exception 'Existing usernames exceed 16 characters; review before applying';
 end if;
end $$;
alter table public.profiles drop constraint profiles_username_format_v1;
alter table public.profiles add constraint profiles_username_format_v1 check (
 username is null or (username=lower(btrim(username)) and username ~ '^[a-z][a-z0-9_]{3,15}$')
);
comment on column public.profiles.username is
 'Optional public discovery handle: lowercase Latin letter first, letters/digits/underscore; 4 to 16 characters.';
notify pgrst,'reload schema';
commit;
