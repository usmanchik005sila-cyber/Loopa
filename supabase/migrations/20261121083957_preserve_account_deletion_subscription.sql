begin;

alter table public.loopa_account_deletion_requests_v1
  add column telegram_id_at_claim text;

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
    select d.user_id, d.status, d.handled_at, d.telegram_id_at_claim
      into v_user_id, v_status, v_handled_at, v_telegram_id
      from public.loopa_account_deletion_requests_v1 as d
     where d.id = p_request_id
       and (p_actor is null or d.user_id = p_actor)
       and d.status in ('pending', 'processing')
     for update;

    if not found then
      return pg_catalog.jsonb_build_object('status', 'not_pending');
    end if;

    -- Give the active attempt time to finish before either caller can retry.
    if v_status = 'processing'
       and v_handled_at > pg_catalog.clock_timestamp() - interval '2 minutes' then
      return pg_catalog.jsonb_build_object('status', 'already_processing');
    end if;

    if v_telegram_id is null then
      select l.telegram_id into v_telegram_id
      from public.telegram_miniapp_links l where l.user_id = v_user_id;
    end if;

    update public.loopa_account_deletion_requests_v1
       set status = 'processing',
           handled_at = pg_catalog.clock_timestamp(),
           telegram_id_at_claim = v_telegram_id
     where id = p_request_id;

    return pg_catalog.jsonb_build_object(
      'status', 'processing',
      'request_id', p_request_id,
      'user_id', v_user_id,
      'telegram_id', v_telegram_id,
      'was_processing', v_status = 'processing'
    );
  end if;

  if p_action = 'release' then
    update public.loopa_account_deletion_requests_v1
       set status = 'pending',
           handled_at = null,
           telegram_id_at_claim = null
     where id = p_request_id
       and (p_actor is null or user_id = p_actor)
       and status = 'processing';
    return pg_catalog.jsonb_build_object('status', 'pending');
  end if;

  if p_action = 'purge' then
    select d.user_id, d.telegram_id_at_claim
      into v_user_id, v_telegram_id
      from public.loopa_account_deletion_requests_v1 as d
     where d.id = p_request_id
       and d.status = 'processing'
       and d.user_id is not null
     for update;

    if not found then
      return pg_catalog.jsonb_build_object('status', 'not_processing');
    end if;

    if exists (select 1 from auth.users where id = v_user_id) then
      return pg_catalog.jsonb_build_object('status', 'auth_still_active');
    end if;

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
       where telegram_id = v_telegram_id
         and not exists (
           select 1 from public.telegram_miniapp_links l
           where l.telegram_id = v_telegram_id and l.user_id <> v_user_id
         );
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

-- A client holding a still-valid access token cannot recreate avatars during
-- cleanup or after its Auth account has been deleted.
create function loopa_private.avatar_account_accepts_writes()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists(select 1 from auth.users u where u.id = auth.uid())
    and not exists (
      select 1 from public.loopa_account_deletion_requests_v1 d
      where d.user_id = auth.uid() and d.status = 'processing'
    );
$$;
revoke all on function loopa_private.avatar_account_accepts_writes()
  from public, anon, authenticated, service_role;

create function loopa_private.guard_avatar_account_write()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if coalesce(auth.jwt()->>'role', nullif(pg_catalog.current_setting('request.jwt.claim.role', true), '')) = 'authenticated'
     and not loopa_private.avatar_account_accepts_writes() then
    raise insufficient_privilege using message = 'Avatar uploads unavailable';
  end if;
  return new;
end;
$$;
revoke all on function loopa_private.guard_avatar_account_write()
  from public, anon, authenticated, service_role;

create trigger loopa_guard_avatar_account_write
before insert or update on storage.objects
for each row when (new.bucket_id = 'avatars')
execute function loopa_private.guard_avatar_account_write();

commit;
