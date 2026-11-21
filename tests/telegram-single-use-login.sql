-- Run against an isolated database after applying telegram_single_use_login.
begin;

do $test$
begin
  if has_function_privilege('anon', 'public.loopa_claim_telegram_login(text,bigint)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.loopa_claim_telegram_login(text,bigint)', 'EXECUTE') then
    raise exception 'Client roles can claim Telegram confirmations';
  end if;
end;
$test$;

set local role service_role;
do $test$
declare
  v_auth_date bigint := floor(extract(epoch from clock_timestamp()));
  v_fingerprint text := repeat('a', 64);
begin
  if public.loopa_claim_telegram_login(v_fingerprint, v_auth_date - 601) is distinct from false
     or public.loopa_claim_telegram_login(v_fingerprint, v_auth_date + 60) is distinct from false
     or public.loopa_claim_telegram_login(null, v_auth_date) is distinct from false then
    raise exception 'Invalid confirmation accepted';
  end if;
  if public.loopa_claim_telegram_login(v_fingerprint, v_auth_date) is distinct from true then
    raise exception 'Fresh confirmation rejected';
  end if;
  if public.loopa_claim_telegram_login(v_fingerprint, v_auth_date) is distinct from false then
    raise exception 'Used confirmation accepted';
  end if;
end;
$test$;

rollback;
