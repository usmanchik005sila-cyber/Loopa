-- Run against an isolated database after applying telegram_action_budgets.
begin;

do $test$
begin
  if has_function_privilege('anon', 'public.loopa_take_telegram_action_budget(text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.loopa_take_telegram_action_budget(text,text)', 'EXECUTE') then
    raise exception 'Client roles can spend Telegram budgets';
  end if;
end;
$test$;

set local role service_role;
do $test$
declare
  v_rule record;
begin
  for v_rule in
    select * from (values ('login', 6, 10), ('register', 3, 60), ('link', 3, 60), ('status', 12, 5))
      as rules(action, burst, refill_seconds)
  loop
    for n in 1..v_rule.burst loop
      if public.loopa_take_telegram_action_budget('1234', v_rule.action) is distinct from 0 then
        raise exception 'Request denied before % budget was exhausted', v_rule.action;
      end if;
    end loop;
    if public.loopa_take_telegram_action_budget('1234', v_rule.action) is distinct from v_rule.refill_seconds then
      raise exception 'Exhausted % budget was not denied', v_rule.action;
    end if;
    if public.loopa_take_telegram_action_budget('4321', v_rule.action) is distinct from 0 then
      raise exception 'Another Telegram account shared the % budget', v_rule.action;
    end if;
  end loop;
end;
$test$;

reset role;
update loopa_private.telegram_action_budgets
set budget_until = budget_until - interval '10 seconds'
where telegram_id = '1234' and action = 'login';

set local role service_role;
do $test$
begin
  if public.loopa_take_telegram_action_budget('1234', 'login') is distinct from 0 then
    raise exception 'Refilled request denied';
  end if;
  if public.loopa_take_telegram_action_budget('1234', 'login') is distinct from 10 then
    raise exception 'Refill allowed more than one request';
  end if;
end;
$test$;

rollback;
