-- LOOPA automatic account deletion after an explicit in-app confirmation.
-- The Telegram bot is notified; it does not approve or block the deletion.
begin;

do $preflight$
declare
  v_missing text[];
begin
  select array_agg(required.table_name order by required.table_name)
    into v_missing
    from (values
      ('blocked_users'),
      ('friend_requests'),
      ('loopa_account_deletion_requests_v1'),
      ('loopa_bot_subscriptions'),
      ('loopa_chat18'),
      ('loopa_dm_messages_v87'),
      ('loopa_history27'),
      ('loopa_invites25'),
      ('loopa_members16'),
      ('loopa_playback57'),
      ('loopa_rooms16'),
      ('loopa_usage27'),
      ('loopa_usage_v87'),
      ('loopa_user_reports_v1'),
      ('profiles'),
      ('telegram_miniapp_links'),
      ('user_presence')
    ) as required(table_name)
   where pg_catalog.to_regclass('public.' || required.table_name) is null;

  if v_missing is not null then
    raise exception 'LOOPA deletion setup is missing public tables: %',
      pg_catalog.array_to_string(v_missing, ', ');
  end if;
end
$preflight$;

create or replace function public.loopa_account_deletion_process_v1(
  p_action text,
  p_request_id uuid,
  p_actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_status text;
  v_handled_at timestamptz;
  v_telegram_id text;
begin
  if p_request_id is null then
    raise exception 'invalid_deletion_request';
  end if;

  if p_action = 'claim' then
    select d.user_id, d.status, d.handled_at
      into v_user_id, v_status, v_handled_at
      from public.loopa_account_deletion_requests_v1 as d
     where d.id = p_request_id
       and (p_actor is null or d.user_id = p_actor)
       and d.status in ('pending', 'processing')
     for update;

    if not found then
      return pg_catalog.jsonb_build_object('status', 'not_pending');
    end if;

    -- Prevent two simultaneous browser submissions from deleting the same account twice.
    if v_status = 'processing'
       and p_actor is not null
       and v_handled_at > pg_catalog.clock_timestamp() - interval '2 minutes' then
      return pg_catalog.jsonb_build_object('status', 'already_processing');
    end if;

    update public.loopa_account_deletion_requests_v1
       set status = 'processing',
           handled_at = pg_catalog.clock_timestamp()
     where id = p_request_id;

    select l.telegram_id
      into v_telegram_id
      from public.telegram_miniapp_links as l
     where l.user_id = v_user_id;

    return pg_catalog.jsonb_build_object(
      'status', 'processing',
      'request_id', p_request_id,
      'user_id', v_user_id,
      'telegram_id', v_telegram_id,
      'was_processing', v_status = 'processing'
    );
  end if;

  if p_action = 'release' then
    if p_actor is null then
      raise exception 'login_required';
    end if;
    update public.loopa_account_deletion_requests_v1
       set status = 'pending',
           handled_at = null
     where id = p_request_id
       and user_id = p_actor
       and status = 'processing';
    return pg_catalog.jsonb_build_object('status', 'pending');
  end if;

  if p_action = 'purge' then
    select d.user_id
      into v_user_id
      from public.loopa_account_deletion_requests_v1 as d
     where d.id = p_request_id
       and d.status = 'processing'
       and d.user_id is not null
     for update;

    if not found then
      return pg_catalog.jsonb_build_object('status', 'not_processing');
    end if;

    select l.telegram_id
      into v_telegram_id
      from public.telegram_miniapp_links as l
     where l.user_id = v_user_id;

    -- Remove the user from allow-lists in rooms hosted by other members.
    update public.loopa_rooms16
       set allowed = pg_catalog.array_remove(allowed, v_user_id)
     where v_user_id = any(allowed);

    delete from public.blocked_users
     where blocker_id = v_user_id or blocked_id = v_user_id;

    delete from public.friend_requests
     where sender_id = v_user_id or receiver_id = v_user_id;

    delete from public.user_presence
     where user_id = v_user_id;

    delete from public.loopa_dm_messages_v87
     where sender_id = v_user_id or recipient_id = v_user_id;

    delete from public.loopa_invites25
     where sender = v_user_id
        or recipient = v_user_id
        or code in (
          select r.code from public.loopa_rooms16 as r where r.host = v_user_id
        );

    delete from public.loopa_chat18
     where author = v_user_id
        or code in (
          select r.code from public.loopa_rooms16 as r where r.host = v_user_id
        );

    delete from public.loopa_members16
     where member = v_user_id
        or code in (
          select r.code from public.loopa_rooms16 as r where r.host = v_user_id
        );

    -- Hosted rooms cascade their room chat and invitations.
    delete from public.loopa_rooms16
     where host = v_user_id;

    delete from public.loopa_history27
     where owner = v_user_id;

    delete from public.loopa_playback57
     where owner = v_user_id;

    delete from public.loopa_usage27
     where owner = v_user_id;

    delete from public.loopa_usage_v87
     where user_id = v_user_id;

    -- Older projects may not have cloud resume points installed.
    if exists (
      select 1
        from pg_catalog.pg_class as c
        join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname = 'loopa_resume_points'
         and c.relkind in ('r', 'p')
    ) then
      execute 'delete from public.loopa_resume_points where user_id = $1'
        using v_user_id;
    end if;

    delete from public.loopa_user_reports_v1
     where reporter_id = v_user_id or reported_user_id = v_user_id;

    if v_telegram_id is not null then
      delete from public.loopa_bot_subscriptions
       where telegram_id = v_telegram_id;
    end if;

    delete from public.telegram_miniapp_links
     where user_id = v_user_id;

    delete from public.profiles
     where id = v_user_id;

    return pg_catalog.jsonb_build_object(
      'status', 'purged',
      'request_id', p_request_id,
      'user_id', v_user_id,
      'telegram_id', v_telegram_id
    );
  end if;

  if p_action = 'complete' then
    delete from public.loopa_account_deletion_requests_v1
     where id = p_request_id
       and status = 'processing'
       and user_id is not null;

    if not found then
      return pg_catalog.jsonb_build_object('status', 'not_processing');
    end if;
    -- The request row is also removed: no account-linked deletion history is retained.
    return pg_catalog.jsonb_build_object('status', 'completed');
  end if;

  raise exception 'invalid_deletion_action';
end
$function$;

revoke all on function public.loopa_account_deletion_process_v1(text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.loopa_account_deletion_process_v1(text, uuid, uuid)
  to service_role;

comment on function public.loopa_account_deletion_process_v1(text, uuid, uuid) is
  'Private service-role-only account cleanup steps; authenticated users can only start deletion through the verified Edge Function.';

commit;
