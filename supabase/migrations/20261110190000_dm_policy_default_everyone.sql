-- Make new LOOPA profiles open to messages from everyone by default.
-- Existing profile preferences are intentionally not updated.
begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.profiles') is null then
    raise exception 'LOOPA profiles table is missing; apply the profiles setup first.';
  end if;
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'dm_policy'
  ) then
    raise exception 'Apply LOOPA user safety migration before changing the DM default.';
  end if;
end
$preflight$;

alter table public.profiles
  alter column dm_policy set default 'everyone';

create or replace function public.loopa_dm_policy_new_profile_default_v1()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.dm_policy is null then
    new.dm_policy := 'everyone';
  end if;
  return new;
end
$function$;

revoke all on function public.loopa_dm_policy_new_profile_default_v1() from public, anon;
grant execute on function public.loopa_dm_policy_new_profile_default_v1() to authenticated, service_role;
drop trigger if exists loopa_dm_policy_new_profile_default_v1 on public.profiles;
create trigger loopa_dm_policy_new_profile_default_v1
before insert on public.profiles
for each row execute function public.loopa_dm_policy_new_profile_default_v1();

commit;
