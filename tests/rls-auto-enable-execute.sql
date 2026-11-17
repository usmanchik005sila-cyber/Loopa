-- Run as database owner. Everything created by this probe is rolled back.
begin;
create table public.loopa_rls_security_probe (id integer);
do $$
begin
 if has_function_privilege('anon','public.rls_auto_enable()','EXECUTE')
 or has_function_privilege('authenticated','public.rls_auto_enable()','EXECUTE') then
  raise exception 'Application roles retain privileged event-trigger execution';
 end if;
 if not (select relrowsecurity from pg_class where oid='public.loopa_rls_security_probe'::regclass) then
  raise exception 'Automatic RLS no longer enables protection on newly created tables';
 end if;
end $$;
rollback;
