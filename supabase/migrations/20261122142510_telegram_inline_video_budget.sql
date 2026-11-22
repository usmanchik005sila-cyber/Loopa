begin;

create table loopa_private.inline_video_budgets (
  bucket text primary key,
  requests integer not null check (requests > 0),
  expires_at timestamptz not null
);
alter table loopa_private.inline_video_budgets enable row level security;
revoke all on loopa_private.inline_video_budgets from public, anon, authenticated, service_role;

create function public.loopa_take_inline_video_budget(p_actor text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_used integer;
begin
  if p_actor is null or p_actor !~ '^[a-f0-9]{64}$' then
    return false;
  end if;
  if exists (
    select 1 from loopa_private.inline_video_budgets
    where bucket = 'daily' and expires_at > v_now and requests >= 30
  ) then
    return false;
  end if;

  insert into loopa_private.inline_video_budgets as budget (bucket, requests, expires_at)
  values (p_actor, 1, v_now + interval '1 minute')
  on conflict (bucket) do update
  set requests = case when budget.expires_at <= v_now then 1 else budget.requests + 1 end,
      expires_at = case when budget.expires_at <= v_now then excluded.expires_at else budget.expires_at end
  where budget.expires_at <= v_now or budget.requests < 8
  returning requests into v_used;
  if not found then
    return false;
  end if;

  insert into loopa_private.inline_video_budgets as budget (bucket, requests, expires_at)
  values ('daily', 1, date_trunc('day', v_now, 'UTC') + interval '24 hours')
  on conflict (bucket) do update
  set requests = case when budget.expires_at <= v_now then 1 else budget.requests + 1 end,
      expires_at = case when budget.expires_at <= v_now then excluded.expires_at else budget.expires_at end
  where budget.expires_at <= v_now or budget.requests < 30
  returning requests into v_used;
  if not found then
    return false;
  end if;

  -- Clean up only expired rows without blocking concurrent Telegram queries.
  delete from loopa_private.inline_video_budgets
    where bucket in (
      select bucket from loopa_private.inline_video_budgets
      where expires_at < v_now and bucket <> 'daily'
      order by expires_at limit 64 for update skip locked
    );
  return true;
end;
$$;
revoke all on function public.loopa_take_inline_video_budget(text) from public, anon, authenticated;
grant execute on function public.loopa_take_inline_video_budget(text) to service_role;

commit;
