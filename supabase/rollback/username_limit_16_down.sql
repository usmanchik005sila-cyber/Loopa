begin;
alter table public.profiles drop constraint profiles_username_format_v1;
alter table public.profiles add constraint profiles_username_format_v1 check (
 username is null or (username=lower(btrim(username)) and username ~ '^[a-z][a-z0-9_]{3,31}$')
);
comment on column public.profiles.username is 'Optional public discovery handle; 4 to 32 characters.';
notify pgrst,'reload schema';
commit;
