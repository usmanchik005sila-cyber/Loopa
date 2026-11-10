-- LOOPA user safety: private reports, account deletion requests and a safer
-- default for profiles created after this migration.
-- Existing profile values are intentionally not updated.
begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.profiles') is null then
    raise exception 'LOOPA profiles table is missing; apply the profiles setup first.';
  end if;
  if pg_catalog.to_regclass('public.loopa_dm_messages_v87') is null then
    raise exception 'Apply the LOOPA direct-messages v87 SQL before this safety migration.';
  end if;
end
$preflight$;

-- A column default affects future inserts only. Existing DM choices remain
-- exactly as stored; there is no UPDATE/backfill of profiles here.
alter table public.profiles
  add column if not exists dm_policy text default 'friends';
alter table public.profiles
  alter column dm_policy set default 'friends';

create or replace function public.loopa_dm_policy_new_profile_default_v1()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.dm_policy is null then
    new.dm_policy := 'friends';
  end if;
  return new;
end
$function$;

revoke all on function public.loopa_dm_policy_new_profile_default_v1() from public, anon;
grant execute on function public.loopa_dm_policy_new_profile_default_v1() to authenticated, service_role;
drop trigger if exists loopa_dm_policy_new_profile_default_v1 on public.profiles;
create trigger loopa_dm_policy_new_profile_default_v1
before insert on public.profiles
for each row execute function public.loopa_dm_policy_new_profile_default_v1();

create table if not exists public.loopa_user_reports_v1 (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  reporter_id uuid not null,
  reported_user_id uuid not null,
  message_ref text,
  reason text not null check (reason in ('harassment', 'spam', 'threats', 'scam', 'other')),
  details text,
  status text not null default 'open'
    check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at timestamptz not null default pg_catalog.now(),
  reviewed_at timestamptz,
  check (message_ref is null or pg_catalog.char_length(message_ref) between 1 and 128),
  check (details is null or pg_catalog.char_length(details) <= 500)
);

comment on table public.loopa_user_reports_v1 is
  'Private manual-review queue. No user-facing table access; owner reviews through Supabase SQL Editor.';
comment on column public.loopa_user_reports_v1.message_ref is
  'Reference to an existing DM row. Message text is not copied into the report.';

create unique index if not exists loopa_user_reports_v1_open_user_unique
  on public.loopa_user_reports_v1 (reporter_id, reported_user_id)
  where status = 'open' and message_ref is null;
create unique index if not exists loopa_user_reports_v1_open_message_unique
  on public.loopa_user_reports_v1 (reporter_id, message_ref)
  where status = 'open' and message_ref is not null;
create index if not exists loopa_user_reports_v1_review_queue
  on public.loopa_user_reports_v1 (created_at)
  where status = 'open';

alter table public.loopa_user_reports_v1 enable row level security;
revoke all on table public.loopa_user_reports_v1 from public, anon, authenticated, service_role;

create table if not exists public.loopa_account_deletion_requests_v1 (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'declined')),
  requested_at timestamptz not null default pg_catalog.now(),
  handled_at timestamptz
);

comment on table public.loopa_account_deletion_requests_v1 is
  'Private owner-review queue. A request does not delete an account or its data.';
create unique index if not exists loopa_account_deletion_requests_v1_active_unique
  on public.loopa_account_deletion_requests_v1 (user_id)
  where status in ('pending', 'processing');
create index if not exists loopa_account_deletion_requests_v1_pending_queue
  on public.loopa_account_deletion_requests_v1 (requested_at)
  where status = 'pending';

alter table public.loopa_account_deletion_requests_v1 enable row level security;
revoke all on table public.loopa_account_deletion_requests_v1 from public, anon, authenticated, service_role;

create or replace function public.loopa_submit_user_report(
  p_target_user uuid,
  p_message_ref text,
  p_reason text,
  p_details text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_target uuid;
  v_sender uuid;
  v_recipient uuid;
  v_details text;
  v_report_id uuid;
  v_recent_count integer;
begin
  if v_actor is null then
    raise exception 'login_required';
  end if;
  if p_reason is null or p_reason not in ('harassment', 'spam', 'threats', 'scam', 'other') then
    raise exception 'invalid_report_reason';
  end if;
  if p_details is not null and pg_catalog.char_length(p_details) > 500 then
    raise exception 'report_details_too_long';
  end if;
  v_details := nullif(pg_catalog.btrim(p_details), '');

  if p_message_ref is not null then
    if pg_catalog.char_length(p_message_ref) not between 1 and 128 then
      raise exception 'invalid_message_reference';
    end if;
    select m.sender_id, m.recipient_id
      into v_sender, v_recipient
      from public.loopa_dm_messages_v87 as m
      where m.id::text = p_message_ref
      limit 1;
    if not found or v_recipient <> v_actor or v_sender = v_actor then
      raise exception 'message_not_reportable';
    end if;
    if p_target_user is not null and p_target_user <> v_sender then
      raise exception 'report_target_mismatch';
    end if;
    v_target := v_sender;
  else
    v_target := p_target_user;
    if v_target is null or v_target = v_actor then
      raise exception 'invalid_report_target';
    end if;
    perform 1 from public.profiles as p where p.id = v_target;
    if not found then
      raise exception 'report_target_not_found';
    end if;
  end if;

  select pg_catalog.count(*)::integer
    into v_recent_count
    from public.loopa_user_reports_v1 as r
    where r.reporter_id = v_actor
      and r.created_at > pg_catalog.now() - interval '24 hours';
  if v_recent_count >= 10 then
    raise exception 'report_rate_limit';
  end if;

  insert into public.loopa_user_reports_v1
    (reporter_id, reported_user_id, message_ref, reason, details)
  values
    (v_actor, v_target, p_message_ref, p_reason, v_details)
  on conflict do nothing
  returning id into v_report_id;

  if v_report_id is null then
    if p_message_ref is null then
      select r.id into v_report_id
        from public.loopa_user_reports_v1 as r
        where r.reporter_id = v_actor and r.reported_user_id = v_target
          and r.message_ref is null and r.status = 'open'
        limit 1;
    else
      select r.id into v_report_id
        from public.loopa_user_reports_v1 as r
        where r.reporter_id = v_actor and r.message_ref = p_message_ref
          and r.status = 'open'
        limit 1;
    end if;
    return pg_catalog.jsonb_build_object('status', 'already_open');
  end if;

  return pg_catalog.jsonb_build_object('status', 'submitted');
end
$function$;

create or replace function public.loopa_request_account_deletion()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_request_id uuid;
begin
  if v_actor is null then
    raise exception 'login_required';
  end if;

  select d.id into v_request_id
    from public.loopa_account_deletion_requests_v1 as d
    where d.user_id = v_actor and d.status in ('pending', 'processing')
    order by d.requested_at desc
    limit 1;
  if v_request_id is not null then
    return pg_catalog.jsonb_build_object('status', 'already_pending', 'request_id', v_request_id);
  end if;

  insert into public.loopa_account_deletion_requests_v1 (user_id)
  values (v_actor)
  on conflict do nothing
  returning id into v_request_id;

  if v_request_id is null then
    select d.id into v_request_id
      from public.loopa_account_deletion_requests_v1 as d
      where d.user_id = v_actor and d.status in ('pending', 'processing')
      order by d.requested_at desc
      limit 1;
    return pg_catalog.jsonb_build_object('status', 'already_pending', 'request_id', v_request_id);
  end if;

  return pg_catalog.jsonb_build_object('status', 'submitted', 'request_id', v_request_id);
end
$function$;

revoke all on function public.loopa_submit_user_report(uuid, text, text, text) from public, anon;
grant execute on function public.loopa_submit_user_report(uuid, text, text, text) to authenticated;
revoke all on function public.loopa_request_account_deletion() from public, anon;
grant execute on function public.loopa_request_account_deletion() to authenticated;

commit;
