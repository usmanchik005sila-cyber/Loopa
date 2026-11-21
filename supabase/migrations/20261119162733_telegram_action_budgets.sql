begin;

create table loopa_private.telegram_action_budgets (
  telegram_id text not null check (telegram_id ~ '^[1-9][0-9]{0,15}$'),
  action text not null check (action in ('login', 'register', 'link', 'status')),
  budget_until timestamptz not null,
  primary key (telegram_id, action)
);
create index telegram_action_budgets_expiry
  on loopa_private.telegram_action_budgets (budget_until);

alter table loopa_private.telegram_action_budgets enable row level security;
revoke all on loopa_private.telegram_action_budgets from public, anon, authenticated, service_role;

-- One request advances the budget by one refill interval. Once the budget is
-- behind wall-clock time, its row can be dropped without refilling early.
create function public.loopa_take_telegram_action_budget(p_telegram_id text, p_action text)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_refill_seconds integer;
  v_burst integer;
  v_refill interval;
begin
  if p_telegram_id is null or p_telegram_id !~ '^[1-9][0-9]{0,15}$' then
    raise exception 'Invalid Telegram account identifier';
  end if;

  case p_action
    when 'login' then v_burst := 6; v_refill_seconds := 10;
    when 'register' then v_burst := 3; v_refill_seconds := 60;
    when 'link' then v_burst := 3; v_refill_seconds := 60;
    when 'status' then v_burst := 12; v_refill_seconds := 5;
    else raise exception 'Invalid Telegram action';
  end case;
  v_refill := make_interval(secs => v_refill_seconds);

  insert into loopa_private.telegram_action_budgets as budgets (telegram_id, action, budget_until)
  values (p_telegram_id, p_action, v_now + v_refill)
  on conflict (telegram_id, action) do update
    set budget_until = greatest(v_now, budgets.budget_until) + v_refill
    where budgets.budget_until <= v_now + (v_burst - 1) * v_refill;

  if not found then
    return v_refill_seconds;
  end if;

  with expired as (
    select telegram_id, action from loopa_private.telegram_action_budgets
    where budget_until <= v_now
    order by budget_until
    limit 32
    for update skip locked
  )
  delete from loopa_private.telegram_action_budgets budgets
  using expired where (budgets.telegram_id, budgets.action) = (expired.telegram_id, expired.action);

  return 0;
end;
$$;

revoke all on function public.loopa_take_telegram_action_budget(text, text) from public, anon, authenticated;
grant execute on function public.loopa_take_telegram_action_budget(text, text) to service_role;

notify pgrst, 'reload schema';
commit;
