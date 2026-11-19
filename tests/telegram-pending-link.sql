-- Run against an isolated database after applying telegram_pending_link.
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', null),
  ('00000000-0000-0000-0000-000000000002', 'existing@example.invalid');

do $test$
begin
  if has_function_privilege('anon', 'public.loopa_telegram_link_step(text,uuid,boolean)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.loopa_telegram_link_step(text,uuid,boolean)', 'EXECUTE')
     or has_table_privilege('service_role', 'loopa_private.telegram_pending_links', 'SELECT') then
    raise exception 'Unexpected permission on pending Telegram links';
  end if;
end;
$test$;

set local role service_role;
do $test$
declare
  v_owner uuid := '00000000-0000-0000-0000-000000000001';
  v_other uuid := '00000000-0000-0000-0000-000000000002';
begin
  if public.loopa_telegram_link_step('1234', v_owner, false) <> 'reserved'
     or public.loopa_telegram_link_step('1234', v_owner, false) <> 'reserved' then
    raise exception 'Reservation was not idempotent';
  end if;
  if public.loopa_telegram_link_step('1234', v_owner, true) <> 'link_unavailable'
     or exists (select 1 from public.telegram_miniapp_links where telegram_id = '1234') then
    raise exception 'Link activated before Auth email was ready';
  end if;
  if public.loopa_telegram_link_step('1234', v_other, false) <> 'telegram_already_linked_to_another_profile'
     or public.loopa_telegram_link_step('4321', v_owner, false) <> 'profile_already_linked_to_another_telegram' then
    raise exception 'Competing reservation was accepted';
  end if;
  begin
    insert into public.telegram_miniapp_links (telegram_id, user_id) values ('1234', v_other);
    raise exception 'Direct registration bypassed pending reservation';
  exception when unique_violation then null;
  end;
end;
$test$;

reset role;
-- Stand in for a successful Auth Admin email update between Edge calls.
update auth.users set email = 'miniapp-1234@auth.loopacinema.invalid'
where id = '00000000-0000-0000-0000-000000000001';

set local role service_role;
do $test$
declare
  v_owner uuid := '00000000-0000-0000-0000-000000000001';
begin
  if public.loopa_telegram_link_step('1234', v_owner, true) <> 'linked'
     or public.loopa_telegram_link_step('1234', v_owner, true) <> 'already_linked' then
    raise exception 'Finalization was not idempotent';
  end if;
  if not exists (select 1 from public.telegram_miniapp_links
                 where telegram_id = '1234' and user_id = v_owner) then
    raise exception 'Active link not saved';
  end if;
end;
$test$;

reset role;
do $test$
begin
  if exists (select 1 from loopa_private.telegram_pending_links where telegram_id = '1234') then
    raise exception 'Finalization left a pending record';
  end if;
end;
$test$;

rollback;
