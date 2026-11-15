-- Execute in BEGIN/ROLLBACK; all Auth and resume fixtures are temporary.
select set_config('loopa_test.owner',gen_random_uuid()::text,true),
       set_config('loopa_test.peer',gen_random_uuid()::text,true);
insert into auth.users(id) values(current_setting('loopa_test.owner')::uuid),
 (current_setting('loopa_test.peer')::uuid);
select set_config('request.jwt.claim.sub',current_setting('loopa_test.owner'),true);
set local role authenticated;
-- First device saves; timestamp must come from the server.
insert into public.loopa_resume_points(user_id,media,position_seconds,duration_seconds,updated_at)
 values(auth.uid(),'https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/',123,600,'2099-01-01');
reset role;
-- Second device: same account, new role/session context, no browser-local data.
select set_config('request.jwt.claim.sub',current_setting('loopa_test.owner'),true);
set local role authenticated;
do $test$
declare n integer; k text;
begin
 select count(*) into n from public.loopa_resume_points
  where user_id=auth.uid() and position_seconds=123 and updated_at<=now();
 if n<>1 then raise exception 'Second session cannot read saved position/server timestamp'; end if;
 -- Same video is an upsert, not a duplicate; a deliberate rewind must be saved.
 insert into public.loopa_resume_points(user_id,media,position_seconds,duration_seconds)
 values(auth.uid(),'https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/',60,600)
 on conflict(user_id,media) do update set position_seconds=excluded.position_seconds;
 select count(*) into n from public.loopa_resume_points where user_id=auth.uid() and position_seconds=60;
 if n<>1 then raise exception 'Upsert/rewind failed'; end if;
 begin
  insert into public.loopa_resume_points(user_id,media,position_seconds)
   values(auth.uid(),'invalid-position',-1);
  raise exception 'TEST invalid position accepted';
 exception when check_violation then null;
 end;
 begin
  update public.loopa_resume_points set user_id=current_setting('loopa_test.peer')::uuid where user_id=auth.uid();
  raise exception 'TEST ownership reassignment accepted';
 exception when insufficient_privilege then null;
 end;
 foreach k in array array['TRUNCATE','TRIGGER','REFERENCES'] loop
  if has_table_privilege('authenticated','public.loopa_resume_points',k) then raise exception 'Excess privilege: %',k; end if;
 end loop;
end $test$;
reset role;
-- A different account must neither read, update, delete nor insert for the owner.
select set_config('request.jwt.claim.sub',current_setting('loopa_test.peer'),true);
set local role authenticated;
do $test$
begin
 if exists(select 1 from public.loopa_resume_points where user_id=current_setting('loopa_test.owner')::uuid) then raise exception 'Foreign progress readable'; end if;
 update public.loopa_resume_points set position_seconds=99 where user_id=current_setting('loopa_test.owner')::uuid;
 if found then raise exception 'Foreign progress writable'; end if;
 delete from public.loopa_resume_points where user_id=current_setting('loopa_test.owner')::uuid;
 if found then raise exception 'Foreign progress deletable'; end if;
 begin
  insert into public.loopa_resume_points(user_id,media,position_seconds)
   values(current_setting('loopa_test.owner')::uuid,'foreign-insert',30);
  raise exception 'TEST foreign insert accepted';
 exception when insufficient_privilege then null;
 end;
end $test$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('loopa_test.owner'),true);
set local role authenticated;
delete from public.loopa_resume_points where user_id=auth.uid();
insert into public.loopa_resume_points(media,position_seconds) values('cascade-check',40);
reset role;
-- Deleting an Auth account must remove its resume records automatically.
delete from auth.users where id=current_setting('loopa_test.owner')::uuid;
do $test$
begin
 if exists(select 1 from public.loopa_resume_points where user_id=current_setting('loopa_test.owner')::uuid) then raise exception 'Cascade cleanup failed'; end if;
 if has_table_privilege('anon','public.loopa_resume_points','SELECT')
  or has_table_privilege('anon','public.loopa_resume_points','INSERT') then raise exception 'Unauthenticated API access'; end if;
end $test$;
