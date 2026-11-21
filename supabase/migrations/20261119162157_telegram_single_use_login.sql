begin;

create table loopa_private.telegram_login_claims (
  fingerprint text primary key check (fingerprint ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null
);
create index telegram_login_claims_expiry
  on loopa_private.telegram_login_claims (expires_at);

alter table loopa_private.telegram_login_claims enable row level security;
revoke all on loopa_private.telegram_login_claims from public, anon, authenticated, service_role;

create function public.loopa_claim_telegram_login(p_fingerprint text, p_auth_date bigint)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_epoch bigint := floor(extract(epoch from v_now));
  v_claimed boolean;
begin
  if p_fingerprint is null or p_fingerprint !~ '^[0-9a-f]{64}$'
     or p_auth_date is null or p_auth_date not between v_epoch - 600 and v_epoch + 30 then
    return false;
  end if;

  insert into loopa_private.telegram_login_claims (fingerprint, expires_at)
  values (p_fingerprint, to_timestamp(p_auth_date + 601))
  on conflict (fingerprint) do nothing;
  v_claimed := found;

  if v_claimed then
    with expired as (
      select fingerprint from loopa_private.telegram_login_claims
      where expires_at <= v_now
      order by expires_at
      limit 64
      for update skip locked
    )
    delete from loopa_private.telegram_login_claims c
    using expired where c.fingerprint = expired.fingerprint;
  end if;
  return v_claimed and clock_timestamp() < to_timestamp(p_auth_date + 601);
end;
$$;

revoke all on function public.loopa_claim_telegram_login(text, bigint) from public, anon, authenticated;
grant execute on function public.loopa_claim_telegram_login(text, bigint) to service_role;

notify pgrst, 'reload schema';
commit;
