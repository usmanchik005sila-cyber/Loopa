-- Run inside BEGIN/ROLLBACK; all fixtures are transactional.
do $test$
declare actor uuid:=gen_random_uuid(); other_actor uuid:=gen_random_uuid();
begin
 insert into auth.users(id) values(actor),(other_actor);
 insert into public.profiles(id,display_name,username) values(actor,'Limit test',null) on conflict(id) do nothing;
 update public.profiles set username='u'||substr(replace(actor::text,'-',''),1,15) where id=actor;
 begin
  update public.profiles set username=repeat('a',17) where id=actor;
  raise exception 'TEST 17-character username accepted';
 exception when check_violation then null; end;
 begin
  insert into public.profiles(id,display_name,username)
   values(other_actor,'Duplicate test','u'||substr(replace(actor::text,'-',''),1,15));
  raise exception 'TEST duplicate username accepted';
 exception when unique_violation then null; end;
 update public.profiles set username=null where id=actor;
end $test$;
