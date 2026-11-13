-- LOOPA optional, unique usernames for profile discovery.
-- Existing profiles remain unchanged and may leave username NULL.
begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.profiles') is null then
    raise exception 'LOOPA profiles table is missing; apply the profiles setup first.';
  end if;
end
$preflight$;

alter table public.profiles
  add column if not exists username text;

do $constraint$
begin
  if not exists (
    select 1
      from pg_catalog.pg_constraint
     where conrelid = 'public.profiles'::regclass
       and conname = 'profiles_username_format_v1'
  ) then
    alter table public.profiles
      add constraint profiles_username_format_v1
      check (username is null or (
        username = pg_catalog.lower(pg_catalog.btrim(username))
        and username ~ '^[a-z][a-z0-9_]{3,31}$'
      ));
  end if;
end
$constraint$;

create unique index if not exists profiles_username_unique_v1
  on public.profiles (username)
  where username is not null;

comment on column public.profiles.username is
  'Optional public discovery handle: lowercase Latin letter first, then letters, digits or underscores; 4 to 32 characters.';

notify pgrst, 'reload schema';
commit;
