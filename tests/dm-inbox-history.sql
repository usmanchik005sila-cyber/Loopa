-- Run inside BEGIN/ROLLBACK after the migration. Uses transactional Auth fixtures.
select set_config('loopa_test.owner',gen_random_uuid()::text,true),set_config('loopa_test.a',gen_random_uuid()::text,true),set_config('loopa_test.b',gen_random_uuid()::text,true);
insert into auth.users(id) values(current_setting('loopa_test.owner')::uuid),(current_setting('loopa_test.a')::uuid),(current_setting('loopa_test.b')::uuid);
insert into public.loopa_dm_messages_v87(sender_id,recipient_id,body)
 values(current_setting('loopa_test.owner')::uuid,current_setting('loopa_test.b')::uuid,'archive');
insert into public.loopa_dm_messages_v87(sender_id,recipient_id,body)
 select current_setting('loopa_test.owner')::uuid,current_setting('loopa_test.a')::uuid,'recent '||n from generate_series(1,600)n;
insert into public.loopa_dm_messages_v87(sender_id,recipient_id,body)
 values(current_setting('loopa_test.a')::uuid,current_setting('loopa_test.b')::uuid,'not yours');
select set_config('request.jwt.claim.sub',current_setting('loopa_test.owner'),true);
set local role authenticated;
do $test$
declare cursor_id bigint; n integer;
begin
 select count(*) into n from public.loopa_dm_inbox();
 if n<>2 then raise exception 'Archive missing or foreign conversation exposed'; end if;
 select id into cursor_id from public.loopa_dm_inbox(page_size=>1);
 if not exists(select 1 from public.loopa_dm_inbox(before_id=>cursor_id) where body='archive') then raise exception 'Keyset page missing archive'; end if;
 if exists(select 1 from public.loopa_dm_inbox() where body='not yours') then raise exception 'Foreign data leak'; end if;
 if exists(select 1 from public.loopa_dm_inbox(before_id=>cursor_id) where id=cursor_id) then raise exception 'Cursor duplicate'; end if;
 if has_function_privilege('anon','public.loopa_dm_inbox(bigint,integer)','execute') then raise exception 'Anon access'; end if;
end $test$;
reset role;
