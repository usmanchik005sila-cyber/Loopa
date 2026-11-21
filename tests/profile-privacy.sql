-- Run in a transaction and ROLLBACK; fixtures never persist.
select set_config('loopa_test.owner',gen_random_uuid()::text,true),
       set_config('loopa_test.peer',gen_random_uuid()::text,true);
insert into auth.users(id) values(current_setting('loopa_test.owner')::uuid),(current_setting('loopa_test.peer')::uuid);
insert into public.profiles(id,display_name,dm_policy,notification_sound)
 values(current_setting('loopa_test.owner')::uuid,'Privacy Owner','friends',false),
       (current_setting('loopa_test.peer')::uuid,'Privacy Peer','friends',false)
 on conflict(id) do update set display_name=excluded.display_name,dm_policy=excluded.dm_policy,notification_sound=false;
select set_config('request.jwt.claim.sub',current_setting('loopa_test.owner'),true);
set local role authenticated;
do $test$
declare peer uuid:=current_setting('loopa_test.peer')::uuid; own uuid:=auth.uid(); n int; r record;
begin
 select count(*) into n from public.profiles where id=peer;
 if n<>0 then raise exception 'Peer private profile is readable'; end if;
 select count(*) into n from public.profiles where id=own and dm_policy='friends' and not notification_sound;
 if n<>1 then raise exception 'Owner cannot read settings'; end if;
 update public.profiles set notification_sound=true where id=own;
 if not found then raise exception 'Owner cannot update settings'; end if;
 update public.profiles set notification_sound=true where id=peer;
 if found then raise exception 'Peer settings writable'; end if;
 select count(*) into n from public.loopa_profiles_by_ids(array[peer]) where id=peer and display_name='Privacy Peer';
 if n<>1 then raise exception 'Public directory broken'; end if;
 if exists(select 1 from public.loopa_profiles_by_ids(array[peer]) d where to_jsonb(d)?|array['dm_policy','notification_sound','room_invite_policy','allow_friend_requests']) then
  raise exception 'Directory exposes private fields';
 end if;
 insert into public.friend_requests(sender_id,receiver_id) values(own,peer);
 -- DM policy must continue to reject a non-friend.
 begin
  insert into public.loopa_dm_messages_v87(sender_id,recipient_id,body) values(own,peer,'privacy regression');
  raise exception 'TEST DM privacy bypass';
 exception when insufficient_privilege then null;
 end;
 for r in select t,p from unnest(array['profiles','user_presence','friend_requests','loopa_dm_messages_v87'])t
 cross join unnest(array['TRUNCATE','REFERENCES','TRIGGER'])p loop
  if has_table_privilege('authenticated','public.'||r.t,r.p) or has_table_privilege('anon','public.'||r.t,r.p) then
   raise exception 'Excess grant remains: % %',r.t,r.p;
  end if;
 end loop;
end $test$;
reset role;
-- Receiver disables requests; duplicate avoidance is not the reason for denial.
delete from public.friend_requests where sender_id=current_setting('loopa_test.owner')::uuid;
update public.profiles set allow_friend_requests=false where id=current_setting('loopa_test.peer')::uuid;
set local role authenticated;
do $test$
begin
 begin
  insert into public.friend_requests(sender_id,receiver_id) values(auth.uid(),current_setting('loopa_test.peer')::uuid);
  raise exception 'TEST disabled friend request accepted';
 exception when insufficient_privilege then null;
 end;
end $test$;
reset role;
-- Accepted friends can still exchange DMs after private settings are hidden.
update public.profiles set allow_friend_requests=true where id=current_setting('loopa_test.peer')::uuid;
set local role authenticated;
insert into public.friend_requests(sender_id,receiver_id) values(auth.uid(),current_setting('loopa_test.peer')::uuid);
reset role;
select set_config('request.jwt.claim.sub',current_setting('loopa_test.peer'),true);
set local role authenticated;
update public.friend_requests set status='accepted' where sender_id=current_setting('loopa_test.owner')::uuid and receiver_id=auth.uid();
reset role;
select set_config('request.jwt.claim.sub',current_setting('loopa_test.owner'),true);
set local role authenticated;
insert into public.loopa_dm_messages_v87(sender_id,recipient_id,body) values(auth.uid(),current_setting('loopa_test.peer')::uuid,'accepted-friend regression');
select public.loopa_block_user(current_setting('loopa_test.peer')::uuid);
do $test$
begin
 if loopa_private.can_request_friend(current_setting('loopa_test.peer')::uuid) then raise exception 'Blocked friend request allowed'; end if;
 begin
  insert into public.loopa_dm_messages_v87(sender_id,recipient_id,body) values(auth.uid(),current_setting('loopa_test.peer')::uuid,'blocked regression');
  raise exception 'TEST blocked DM accepted';
 exception when insufficient_privilege then null;
 end;
end $test$;
reset role;
set local role anon;
do $test$
begin
 if has_function_privilege('anon','public.loopa_profiles_by_ids(uuid[])','EXECUTE') then
  raise exception 'Unauthenticated directory access';
 end if;
end $test$;
reset role;
