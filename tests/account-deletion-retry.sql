-- Run in an isolated database with the account deletion migrations applied.
begin;
do $test$
declare
  deleted_user uuid := gen_random_uuid();
  active_user uuid := gen_random_uuid();
  removal_request uuid := gen_random_uuid();
  other_request uuid := gen_random_uuid();
  tg_id text := '27301';
  result jsonb;
begin
  insert into auth.users(id) values(deleted_user),(active_user);
  insert into public.profiles(id,display_name) values(deleted_user,'Delete fixture'),(active_user,'Keep fixture');
  insert into public.telegram_miniapp_links(telegram_id,user_id) values(tg_id,deleted_user);
  insert into public.loopa_bot_subscriptions(telegram_id,enabled) values(tg_id,true);
  insert into public.loopa_account_deletion_requests_v1(id,user_id) values(removal_request,deleted_user),(other_request,active_user);

  perform set_config('request.jwt.claim.sub',deleted_user::text,true);
  if not loopa_private.avatar_account_accepts_writes() then raise exception 'Active owner cannot upload'; end if;
  result := public.loopa_account_deletion_process_v1('claim',removal_request,active_user);
  if result->>'status' is distinct from 'not_pending' then raise exception 'Another profile claimed a request'; end if;

  result := public.loopa_account_deletion_process_v1('claim',removal_request,deleted_user);
  if result->>'telegram_id' is distinct from tg_id or loopa_private.avatar_account_accepts_writes() then
    raise exception 'Claim lost Telegram identity or allowed an avatar write';
  end if;
  result := public.loopa_account_deletion_process_v1('claim',removal_request,null);
  if result->>'status' is distinct from 'already_processing' then raise exception 'Concurrent owner attempt was accepted'; end if;
  result := public.loopa_account_deletion_process_v1('purge',removal_request,null);
  if result->>'status' is distinct from 'auth_still_active' then raise exception 'Active Auth account was purged'; end if;

  delete from auth.users where id=deleted_user;
  if exists(select 1 from public.telegram_miniapp_links where user_id=deleted_user) then raise exception 'Fixture did not cascade link'; end if;
  if loopa_private.avatar_account_accepts_writes() then raise exception 'Deleted owner can still upload'; end if;
  update public.loopa_account_deletion_requests_v1 set handled_at=clock_timestamp()-interval '3 minutes' where id=removal_request;
  result := public.loopa_account_deletion_process_v1('claim',removal_request,null);
  if result->>'telegram_id' is distinct from tg_id then raise exception 'Retry lost the Telegram identity'; end if;
  result := public.loopa_account_deletion_process_v1('purge',removal_request,null);
  if result->>'status' is distinct from 'purged' or exists(select 1 from public.loopa_bot_subscriptions where telegram_id=tg_id) then
    raise exception 'Retry did not clear the Telegram subscription';
  end if;
  perform public.loopa_account_deletion_process_v1('complete',removal_request,null);
  if exists(select 1 from public.loopa_account_deletion_requests_v1 where id=removal_request)
     or not exists(select 1 from public.profiles where id=active_user) then
    raise exception 'Cleanup affected the wrong record';
  end if;
end $test$;
rollback;
