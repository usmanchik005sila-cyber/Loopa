-- Baseline through hosted migration 20261121140032. Apply only to an empty staging database.

BEGIN;

SET LOCAL check_function_bodies = off;

SET LOCAL search_path = public, extensions;

DO $bootstrap$
BEGIN
  IF to_regnamespace('loopa_private') IS NOT NULL
     OR to_regclass('public.profiles') IS NOT NULL
     OR to_regclass('public.loopa_rooms16') IS NOT NULL
     OR EXISTS (SELECT FROM auth.users)
     OR EXISTS (SELECT FROM storage.buckets WHERE id = 'avatars') THEN
    RAISE EXCEPTION 'LOOPA bootstrap requires an empty application database';
  END IF;
END;
$bootstrap$;

CREATE SCHEMA loopa_private;

REVOKE ALL ON SCHEMA public, loopa_private FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE "loopa_private"."request_budgets" (
  "user_id" uuid NOT NULL,
  "scope" text NOT NULL,
  "tokens" double precision NOT NULL,
  "updated_at" timestamp with time zone NOT NULL
);

ALTER TABLE "loopa_private"."request_budgets" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "loopa_private"."telegram_action_budgets" (
  "telegram_id" text NOT NULL,
  "action" text NOT NULL,
  "budget_until" timestamp with time zone NOT NULL
);

ALTER TABLE "loopa_private"."telegram_action_budgets" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "loopa_private"."telegram_finished_registrations" (
  "user_id" uuid NOT NULL
);

ALTER TABLE "loopa_private"."telegram_finished_registrations" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "loopa_private"."telegram_login_claims" (
  "fingerprint" text NOT NULL,
  "expires_at" timestamp with time zone NOT NULL
);

ALTER TABLE "loopa_private"."telegram_login_claims" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "loopa_private"."telegram_pending_links" (
  "telegram_id" text NOT NULL,
  "user_id" uuid NOT NULL,
  "started_at" timestamp with time zone NOT NULL DEFAULT clock_timestamp()
);

ALTER TABLE "loopa_private"."telegram_pending_links" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "loopa_private"."telegram_profile_imports" (
  "user_id" uuid NOT NULL
);

ALTER TABLE "loopa_private"."telegram_profile_imports" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."blocked_users" (
  "blocker_id" uuid NOT NULL,
  "blocked_id" uuid NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE "public"."blocked_users" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."friend_requests" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "sender_id" uuid NOT NULL,
  "receiver_id" uuid NOT NULL,
  "status" text NOT NULL DEFAULT 'pending'::text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "responded_at" timestamp with time zone
);

ALTER TABLE "public"."friend_requests" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_account_deletion_requests_v1" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "status" text NOT NULL DEFAULT 'pending'::text,
  "requested_at" timestamp with time zone NOT NULL DEFAULT now(),
  "handled_at" timestamp with time zone,
  "telegram_id_at_claim" text
);

ALTER TABLE "public"."loopa_account_deletion_requests_v1" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_bot_subscriptions" (
  "telegram_id" text NOT NULL,
  "enabled" boolean NOT NULL DEFAULT true,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE "public"."loopa_bot_subscriptions" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_chat18" (
  "id" bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
  "code" text,
  "author" uuid,
  "body" text NOT NULL,
  "sent" timestamp with time zone DEFAULT now()
);

ALTER TABLE "public"."loopa_chat18" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_dm_messages_v87" (
  "id" bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
  "sender_id" uuid NOT NULL,
  "recipient_id" uuid NOT NULL,
  "body" text NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE "public"."loopa_dm_messages_v87" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_history27" (
  "owner" uuid NOT NULL,
  "video" text NOT NULL,
  "code" text NOT NULL,
  "title" text NOT NULL,
  "image" text NOT NULL DEFAULT ''::text,
  "seen" timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE "public"."loopa_history27" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_invites25" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "code" text NOT NULL,
  "sender" uuid NOT NULL,
  "recipient" uuid NOT NULL,
  "sent" timestamp with time zone NOT NULL DEFAULT now(),
  "status" text NOT NULL DEFAULT 'pending'::text,
  "notified_sent" timestamp with time zone,
  "bot_notified_sent" timestamp with time zone
);

ALTER TABLE "public"."loopa_invites25" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_members16" (
  "code" text NOT NULL,
  "member" uuid NOT NULL,
  "seen" timestamp with time zone
);

ALTER TABLE "public"."loopa_members16" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_playback57" (
  "code" text NOT NULL,
  "video" text NOT NULL,
  "pos" double precision NOT NULL,
  "playing" boolean NOT NULL,
  "stamp" timestamp with time zone NOT NULL,
  "owner" uuid NOT NULL
);

ALTER TABLE "public"."loopa_playback57" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_resume_points" (
  "user_id" uuid NOT NULL DEFAULT auth.uid(),
  "media" text NOT NULL,
  "position_seconds" integer NOT NULL,
  "duration_seconds" integer NOT NULL DEFAULT 0,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE "public"."loopa_resume_points" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_rooms16" (
  "code" text NOT NULL DEFAULT upper("left"(replace((gen_random_uuid())::text, '-'::text, ''::text), 12)),
  "host" uuid NOT NULL,
  "video" text NOT NULL DEFAULT ''::text,
  "playing" boolean NOT NULL DEFAULT false,
  "pos" double precision NOT NULL DEFAULT 0,
  "changed" timestamp with time zone NOT NULL DEFAULT now(),
  "access_mode" text NOT NULL DEFAULT 'code'::text,
  "allowed" uuid[] NOT NULL DEFAULT '{}'::uuid[],
  "shared_control" boolean NOT NULL DEFAULT false,
  "control_seq" bigint NOT NULL DEFAULT 0,
  "control_applied_seq" bigint NOT NULL DEFAULT 0,
  "control_pos" double precision,
  "control_playing" boolean,
  "control_video" text NOT NULL DEFAULT ''::text,
  "control_at" timestamp with time zone,
  "control_actor" uuid,
  "shared_control_video" text NOT NULL DEFAULT ''::text,
  "shared_control_until" timestamp with time zone,
  "control_generation" bigint NOT NULL DEFAULT 0
);

ALTER TABLE "public"."loopa_rooms16" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_titles26" (
  "code" text NOT NULL,
  "video" text NOT NULL,
  "title" text NOT NULL,
  "image" text NOT NULL DEFAULT ''::text
);

ALTER TABLE "public"."loopa_titles26" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_usage27" (
  "owner" uuid NOT NULL,
  "total_seconds" double precision NOT NULL DEFAULT 0,
  "tick" timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE "public"."loopa_usage27" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_usage_v87" (
  "user_id" uuid NOT NULL,
  "total_seconds" bigint NOT NULL DEFAULT 0,
  "last_ping_at" timestamp with time zone,
  "history_synced" boolean NOT NULL DEFAULT false
);

ALTER TABLE "public"."loopa_usage_v87" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."loopa_user_reports_v1" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "reporter_id" uuid NOT NULL,
  "reported_user_id" uuid NOT NULL,
  "message_ref" text,
  "reason" text NOT NULL,
  "details" text,
  "status" text NOT NULL DEFAULT 'open'::text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "reviewed_at" timestamp with time zone
);

ALTER TABLE "public"."loopa_user_reports_v1" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."profiles" (
  "id" uuid NOT NULL,
  "display_name" text NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  "avatar_path" text,
  "allow_friend_requests" boolean NOT NULL DEFAULT true,
  "room_invite_policy" text NOT NULL DEFAULT 'friends'::text,
  "dm_policy" text NOT NULL DEFAULT 'everyone'::text,
  "notification_sound" boolean NOT NULL DEFAULT true,
  "username" text
);

ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."telegram_miniapp_links" (
  "telegram_id" text NOT NULL,
  "user_id" uuid NOT NULL,
  "linked_at" timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE "public"."telegram_miniapp_links" ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."user_presence" (
  "user_id" uuid NOT NULL,
  "visible" boolean NOT NULL DEFAULT true,
  "last_active_at" timestamp with time zone NOT NULL DEFAULT now(),
  "share_room_activity" boolean NOT NULL DEFAULT true
);

ALTER TABLE "public"."user_presence" ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION loopa_private.avatar_account_accepts_writes()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from auth.users u where u.id = auth.uid())
    and not exists (
      select 1 from public.loopa_account_deletion_requests_v1 d
      where d.user_id = auth.uid() and d.status = 'processing'
    );
$function$;

CREATE OR REPLACE FUNCTION loopa_private.can_request_friend(target uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select (select auth.uid()) is not null and target<>(select auth.uid())
 and exists(select 1 from public.profiles p where p.id=target and p.allow_friend_requests)
 and not public.loopa_pair_is_blocked((select auth.uid()),target);
$function$;

CREATE OR REPLACE FUNCTION loopa_private.consume_budget(p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid(); v_capacity double precision; v_rate double precision;
 v_tokens double precision; v_updated timestamptz; v_now timestamptz;
begin
 if v_user is null then raise exception 'Войди в аккаунт'; end if;
 case p_scope
  when 'message' then v_capacity:=8; v_rate:=1;
  when 'room_create' then v_capacity:=5; v_rate:=1.0/12;
  when 'friend_request' then v_capacity:=5; v_rate:=1.0/12;
  when 'room_invite' then v_capacity:=20; v_rate:=1.0/3;
  when 'user_search' then v_capacity:=10; v_rate:=1.0/3;
  when 'search' then v_capacity:=10; v_rate:=1.0/3;
  when 'suggest' then v_capacity:=30; v_rate:=10;
  else raise exception 'Неизвестный лимит';
 end case;
 insert into loopa_private.request_budgets(user_id,scope,tokens,updated_at)
 values(v_user,p_scope,v_capacity,clock_timestamp()) on conflict do nothing;
 select tokens,updated_at into v_tokens,v_updated
 from loopa_private.request_budgets where user_id=v_user and scope=p_scope for update;
 v_now:=clock_timestamp();
 v_tokens:=least(v_capacity,v_tokens+greatest(0,extract(epoch from v_now-v_updated))*v_rate);
 if v_tokens<1 then
  update loopa_private.request_budgets set tokens=v_tokens,updated_at=v_now
  where user_id=v_user and scope=p_scope;
  return jsonb_build_object('allowed',false,'retry_after',greatest(1,ceil((1-v_tokens)/v_rate)::integer));
 end if;
 update loopa_private.request_budgets set tokens=v_tokens-1,updated_at=v_now
 where user_id=v_user and scope=p_scope;
 return jsonb_build_object('allowed',true,'retry_after',0);
end $function$;

CREATE OR REPLACE FUNCTION loopa_private.find_telegram_registration(p_telegram_id text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select u.id from auth.users u
  where u.email = 'miniapp-' || p_telegram_id || '@auth.loopacinema.invalid'
    and u.raw_app_meta_data->>'loopa_telegram_registration' = p_telegram_id
    and u.email_confirmed_at is not null
    and not exists (select 1 from loopa_private.telegram_finished_registrations f where f.user_id = u.id);
$function$;

CREATE OR REPLACE FUNCTION loopa_private.guard_avatar_account_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if coalesce(auth.jwt()->>'role', nullif(pg_catalog.current_setting('request.jwt.claim.role', true), '')) = 'authenticated'
     and not loopa_private.avatar_account_accepts_writes() then
    raise insufficient_privilege using message = 'Avatar uploads unavailable';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION loopa_private.guard_telegram_link_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if nullif(old.email, '') is not null
     or new.email <> 'miniapp-link-' || new.id::text || '@auth.loopacinema.invalid'
     or not exists (select 1 from loopa_private.telegram_pending_links p where p.user_id = new.id) then
    raise check_violation using message = 'Telegram link email update rejected';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION loopa_private.guard_telegram_link_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_candidate uuid;
begin
  perform loopa_private.lock_telegram_link(new.telegram_id, new.user_id);
  v_candidate := loopa_private.find_telegram_registration(new.telegram_id);
  if v_candidate is not null and v_candidate <> new.user_id then
    raise unique_violation using message = 'Telegram registration already started';
  end if;
  if exists (
    select 1 from loopa_private.telegram_pending_links p
    where (p.telegram_id = new.telegram_id or p.user_id = new.user_id)
      and (p.telegram_id, p.user_id) <> (new.telegram_id, new.user_id)
  ) then
    raise unique_violation using message = 'Telegram link reserved';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION loopa_private.guard_telegram_registration_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_telegram_id text := substring(new.email from '^miniapp-([1-9][0-9]{0,15})@auth[.]loopacinema[.]invalid$');
begin
  if v_telegram_id is null then return new; end if;

  perform pg_advisory_xact_lock(171406, hashtext(v_telegram_id));
  if exists (select 1 from public.telegram_miniapp_links l where l.telegram_id = v_telegram_id)
     or exists (select 1 from loopa_private.telegram_pending_links p where p.telegram_id = v_telegram_id) then
    raise unique_violation using message = 'Telegram account already reserved';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION loopa_private.limit_insert_budget()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb; v_scope text;
begin
 -- Trusted maintenance without an end-user JWT is unaffected.
 if auth.uid() is null then return new; end if;
 v_scope:=case tg_table_name
  when 'loopa_rooms16' then 'room_create'
  when 'friend_requests' then 'friend_request'
  when 'loopa_invites25' then 'room_invite'
  else 'message'
 end;
 v_result:=loopa_private.consume_budget(v_scope);
 if not (v_result->>'allowed')::boolean then
  raise exception using errcode='P0001',message=case v_scope
   when 'message' then 'Слишком много сообщений. Подожди немного и отправь снова.'
   when 'friend_request' then 'Слишком много заявок в друзья. Подожди немного и попробуй снова.'
   when 'room_invite' then 'Слишком много приглашений. Подожди немного и попробуй снова.'
   else 'Слишком часто создаёшь комнаты. Подожди немного и попробуй снова.'
  end;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION loopa_private.lock_telegram_link(p_telegram_id text, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform pg_advisory_xact_lock(171406, hashtext(p_telegram_id));
  perform pg_advisory_xact_lock(171407, hashtext(p_user_id::text));
end;
$function$;

CREATE OR REPLACE FUNCTION loopa_private.loopa_collab27(action text, room_code text, enabled boolean DEFAULT NULL::boolean, position_seconds double precision DEFAULT NULL::double precision, is_playing boolean DEFAULT NULL::boolean, sequence bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  room_row public.loopa_rooms16;
  v_code text := upper(trim(room_code));
  new_seq bigint;
begin
  if actor is null then raise exception 'Войди в аккаунт'; end if;
  select * into room_row from public.loopa_rooms16 r where r.code=v_code for update;
  if room_row.code is null then raise exception 'Комната недоступна'; end if;
  if public.loopa_pair_is_blocked(actor,room_row.host) then raise exception 'Комната недоступна'; end if;
  if room_row.host <> actor and (
    (room_row.access_mode='private' and not(actor=any(room_row.allowed)))
    or (room_row.access_mode='friends' and not exists(
      select 1 from public.friend_requests f where f.status='accepted'
      and ((f.sender_id=actor and f.receiver_id=room_row.host)
        or (f.receiver_id=actor and f.sender_id=room_row.host))
    ))
  ) then raise exception 'Нет доступа'; end if;
  if not exists (
    select 1 from public.loopa_members16 m
    where m.code=v_code and m.member=actor and m.seen>now()-interval '45 seconds'
  ) then raise exception 'Нет активного участия в комнате'; end if;

  if action='mode' then
    if room_row.host<>actor or enabled is null then raise exception 'Управлять режимом может только создатель'; end if;
    update public.loopa_rooms16 r
      set shared_control=enabled,
          shared_control_video=case when enabled then r.video else '' end,
          shared_control_until=case when enabled then clock_timestamp()+interval '30 seconds' else null end,
          control_applied_seq=r.control_seq
      where r.code=v_code;
    return jsonb_build_object('shared_control',enabled,'shared_control_video',
      case when enabled then room_row.video else '' end,'shared_control_until',
      case when enabled then clock_timestamp()+interval '30 seconds' else null end);
  elsif action='renew' then
    if room_row.host<>actor then raise exception 'Только создатель продлевает разрешение'; end if;
    if room_row.shared_control and room_row.shared_control_until>clock_timestamp()
       and room_row.shared_control_video=room_row.video then
      update public.loopa_rooms16 r
        set shared_control_until=clock_timestamp()+interval '30 seconds'
        where r.code=v_code;
      return jsonb_build_object('shared_control',true,
        'shared_control_until',clock_timestamp()+interval '30 seconds');
    end if;
    return jsonb_build_object('shared_control',false);
  elsif action='control' then
    if room_row.host=actor then raise exception 'Создатель использует штатное управление'; end if;
    if not room_row.shared_control or room_row.video=''
       or room_row.shared_control_video<>room_row.video
       or room_row.shared_control_until is null
       or room_row.shared_control_until<=clock_timestamp()
       or not exists(select 1 from public.loopa_members16 m
         where m.code=v_code and m.member=room_row.host
         and m.seen>clock_timestamp()-interval '30 seconds')
    then raise exception 'Совместное управление выключено'; end if;
    if position_seconds is null or position_seconds not between 0 and 864000 or is_playing is null then
      raise exception 'Некорректная позиция';
    end if;
    new_seq:=room_row.control_seq+1;
    update public.loopa_rooms16 r
      set control_seq=new_seq,control_pos=position_seconds,control_playing=is_playing,
          control_video=room_row.video,control_actor=actor,control_at=clock_timestamp(),
          pos=position_seconds,playing=is_playing,changed=clock_timestamp()
      where r.code=v_code;
    insert into public.loopa_playback57(code,video,pos,playing,stamp,owner)
      values(v_code,room_row.video,position_seconds,is_playing,clock_timestamp(),room_row.host)
      on conflict(code) do update set
        video=excluded.video,pos=excluded.pos,playing=excluded.playing,
        stamp=excluded.stamp,owner=excluded.owner;
    return jsonb_build_object('ok',true,'seq',new_seq,'pos',position_seconds,'playing',is_playing);
  elsif action='pull' then
    if room_row.host<>actor then raise exception 'Только создатель получает команды'; end if;
    if room_row.shared_control and room_row.shared_control_until>clock_timestamp()
       and room_row.shared_control_video=room_row.video
       and room_row.video<>'' and room_row.control_video=room_row.video
       and room_row.control_seq>room_row.control_applied_seq then
      return jsonb_build_object('pending',true,'seq',room_row.control_seq,
        'video',room_row.control_video,'pos',room_row.control_pos,'playing',room_row.control_playing);
    end if;
    return jsonb_build_object('pending',false);
  elsif action='ack' then
    if room_row.host<>actor then raise exception 'Только создатель подтверждает команды'; end if;
    if sequence is null or sequence<1 then raise exception 'Некорректный номер команды'; end if;
    if room_row.shared_control and room_row.shared_control_until>clock_timestamp()
       and room_row.shared_control_video=room_row.video
       and room_row.video=room_row.control_video
       and room_row.control_seq=sequence and room_row.control_applied_seq<sequence then
      update public.loopa_rooms16 r set control_applied_seq=sequence where r.code=v_code;
      return jsonb_build_object('applied',true,'seq',sequence);
    end if;
    return jsonb_build_object('applied',false,'seq',room_row.control_seq);
  else
    raise exception 'Неизвестная команда';
  end if;
end
$function$;

CREATE OR REPLACE FUNCTION loopa_private.seed_telegram_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_name text;
  v_username text;
  v_avatar text;
begin
  select left(btrim(u.raw_user_meta_data->>'display_name'), 40),
         u.raw_app_meta_data->>'loopa_telegram_username'
    into v_name, v_username
  from auth.users u
  where u.id = new.user_id
    and u.raw_app_meta_data->>'loopa_telegram_registration' = new.telegram_id
    and u.raw_app_meta_data->'loopa_telegram_profile_seed' = 'true'::jsonb;
  if not found then return new; end if;

  v_name := coalesce(nullif(v_name, ''), 'Участник LOOPA');
  if v_username !~ '^[a-z][a-z0-9_]{3,15}$' then v_username := null; end if;
  select o.name into v_avatar from storage.objects o
  where o.bucket_id = 'avatars' and o.name = new.user_id::text || '/telegram-avatar.jpg';

  -- A conflicting username falls back to a blank field; the user can pick
  -- another one. An already existing profile always wins.
  insert into public.profiles(id, display_name, username, avatar_path)
  values (new.user_id, v_name, v_username, v_avatar)
  on conflict do nothing;
  if not found and v_username is not null then
    insert into public.profiles(id, display_name, avatar_path)
    values (new.user_id, v_name, v_avatar)
    on conflict (id) do nothing;
  end if;
  insert into loopa_private.telegram_profile_imports(user_id)
  values(new.user_id) on conflict do nothing;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_account_deletion_process_v1(p_action text, p_request_id uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.loopa_activity26(action text, peer uuid DEFAULT NULL::uuid, room_code text DEFAULT ''::text, media text DEFAULT ''::text, title text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  u uuid := auth.uid();
  chosen public.loopa_rooms16;
begin
  if u is null then raise exception 'Войди в аккаунт'; end if;

  if action = 'title' then
    select * into chosen from public.loopa_rooms16 where code = room_code for update;
    if chosen.host is distinct from u or chosen.video <> media
       or length(trim(title)) not between 1 and 200 then
      raise exception 'Нет доступа';
    end if;
    insert into public.loopa_titles26 values(room_code, media, trim(title))
    on conflict(code) do update set video = excluded.video, title = excluded.title;
    return '{}'::jsonb;
  elsif action = 'friends' then
    return coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'private', not access.can_view,
        'state', case when access.can_view and rm.video <> '' then 'watching' else 'in_room' end,
        'title', case when access.can_view and rm.video <> '' then coalesce(t.title, 'Видео') end
      ))
      from public.profiles p
      join lateral (
        select r.* from public.loopa_members16 m
        join public.loopa_rooms16 r on r.code = m.code
        where m.member = p.id and m.seen > now() - interval '25 seconds'
          and not public.loopa_pair_is_blocked(u, r.host)
        order by m.seen desc limit 1
      ) rm on true
      cross join lateral (
        select case
          when rm.host = u or rm.access_mode = 'code' then true
          when rm.access_mode = 'private' then coalesce(u = any(rm.allowed), false)
          when rm.access_mode = 'friends' then exists (
            select 1 from public.friend_requests f where f.status = 'accepted'
              and ((f.sender_id = u and f.receiver_id = rm.host)
                or (f.sender_id = rm.host and f.receiver_id = u))
          )
          else false
        end as can_view
      ) access
      left join public.loopa_titles26 t on t.code = rm.code and t.video = rm.video
      where p.id <> u and not public.loopa_pair_is_blocked(u, p.id)
        and exists (
          select 1 from public.user_presence pr
          where pr.user_id = p.id and pr.visible and pr.share_room_activity
        )
        and exists (
          select 1 from public.friend_requests f where f.status = 'accepted'
            and ((f.sender_id = u and f.receiver_id = p.id)
              or (f.sender_id = p.id and f.receiver_id = u))
        )
    ), '[]'::jsonb);
  elsif action = 'join' then
    if peer is null or public.loopa_pair_is_blocked(u, peer)
       or not exists (
         select 1 from public.friend_requests f where f.status = 'accepted'
           and ((f.sender_id = u and f.receiver_id = peer)
             or (f.sender_id = peer and f.receiver_id = u))
       )
       or not exists (
         select 1 from public.user_presence pr
         where pr.user_id = peer and pr.visible and pr.share_room_activity
       ) then
      raise exception 'Просмотр недоступен';
    end if;
    select r.* into chosen from public.loopa_members16 m
    join public.loopa_rooms16 r on r.code = m.code
    where m.member = peer and m.seen > now() - interval '25 seconds' and r.video <> ''
    order by m.seen desc limit 1;
    if chosen.code is null then raise exception 'Друг уже завершил просмотр'; end if;
    if chosen.access_mode = 'private' and chosen.host <> u
       and not coalesce(u = any(chosen.allowed), false) then
      raise exception 'Друг смотрит в приватной комнате. Войти можно по приглашению';
    end if;
    return public.loopa_room16('join', chosen.code);
  end if;
  raise exception 'Неизвестная команда';
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_allowed_video_url(value text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select coalesce(length(value) between 10 and 1500 and (
 value ~ '^https://www\.youtube\.com/embed/[A-Za-z0-9_-]{11}(\?[A-Za-z0-9_.~%=&-]{1,250})?$'
 or value ~ '^https://rutube\.ru/play/embed/[A-Fa-f0-9]{32}/$'
 or value ~ '^https://vkvideo\.ru/video_ext\.php\?oid=-?[0-9]+&id=[0-9]+&js_api=1(&hash=[A-Za-z0-9_.~%!-]{1,250})?$'
 ), false);
$function$;

CREATE OR REPLACE FUNCTION public.loopa_avatar_can_read(p_owner uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select case when (select auth.uid()) is null or p_owner is null then false
    else not public.loopa_pair_is_blocked((select auth.uid()), p_owner)
  end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_block_user(target_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid := auth.uid();
begin
  if actor is null or target_user is null or target_user = actor then
    raise exception 'Invalid block target';
  end if;

  insert into public.blocked_users(blocker_id, blocked_id)
  values (actor, target_user) on conflict do nothing;

  delete from public.friend_requests
  where status = 'pending'
    and ((sender_id = actor and receiver_id = target_user)
      or (sender_id = target_user and receiver_id = actor));
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_claim_invite_notices()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  recipient_id uuid := auth.uid();
  claimed jsonb;
begin
  if recipient_id is null then
    raise exception 'Authentication required';
  end if;

  with updated as (
    update public.loopa_invites25 as v
    set notified_sent = v.sent
    where v.recipient = recipient_id
      and v.status = 'pending'
      and v.sent > now() - interval '24 hours'
      and v.notified_sent is distinct from v.sent
      and exists (
        select 1 from public.loopa_rooms16 rm
        where rm.code = v.code and rm.host = v.sender
      )
      and not public.loopa_pair_is_blocked(recipient_id, v.sender)
      and exists (
        select 1 from public.friend_requests fr
        where fr.status = 'accepted'
          and (
            (fr.sender_id = recipient_id and fr.receiver_id = v.sender)
            or (fr.sender_id = v.sender and fr.receiver_id = recipient_id)
          )
      )
      and exists (
        select 1 from public.profiles me
        where me.id = recipient_id
          and coalesce(me.room_invite_policy, 'friends') <> 'nobody'
      )
    returning v.id, v.sent
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'sent', sent)), '[]'::jsonb)
    into claimed
  from updated;
  return claimed;
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_claim_telegram_invite(p_invitation uuid, p_sender uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare payload jsonb;
begin
  if p_invitation is null or p_sender is null then return null; end if;
  with claimed as (
    update public.loopa_invites25 v
    set bot_notified_sent = v.sent
    where v.id = p_invitation
      and v.sender = p_sender
      and v.status = 'pending'
      and v.sent > now() - interval '24 hours'
      and v.bot_notified_sent is distinct from v.sent
      and exists(select 1 from public.loopa_rooms16 rm where rm.code=v.code and rm.host=p_sender)
      and exists(select 1 from public.profiles me where me.id=v.recipient
        and coalesce(me.room_invite_policy,'friends') <> 'nobody')
      and not exists(
        select 1 from public.blocked_users b
        where (b.blocker_id=v.recipient and b.blocked_id=p_sender)
           or (b.blocker_id=p_sender and b.blocked_id=v.recipient)
      )
      and exists(select 1 from public.friend_requests f
        where f.status='accepted' and
        ((f.sender_id=p_sender and f.receiver_id=v.recipient) or
         (f.sender_id=v.recipient and f.receiver_id=p_sender)))
      and exists(select 1 from public.telegram_miniapp_links l
        join public.loopa_bot_subscriptions b on b.telegram_id=l.telegram_id
        where l.user_id=v.recipient and b.enabled)
    returning v.recipient,v.code
  )
  select jsonb_build_object(
    'telegram_id',l.telegram_id,
    'code',c.code,
    'sender_name',left(coalesce(nullif(p.display_name,''),'Друг'),80)
  ) into payload
  from claimed c
  join public.telegram_miniapp_links l on l.user_id=c.recipient
  join public.loopa_bot_subscriptions b on b.telegram_id=l.telegram_id and b.enabled
  left join public.profiles p on p.id=p_sender;
  return payload;
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_claim_telegram_login(p_fingerprint text, p_auth_date bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.loopa_collab27(action text, room_code text, enabled boolean DEFAULT NULL::boolean, position_seconds double precision DEFAULT NULL::double precision, is_playing boolean DEFAULT NULL::boolean, sequence bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if action is null or action not in ('mode', 'renew', 'pull', 'ack') then
    raise exception 'Команда недоступна. Обнови LOOPA';
  end if;
  return loopa_private.loopa_collab27(action, room_code, enabled, position_seconds, is_playing, sequence);
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_complete_telegram_registration(p_telegram_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
begin
  if p_telegram_id is null or p_telegram_id !~ '^[1-9][0-9]{0,15}$' then
    raise exception 'Invalid Telegram account identifier';
  end if;

  -- Same Telegram lock as the explicit link flow, including its insert trigger.
  perform pg_advisory_xact_lock(171406, hashtext(p_telegram_id));

  select l.user_id into v_user_id
  from public.telegram_miniapp_links l where l.telegram_id = p_telegram_id;
  if found then
    return jsonb_build_object('status', 'linked', 'user_id', v_user_id);
  end if;
  if exists (select 1 from loopa_private.telegram_pending_links p where p.telegram_id = p_telegram_id) then
    return jsonb_build_object('status', 'link_pending');
  end if;

  v_user_id := loopa_private.find_telegram_registration(p_telegram_id);
  if v_user_id is null then
    return jsonb_build_object('status', 'missing');
  end if;
  perform loopa_private.lock_telegram_link(p_telegram_id, v_user_id);
  if exists (select 1 from public.telegram_miniapp_links l where l.user_id = v_user_id)
     or exists (select 1 from loopa_private.telegram_pending_links p where p.user_id = v_user_id) then
    return jsonb_build_object('status', 'link_pending');
  end if;

  insert into public.telegram_miniapp_links (telegram_id, user_id)
  values (p_telegram_id, v_user_id);
  insert into loopa_private.telegram_finished_registrations (user_id) values (v_user_id);
  return jsonb_build_object('status', 'linked', 'user_id', v_user_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_control_generation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if TG_ARGV[0]='grant' or new.video is distinct from old.video then
  new.control_generation=old.control_generation+1;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.loopa_control_v2(room_code text, expected_video text, expected_generation bigint, position_seconds double precision, is_playing boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r public.loopa_rooms16;
begin
  if auth.uid() is null then raise exception 'login_required'; end if;

  select * into r from public.loopa_rooms16 where code = upper(trim(room_code)) for update;
  if r.code is null or r.video is distinct from expected_video
     or r.control_generation is distinct from expected_generation then
    raise exception 'Комната или разрешение изменились';
  end if;

  return loopa_private.loopa_collab27(
    action => 'control', room_code => r.code,
    position_seconds => position_seconds, is_playing => is_playing
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_dm_inbox(before_id bigint DEFAULT NULL::bigint, page_size integer DEFAULT 51)
 RETURNS TABLE(id bigint, sender_id uuid, recipient_id uuid, body text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select latest.id,latest.sender_id,latest.recipient_id,latest.body,latest.created_at
 from (
  select distinct on (case when m.sender_id=(select auth.uid()) then m.recipient_id else m.sender_id end)
   m.id,m.sender_id,m.recipient_id,m.body,m.created_at
  from public.loopa_dm_messages_v87 m
  where m.sender_id=(select auth.uid()) or m.recipient_id=(select auth.uid())
  order by case when m.sender_id=(select auth.uid()) then m.recipient_id else m.sender_id end,m.id desc
 ) latest
 where before_id is null or latest.id<before_id
 order by latest.id desc limit greatest(1,least(coalesce(page_size,51),101));
$function$;

CREATE OR REPLACE FUNCTION public.loopa_dm_may_send_v87(target uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select target is not null and auth.uid() is not null and target <> auth.uid()
  and exists(select 1 from public.profiles p where p.id = target)
  and not exists (
     select 1 from public.blocked_users b
      where (b.blocker_id=auth.uid() and b.blocked_id=target)
         or (b.blocker_id=target and b.blocked_id=auth.uid())
  )
  and (
     coalesce((select p.dm_policy from public.profiles p where p.id=target),'everyone') = 'everyone'
     or exists (
       select 1 from public.friend_requests f
       where f.status='accepted'
         and ((f.sender_id=auth.uid() and f.receiver_id=target)
           or (f.sender_id=target and f.receiver_id=auth.uid()))
     )
  );
$function$;

CREATE OR REPLACE FUNCTION public.loopa_dm_policy_new_profile_default_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.dm_policy is null then
    new.dm_policy := 'everyone';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.loopa_friend_stats_v87(peer_id uuid)
 RETURNS TABLE(total_seconds bigint, joined_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select u.total_seconds from public.loopa_usage_v87 u where u.user_id=peer_id),0),
        (select a.created_at from auth.users a where a.id=peer_id)
 where auth.uid() is not null and (peer_id = auth.uid() or (not public.loopa_pair_is_blocked(auth.uid(), peer_id) and exists (
   select 1 from public.friend_requests f
   where f.status='accepted'
     and ((f.sender_id=auth.uid() and f.receiver_id=peer_id)
       or (f.sender_id=peer_id and f.receiver_id=auth.uid()))
 )));
$function$;

CREATE OR REPLACE FUNCTION public.loopa_friend_stats_v88(peer_id uuid)
 RETURNS TABLE(total_seconds bigint, joined_at timestamp with time zone, history_synced boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select u.total_seconds from public.loopa_usage_v87 u where u.user_id=peer_id),0)::bigint,
         (select a.created_at from auth.users a where a.id=peer_id),
         coalesce((select u.history_synced from public.loopa_usage_v87 u where u.user_id=peer_id),false)
  where auth.uid() is not null and (peer_id = auth.uid() or (not public.loopa_pair_is_blocked(auth.uid(), peer_id) and exists (
    select 1 from public.friend_requests f
    where f.status = 'accepted'
      and ((f.sender_id=auth.uid() and f.receiver_id=peer_id)
        or (f.sender_id=peer_id and f.receiver_id=auth.uid()))
  )));
$function$;

CREATE OR REPLACE FUNCTION public.loopa_guard_friend_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.id is distinct from old.id
     or new.sender_id is distinct from old.sender_id
     or new.receiver_id is distinct from old.receiver_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Friend request participants cannot be changed';
  end if;
  if old.status <> 'pending' or new.status <> 'accepted' then
    raise exception 'Only pending requests can be accepted';
  end if;
  new.responded_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_history27(op text, room_code text DEFAULT ''::text, media text DEFAULT ''::text, caption text DEFAULT ''::text, picture text DEFAULT ''::text, elapsed double precision DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); r public.loopa_rooms16; stats public.loopa_usage27; stamp timestamptz:=clock_timestamp();
begin
 if u is null then raise exception 'Войди в аккаунт'; end if;
 insert into public.loopa_usage27(owner) values(u) on conflict do nothing;
 select * into stats from public.loopa_usage27 where owner=u for update;
 if op='start' then update public.loopa_usage27 set tick=stamp where owner=u;
 elsif op='tick' then
 if elapsed is null or elapsed not between 0 and 20 then raise exception 'Проверь время'; end if;
 update public.loopa_usage27 set total_seconds=total_seconds+least(elapsed,greatest(0,extract(epoch from stamp-tick)),20),tick=stamp where owner=u;
 elsif op in ('record','meta') then
 select * into r from public.loopa_rooms16 where code=room_code for update;
 if r.code is null or r.video='' or public.loopa_pair_is_blocked(u,r.host) or not exists(select from public.loopa_members16 m where m.code=r.code and m.member=u) or (r.host<>u and ((r.access_mode='private' and not(u=any(r.allowed))) or (r.access_mode='friends' and not exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=r.host) or (f.sender_id=r.host and f.receiver_id=u)))))) then raise exception 'Комната недоступна'; end if;
 if op='meta' then
 if r.host<>u or r.video<>media or length(trim(caption)) not between 1 and 200 then raise exception 'Нет доступа'; end if;
 if length(picture)>1500 or (picture<>'' and picture !~ '^https://([a-zA-Z0-9-]+\.)*(ytimg\.com|youtube\.com|userapi\.com|vk\.com|vkvideo\.ru|rutube\.ru|rtbcdn\.ru)/') then picture:=''; end if;
 insert into public.loopa_titles26(code,video,title,image) values(r.code,media,trim(caption),picture) on conflict(code) do update set video=excluded.video,title=excluded.title,image=case when public.loopa_titles26.video=excluded.video and excluded.image='' then public.loopa_titles26.image else excluded.image end;
 end if;
 insert into public.loopa_history27(owner,video,code,title,image,seen) select u,r.video,r.code,coalesce(t.title,'Видео'),coalesce(t.image,''),stamp from (select 1) dummy left join public.loopa_titles26 t on t.code=r.code and t.video=r.video on conflict(owner,video) do update set code=excluded.code,title=excluded.title,image=excluded.image,seen=excluded.seen;
 elsif op<>'read' then raise exception 'Неизвестная команда'; end if;
 -- One-time seed from rooms this account has already visited; never expose inaccessible rooms.
 if not exists(select from public.loopa_history27 h where h.owner=u) then
 insert into public.loopa_history27(owner,video,code,title,image,seen)
 select distinct on (rr.video) u,rr.video,rr.code,coalesce(t.title,'Видео'),coalesce(t.image,''),coalesce(m.seen,rr.changed) from public.loopa_members16 m join public.loopa_rooms16 rr on rr.code=m.code left join public.loopa_titles26 t on t.code=rr.code and t.video=rr.video where m.member=u and rr.video<>'' and not public.loopa_pair_is_blocked(u,rr.host) and (rr.host=u or rr.access_mode='code' or (rr.access_mode='private' and u=any(rr.allowed)) or (rr.access_mode='friends' and exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=rr.host) or (f.sender_id=rr.host and f.receiver_id=u))))) order by rr.video,m.seen desc nulls last;
 end if;
 delete from public.loopa_history27 h where h.owner=u and h.video not in (select x.video from public.loopa_history27 x where x.owner=u order by x.seen desc limit 2);
 return jsonb_build_object('seconds',(select total_seconds from public.loopa_usage27 where owner=u),'history',coalesce((select jsonb_agg(to_jsonb(x)-'owner' order by x.seen desc) from public.loopa_history27 x where x.owner=u),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.loopa_invite25(action text, room_code text DEFAULT ''::text, peer uuid DEFAULT NULL::uuid, invitation uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); r public.loopa_rooms16; i public.loopa_invites25; answer jsonb;
begin
 if u is null then raise exception 'Войди в аккаунт'; end if;
 if action='friends' then
   select * into r from public.loopa_rooms16 where code=upper(trim(room_code));
   if r.code is null or r.host<>u then raise exception 'Приглашать может ведущий комнаты'; end if;
   return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(p.display_name,'Друг'),'online',exists(select from public.user_presence pr where pr.user_id=p.id and pr.visible and pr.last_active_at>now()-interval '90 seconds'),'invited',exists(select from public.loopa_invites25 v where v.code=r.code and v.recipient=p.id and v.status='pending' and v.sent>now()-interval '24 hours')) order by p.display_name)
     from public.profiles p where p.id<>u and coalesce(p.room_invite_policy,'friends')<>'nobody' and not public.loopa_pair_is_blocked(u,p.id) and exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=p.id) or (f.sender_id=p.id and f.receiver_id=u)))),'[]'::jsonb);
 elsif action='send' then
   select * into r from public.loopa_rooms16 where code=upper(trim(room_code)) for update;
   if r.code is null or r.host<>u then raise exception 'Приглашать может ведущий комнаты'; end if;
   if peer is null or peer=u or public.loopa_pair_is_blocked(u,peer) or not exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=peer) or (f.sender_id=peer and f.receiver_id=u))) or not exists(select from public.profiles p where p.id=peer and coalesce(p.room_invite_policy,'friends')<>'nobody') then raise exception 'Приглашение недоступно'; end if;
   select * into i from public.loopa_invites25 where code=r.code and recipient=peer;
   if i.sent>now()-interval '60 seconds' then raise exception 'Приглашение уже отправлено. Подожди минуту'; end if;
   if (select count(*) from public.loopa_invites25 where sender=u and sent>now()-interval '1 minute')>=20 then raise exception 'Слишком много приглашений. Подожди минуту'; end if;
   insert into public.loopa_invites25(code,sender,recipient) values(r.code,u,peer) on conflict(code,recipient) do update set sent=now(),status='pending' returning * into i;
   return jsonb_build_object('id',i.id);
 elsif action='inbox' then
   -- The inbox query is limited to the authenticated recipient's current invite.
   -- Private-room title and attendance stay hidden until the recipient is on the allow-list.
   return coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'code',v.code,'name',coalesce(p.display_name,'Друг'),'sent',v.sent,'watch_title',case when rm.access_mode='private' and not coalesce(u=any(rm.allowed),false) then 'Закрытая комната' when coalesce(rm.video,'')='' then 'Видео ещё не выбрано' else coalesce(nullif(t.title,''),'Видео') end,'watch_image',case when rm.access_mode='private' and not coalesce(u=any(rm.allowed),false) then null else coalesce(t.image,'') end,'participant_count',case when rm.access_mode='private' and not coalesce(u=any(rm.allowed),false) then null else (select count(*)::integer from public.loopa_members16 m where m.code=rm.code and m.seen>now()-interval '20 seconds') end) order by v.sent desc)
     from public.loopa_invites25 v join public.loopa_rooms16 rm on rm.code=v.code join public.profiles p on p.id=v.sender left join public.loopa_titles26 t on t.code=rm.code and t.video=rm.video where v.recipient=u and v.status='pending' and v.sent>now()-interval '24 hours' and rm.host=v.sender and not public.loopa_pair_is_blocked(u,v.sender) and exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=v.sender) or (f.sender_id=v.sender and f.receiver_id=u))) and exists(select from public.profiles me where me.id=u and coalesce(me.room_invite_policy,'friends')<>'nobody')),'[]'::jsonb);
 elsif action in ('accept','decline') then
   select * into i from public.loopa_invites25 where id=invitation and recipient=u;
   if i.id is null then raise exception 'Приглашение не найдено'; end if;
   -- Lock room first, matching send and room RPC lock order.
   select * into r from public.loopa_rooms16 where code=i.code for update;
   select * into i from public.loopa_invites25 where id=invitation and recipient=u for update;
   if i.status<>'pending' or i.sent<now()-interval '24 hours' then raise exception 'Приглашение устарело'; end if;
   if action='accept' then
     if r.code is null or r.host<>i.sender or public.loopa_pair_is_blocked(u,i.sender) or not exists(select from public.profiles me where me.id=u and coalesce(me.room_invite_policy,'friends')<>'nobody') or not exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=i.sender) or (f.sender_id=i.sender and f.receiver_id=u))) then raise exception 'Приглашение недоступно'; end if;
     if r.access_mode='private' then update public.loopa_rooms16 set allowed=array_append(allowed,u) where code=r.code and not(u=any(allowed)); end if;
     answer:=public.loopa_room16('join',i.code);
   end if;
   update public.loopa_invites25 set status=case when action='accept' then 'accepted' else 'declined' end where id=i.id;
   return coalesce(answer,'{}'::jsonb);
 end if;
 raise exception 'Неизвестная команда';
end $function$;

CREATE OR REPLACE FUNCTION public.loopa_pair_is_blocked(user_a uuid, user_b uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
if auth.uid() is null or auth.uid() not in (user_a,user_b) then
raise exception 'Pair check is only available to a participant';
end if;
return exists (
select 1 from public.blocked_users b
where (b.blocker_id = user_a and b.blocked_id = user_b)
or (b.blocker_id = user_b and b.blocked_id = user_a)
);
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_profiles_by_ids(p_ids uuid[])
 RETURNS TABLE(id uuid, display_name text, username text, avatar_path text, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p.id, p.display_name, p.username,
    case when not public.loopa_pair_is_blocked((select auth.uid()), p.id) then p.avatar_path end,
    p.updated_at
  from public.profiles p
  where (select auth.uid()) is not null
    and cardinality(p_ids) between 1 and 150
    and p.id = any(p_ids);
$function$;

CREATE OR REPLACE FUNCTION public.loopa_public_profiles()
 RETURNS TABLE(id uuid, display_name text, username text, avatar_path text, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p.id, p.display_name, p.username,
    case when not public.loopa_pair_is_blocked((select auth.uid()), p.id) then p.avatar_path end,
    p.updated_at
  from public.profiles p where (select auth.uid()) is not null;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_repair_telegram_profile(p_telegram_id text, p_user_id uuid, p_apply boolean, p_display_name text DEFAULT NULL::text, p_username text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_avatar_missing boolean;
  v_avatar text;
begin
  select p.avatar_path is null into v_avatar_missing
  from public.profiles p
  join public.telegram_miniapp_links l on l.user_id = p.id
  join auth.users u on u.id = p.id
  where p.id = p_user_id and l.telegram_id = p_telegram_id
    and u.raw_app_meta_data->>'loopa_telegram_registration' = p_telegram_id
    and p.display_name = 'Участник LOOPA'
    and not exists (select 1 from loopa_private.telegram_profile_imports i where i.user_id = p.id)
  for update of p;
  if not found then return jsonb_build_object('eligible', false); end if;
  if p_apply is not true then
    return jsonb_build_object('eligible', true, 'avatar_missing', v_avatar_missing);
  end if;

  insert into loopa_private.telegram_profile_imports(user_id)
  values(p_user_id) on conflict do nothing;
  if not found then return jsonb_build_object('eligible', false); end if;

  if v_avatar_missing then
    select o.name into v_avatar from storage.objects o
    where o.bucket_id = 'avatars' and o.name = p_user_id::text || '/telegram-avatar.jpg';
  end if;
  update public.profiles
  set display_name = coalesce(nullif(left(btrim(p_display_name), 40), ''), display_name),
      avatar_path = coalesce(avatar_path, v_avatar),
      updated_at = clock_timestamp()
  where id = p_user_id;

  if p_username ~ '^[a-z][a-z0-9_]{3,15}$' then
    begin
      update public.profiles set username = p_username where id = p_user_id and username is null;
    exception when unique_violation then
      null; -- Keep the existing owner of the nickname.
    end;
  end if;
  return jsonb_build_object('imported', true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_request_account_deletion()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.loopa_revoke_collab_on_video_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.video is distinct from old.video then
    new.shared_control=false;
    new.shared_control_video='';
    new.shared_control_until=null;
    new.control_applied_seq=new.control_seq;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.loopa_room16(op text, room text DEFAULT ''::text, media text DEFAULT ''::text, seconds double precision DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); r public.loopa_rooms16; stamp timestamptz;
begin
 if u is null then raise exception 'Войди в аккаунт'; end if;
 room:=upper(trim(room));
 if op='list' then return coalesce((select jsonb_agg(x.code order by x.changed desc) from public.loopa_rooms16 x join public.loopa_members16 m using(code) where m.member=u and not public.loopa_pair_is_blocked(u,x.host) and (x.host=u or x.access_mode='code' or (x.access_mode='private' and u=any(x.allowed)) or (x.access_mode='friends' and exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=x.host) or (f.sender_id=x.host and f.receiver_id=u)))))),'[]'::jsonb); end if;
 if op='create' then
 insert into public.loopa_rooms16(host) values(u) returning * into r;
 insert into public.loopa_members16(code,member) values(r.code,u);
 else
 select * into r from public.loopa_rooms16 where code=room for update;
 if r.code is null or public.loopa_pair_is_blocked(u,r.host) then raise exception 'Комната недоступна'; end if;
 if u<>r.host and ((r.access_mode='friends' and not exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=r.host) or (f.sender_id=r.host and f.receiver_id=u)))) or (r.access_mode='private' and not(u=any(r.allowed)))) then raise exception 'Комната недоступна'; end if;
 if op='join' then insert into public.loopa_members16(code,member) values(room,u) on conflict do nothing;
 -- An actual successful join also accepts the host's outstanding room invite,
 -- even if the user entered through a Telegram startapp/deep link or room code.
 -- This runs after access checks and membership insert, inside one transaction.
 update public.loopa_invites25 v
   set status='accepted'
   where v.code=r.code and v.recipient=u and v.sender=r.host
     and v.status='pending' and v.sent>now()-interval '24 hours';
 elsif not exists(select from public.loopa_members16 where code=room and member=u) then raise exception 'Нет доступа'; end if;
 if op in ('video','play','pause') then
 if r.host<>u then raise exception 'Управлять может ведущий'; end if;
 if op='video' and (media is null or length(media) not between 10 and 1500 or not public.loopa_allowed_video_url(media)) then raise exception 'Разрешены только ссылки YouTube, VK Видео и RUTUBE'; end if;
 if seconds not between 0 and 864000 then raise exception 'Проверь время'; end if;
 update public.loopa_rooms16 set video=case when op='video' then media else video end,playing=op='play',pos=case when op='video' then 0 else seconds end,changed=clock_timestamp() where code=room returning * into r;
 elsif op='chat' then
 if length(trim(media)) not between 1 and 1000 then raise exception 'Сообщение: от 1 до 1000 символов'; end if;
 insert into public.loopa_chat18(code,author,body) values(room,u,trim(media));
 elsif op='access' then
 if u<>r.host or coalesce(media::jsonb->>'mode','') not in ('code','friends','private') then raise exception 'Нет доступа'; end if;
 update public.loopa_rooms16 set access_mode=media::jsonb->>'mode',allowed=array(select value::uuid from jsonb_array_elements_text(media::jsonb->'ids')) where code=room returning * into r;
 elsif op not in ('join','read') then raise exception 'Неизвестная команда'; end if;
 end if;
 update public.loopa_members16 set seen=clock_timestamp() where code=r.code and member=u;
 stamp:=clock_timestamp();
 return (to_jsonb(r)-'allowed')||jsonb_build_object('allowed',case when u=r.host then r.allowed else '{}'::uuid[] end,'server_time',stamp,
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.member,'name',coalesce(p.display_name,'Участник'),'online',coalesce(m.seen>stamp-interval '20 seconds',false) and (m.member=u or (
      not public.loopa_pair_is_blocked(u,m.member) and not exists (
        select 1 from public.user_presence pr where pr.user_id=m.member and not pr.visible
      )
    )))) from public.loopa_members16 m left join public.profiles p on p.id=m.member where m.code=r.code),'[]'::jsonb),
 'chat',coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from(select c.id,c.author,c.body,c.sent,p.display_name as name from public.loopa_chat18 c left join public.profiles p on p.id=c.author where c.code=r.code order by c.id desc limit 60)t),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.loopa_search_budget(p_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if p_mode not in ('search','suggest') or p_mode is null then raise exception 'Неизвестный режим'; end if;
 return loopa_private.consume_budget(p_mode);
end $function$;

CREATE OR REPLACE FUNCTION public.loopa_search_profiles(p_term text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  viewer uuid := auth.uid();
  needle text := lower(btrim(p_term));
  handle text := btrim(regexp_replace(needle, '^@', ''));
  budget jsonb;
  exact_id uuid;
  results jsonb;
begin
  if viewer is null then raise exception 'Войди в аккаунт'; end if;
  if needle is null or char_length(needle) not between 2 and 40 then
    return jsonb_build_object('profiles', '[]'::jsonb);
  end if;

  budget := loopa_private.consume_budget('user_search');
  if (budget->>'allowed')::boolean is distinct from true then
    return jsonb_build_object('profiles', '[]'::jsonb, 'retry_after', budget->'retry_after');
  end if;

  if handle ~ '^[a-z][a-z0-9_]{3,15}$' then
    select p.id into exact_id from public.profiles p
    where p.username = handle and p.id <> viewer and not exists (
      select 1 from public.blocked_users b where b.blocker_id = viewer and b.blocked_id = p.id
    );
  end if;

  with candidates as (
    select exact_id as id, 0 as rank where exact_id is not null
    union all
    select matches.id, 1 from (
      select p.id from public.profiles p
      where p.id <> viewer and p.id is distinct from exact_id
        and strpos(lower(p.display_name), needle) > 0 and not exists (
          select 1 from public.blocked_users b where b.blocker_id = viewer and b.blocked_id = p.id
        )
      order by p.id limit 15
    ) matches
  )
  select coalesce(jsonb_agg(to_jsonb(p) order by c.rank, p.id), '[]'::jsonb) into results
  from public.loopa_profiles_by_ids(array(select c.id from candidates c)) p
  join candidates c on c.id = p.id;
  return jsonb_build_object('profiles', results);
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_submit_user_report(p_target_user uuid, p_message_ref text, p_reason text, p_details text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.loopa_sync57(room_code text, media text DEFAULT ''::text, position_seconds double precision DEFAULT 0, is_playing boolean DEFAULT false, sample_age double precision DEFAULT 0, publish boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); r public.loopa_rooms16; snap public.loopa_playback57; permission jsonb; t timestamptz;
begin
 if u is null then raise exception 'Войди в аккаунт'; end if;
 -- Reuse the room's existing membership, privacy and block checks.
 permission:=public.loopa_room16(op=>'read',room=>room_code);
 select * into r from public.loopa_rooms16 where code=room_code for share;
 if r.code is null then raise exception 'Комната недоступна'; end if;
 t:=clock_timestamp();
 if publish then
  if r.host<>u then raise exception 'Управляет ведущий'; end if;
  if media<>r.video or media='' then raise exception 'Видео изменилось'; end if;
  if position_seconds is null or position_seconds not between 0 and 604800 or sample_age is null or sample_age not between 0 and 2 or is_playing is null then raise exception 'Некорректный замер'; end if;
  if not (r.shared_control and r.shared_control_until>clock_timestamp() and r.shared_control_video=r.video and r.control_video=r.video and r.control_seq>r.control_applied_seq) then
  insert into public.loopa_playback57(code,video,pos,playing,stamp,owner)
  values(room_code,media,position_seconds+case when is_playing then sample_age else 0 end,is_playing,t,u)
  on conflict(code) do update set video=excluded.video,pos=excluded.pos,playing=excluded.playing,stamp=excluded.stamp,owner=excluded.owner;
  end if;
 end if;
 select * into snap from public.loopa_playback57 where code=room_code;
 if snap.code is null or snap.video<>r.video or snap.owner<>r.host then return jsonb_build_object('ready',false); end if;
 return jsonb_build_object('ready',true,'video',snap.video,'pos',snap.pos,'playing',snap.playing,'age',greatest(0,extract(epoch from clock_timestamp()-snap.stamp)));
end $function$;

CREATE OR REPLACE FUNCTION public.loopa_take_telegram_action_budget(p_telegram_id text, p_action text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.loopa_telegram_link_step(p_telegram_id text, p_user_id uuid, p_finish boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_telegram_id is null or p_telegram_id !~ '^[1-9][0-9]{0,15}$'
     or p_user_id is null or p_finish is null then
    raise exception 'Invalid Telegram link request';
  end if;

  perform loopa_private.lock_telegram_link(p_telegram_id, p_user_id);

  if exists (select 1 from public.telegram_miniapp_links l
             where l.telegram_id = p_telegram_id and l.user_id = p_user_id) then
    return 'already_linked';
  end if;
  if exists (select 1 from public.telegram_miniapp_links l where l.telegram_id = p_telegram_id)
     or exists (select 1 from loopa_private.telegram_pending_links p
                where p.telegram_id = p_telegram_id and p.user_id <> p_user_id) then
    return 'telegram_already_linked_to_another_profile';
  end if;
  if exists (select 1 from public.telegram_miniapp_links l where l.user_id = p_user_id)
     or exists (select 1 from loopa_private.telegram_pending_links p
                where p.user_id = p_user_id and p.telegram_id <> p_telegram_id) then
    return 'profile_already_linked_to_another_telegram';
  end if;

  if not p_finish then
    if loopa_private.find_telegram_registration(p_telegram_id) is not null then
      return 'telegram_registration_pending';
    end if;
    insert into loopa_private.telegram_pending_links (telegram_id, user_id)
    values (p_telegram_id, p_user_id) on conflict (telegram_id) do nothing;
    return 'reserved';
  end if;

  if not exists (select 1 from loopa_private.telegram_pending_links p
                 where p.telegram_id = p_telegram_id and p.user_id = p_user_id)
     or not exists (select 1 from auth.users u where u.id = p_user_id and nullif(u.email, '') is not null) then
    return 'link_unavailable';
  end if;

  insert into public.telegram_miniapp_links (telegram_id, user_id)
  values (p_telegram_id, p_user_id);
  delete from loopa_private.telegram_pending_links where telegram_id = p_telegram_id and user_id = p_user_id;
  return 'linked';
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_touch_resume_point_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_unblock_user(target_user uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
delete from public.blocked_users
where blocker_id = auth.uid() and blocked_id = target_user;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_usage_ping_v87()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare who uuid := auth.uid();
begin
 if who is null then return; end if;
 insert into public.loopa_usage_v87(user_id,total_seconds,last_ping_at)
 values(who,0,clock_timestamp())
 on conflict(user_id) do update
 set total_seconds = public.loopa_usage_v87.total_seconds +
   case when public.loopa_usage_v87.last_ping_at is not null
             and clock_timestamp()-public.loopa_usage_v87.last_ping_at <= interval '45 seconds'
        then least(30, greatest(0, floor(extract(epoch from
             clock_timestamp()-public.loopa_usage_v87.last_ping_at))::integer))
        else 0 end,
     last_ping_at = clock_timestamp();
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_usage_snapshot_v88(observed_total_seconds bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare who uuid := auth.uid();
begin
  if who is null then
    raise exception 'Authentication required';
  end if;
  if observed_total_seconds is null or observed_total_seconds < 0 or observed_total_seconds > 315360000 then
    raise exception 'Invalid usage duration';
  end if;
  insert into public.loopa_usage_v87 (user_id,total_seconds,last_ping_at,history_synced)
  values (who,observed_total_seconds,clock_timestamp(),true)
  on conflict (user_id) do update
  set total_seconds = greatest(public.loopa_usage_v87.total_seconds,excluded.total_seconds),
      last_ping_at = excluded.last_ping_at,
      history_synced = true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.loopa_visible_presence(p_users uuid[])
 RETURNS TABLE(user_id uuid, last_active_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p.user_id, p.last_active_at from public.user_presence p
  where (select auth.uid()) is not null and p.user_id = any(p_users)
    and (p.user_id = (select auth.uid()) or (
      p.visible and not public.loopa_pair_is_blocked((select auth.uid()), p.user_id)
    ));
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

ALTER TABLE "loopa_private"."request_budgets" ADD CONSTRAINT "request_budgets_pkey" PRIMARY KEY (user_id, scope);

ALTER TABLE "loopa_private"."request_budgets" ADD CONSTRAINT "request_budgets_scope_check" CHECK ((scope = ANY (ARRAY['message'::text, 'room_create'::text, 'search'::text, 'suggest'::text, 'friend_request'::text, 'room_invite'::text, 'user_search'::text])));

ALTER TABLE "loopa_private"."telegram_action_budgets" ADD CONSTRAINT "telegram_action_budgets_action_check" CHECK ((action = ANY (ARRAY['login'::text, 'register'::text, 'link'::text, 'status'::text])));

ALTER TABLE "loopa_private"."telegram_action_budgets" ADD CONSTRAINT "telegram_action_budgets_pkey" PRIMARY KEY (telegram_id, action);

ALTER TABLE "loopa_private"."telegram_action_budgets" ADD CONSTRAINT "telegram_action_budgets_telegram_id_check" CHECK ((telegram_id ~ '^[1-9][0-9]{0,15}$'::text));

ALTER TABLE "loopa_private"."telegram_finished_registrations" ADD CONSTRAINT "telegram_finished_registrations_pkey" PRIMARY KEY (user_id);

ALTER TABLE "loopa_private"."telegram_login_claims" ADD CONSTRAINT "telegram_login_claims_fingerprint_check" CHECK ((fingerprint ~ '^[0-9a-f]{64}$'::text));

ALTER TABLE "loopa_private"."telegram_login_claims" ADD CONSTRAINT "telegram_login_claims_pkey" PRIMARY KEY (fingerprint);

ALTER TABLE "loopa_private"."telegram_pending_links" ADD CONSTRAINT "telegram_pending_links_pkey" PRIMARY KEY (telegram_id);

ALTER TABLE "loopa_private"."telegram_pending_links" ADD CONSTRAINT "telegram_pending_links_telegram_id_check" CHECK ((telegram_id ~ '^[1-9][0-9]{0,15}$'::text));

ALTER TABLE "loopa_private"."telegram_pending_links" ADD CONSTRAINT "telegram_pending_links_user_id_key" UNIQUE (user_id);

ALTER TABLE "loopa_private"."telegram_profile_imports" ADD CONSTRAINT "telegram_profile_imports_pkey" PRIMARY KEY (user_id);

ALTER TABLE "public"."blocked_users" ADD CONSTRAINT "blocked_users_pkey" PRIMARY KEY (blocker_id, blocked_id);

ALTER TABLE "public"."blocked_users" ADD CONSTRAINT "loopa_block_no_self" CHECK ((blocker_id <> blocked_id));

ALTER TABLE "public"."friend_requests" ADD CONSTRAINT "friend_requests_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."friend_requests" ADD CONSTRAINT "friend_requests_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text])));

ALTER TABLE "public"."friend_requests" ADD CONSTRAINT "loopa_friends_no_self" CHECK ((sender_id <> receiver_id));

ALTER TABLE "public"."loopa_account_deletion_requests_v1" ADD CONSTRAINT "loopa_account_deletion_requests_v1_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."loopa_account_deletion_requests_v1" ADD CONSTRAINT "loopa_account_deletion_requests_v1_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'completed'::text, 'declined'::text])));

ALTER TABLE "public"."loopa_bot_subscriptions" ADD CONSTRAINT "loopa_bot_subscriptions_numeric_id" CHECK ((telegram_id ~ '^[1-9][0-9]{0,18}$'::text));

ALTER TABLE "public"."loopa_bot_subscriptions" ADD CONSTRAINT "loopa_bot_subscriptions_pkey" PRIMARY KEY (telegram_id);

ALTER TABLE "public"."loopa_chat18" ADD CONSTRAINT "loopa_chat18_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."loopa_dm_messages_v87" ADD CONSTRAINT "loopa_dm_messages_v87_body_check" CHECK (((char_length(btrim(body)) >= 1) AND (char_length(btrim(body)) <= 2000)));

ALTER TABLE "public"."loopa_dm_messages_v87" ADD CONSTRAINT "loopa_dm_messages_v87_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."loopa_dm_messages_v87" ADD CONSTRAINT "loopa_dm_not_self" CHECK ((sender_id <> recipient_id));

ALTER TABLE "public"."loopa_history27" ADD CONSTRAINT "loopa_history27_pkey" PRIMARY KEY (owner, video);

ALTER TABLE "public"."loopa_invites25" ADD CONSTRAINT "loopa_invites25_code_recipient_key" UNIQUE (code, recipient);

ALTER TABLE "public"."loopa_invites25" ADD CONSTRAINT "loopa_invites25_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."loopa_invites25" ADD CONSTRAINT "loopa_invites25_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text])));

ALTER TABLE "public"."loopa_members16" ADD CONSTRAINT "loopa_members16_pkey" PRIMARY KEY (code, member);

ALTER TABLE "public"."loopa_playback57" ADD CONSTRAINT "loopa_playback57_pkey" PRIMARY KEY (code);

ALTER TABLE "public"."loopa_resume_points" ADD CONSTRAINT "loopa_resume_points_duration_seconds_check" CHECK (((duration_seconds >= 0) AND (duration_seconds <= 360000)));

ALTER TABLE "public"."loopa_resume_points" ADD CONSTRAINT "loopa_resume_points_media_check" CHECK (((length(media) >= 1) AND (length(media) <= 2048)));

ALTER TABLE "public"."loopa_resume_points" ADD CONSTRAINT "loopa_resume_points_pkey" PRIMARY KEY (user_id, media);

ALTER TABLE "public"."loopa_resume_points" ADD CONSTRAINT "loopa_resume_points_position_seconds_check" CHECK (((position_seconds >= 20) AND (position_seconds <= 360000)));

ALTER TABLE "public"."loopa_rooms16" ADD CONSTRAINT "loopa_rooms16_allowed_members_valid" CHECK (
CASE
    WHEN (COALESCE(array_ndims(allowed), 1) = 1) THEN (array_position(allowed, NULL::uuid) IS NULL)
    ELSE false
END);

ALTER TABLE "public"."loopa_rooms16" ADD CONSTRAINT "loopa_rooms16_pkey" PRIMARY KEY (code);

ALTER TABLE "public"."loopa_titles26" ADD CONSTRAINT "loopa_titles26_pkey" PRIMARY KEY (code);

ALTER TABLE "public"."loopa_usage27" ADD CONSTRAINT "loopa_usage27_pkey" PRIMARY KEY (owner);

ALTER TABLE "public"."loopa_usage_v87" ADD CONSTRAINT "loopa_usage_v87_pkey" PRIMARY KEY (user_id);

ALTER TABLE "public"."loopa_usage_v87" ADD CONSTRAINT "loopa_usage_v87_total_seconds_check" CHECK ((total_seconds >= 0));

ALTER TABLE "public"."loopa_user_reports_v1" ADD CONSTRAINT "loopa_user_reports_v1_details_check" CHECK (((details IS NULL) OR (char_length(details) <= 500)));

ALTER TABLE "public"."loopa_user_reports_v1" ADD CONSTRAINT "loopa_user_reports_v1_message_ref_check" CHECK (((message_ref IS NULL) OR ((char_length(message_ref) >= 1) AND (char_length(message_ref) <= 128))));

ALTER TABLE "public"."loopa_user_reports_v1" ADD CONSTRAINT "loopa_user_reports_v1_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."loopa_user_reports_v1" ADD CONSTRAINT "loopa_user_reports_v1_reason_check" CHECK ((reason = ANY (ARRAY['harassment'::text, 'spam'::text, 'threats'::text, 'scam'::text, 'other'::text])));

ALTER TABLE "public"."loopa_user_reports_v1" ADD CONSTRAINT "loopa_user_reports_v1_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'reviewed'::text, 'actioned'::text, 'dismissed'::text])));

ALTER TABLE "public"."profiles" ADD CONSTRAINT "loopa_profile_avatar_own_path" CHECK (((avatar_path IS NULL) OR (avatar_path ~ (('^'::text || (id)::text) || '/avatar[.](jpg|png|webp)$'::text)) OR (avatar_path = ((id)::text || '/telegram-avatar.jpg'::text))));

ALTER TABLE "public"."profiles" ADD CONSTRAINT "loopa_room_invite_policy_check" CHECK ((room_invite_policy = ANY (ARRAY['everyone'::text, 'friends'::text, 'nobody'::text])));

ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_display_name_check" CHECK (((char_length(TRIM(BOTH FROM display_name)) >= 1) AND (char_length(TRIM(BOTH FROM display_name)) <= 40)));

ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_dm_policy_check" CHECK ((dm_policy = ANY (ARRAY['everyone'::text, 'friends'::text])));

ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_username_format_v1" CHECK (((username IS NULL) OR ((username = lower(btrim(username))) AND (username ~ '^[a-z][a-z0-9_]{3,15}$'::text))));

ALTER TABLE "public"."telegram_miniapp_links" ADD CONSTRAINT "telegram_miniapp_links_pkey" PRIMARY KEY (telegram_id);

ALTER TABLE "public"."telegram_miniapp_links" ADD CONSTRAINT "telegram_miniapp_links_telegram_id_check" CHECK ((telegram_id ~ '^[0-9]{1,20}$'::text));

ALTER TABLE "public"."telegram_miniapp_links" ADD CONSTRAINT "telegram_miniapp_links_user_id_key" UNIQUE (user_id);

ALTER TABLE "public"."user_presence" ADD CONSTRAINT "user_presence_pkey" PRIMARY KEY (user_id);

ALTER TABLE "loopa_private"."request_budgets" ADD CONSTRAINT "request_budgets_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "loopa_private"."telegram_finished_registrations" ADD CONSTRAINT "telegram_finished_registrations_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "loopa_private"."telegram_pending_links" ADD CONSTRAINT "telegram_pending_links_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "loopa_private"."telegram_profile_imports" ADD CONSTRAINT "telegram_profile_imports_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."blocked_users" ADD CONSTRAINT "blocked_users_blocked_id_fkey" FOREIGN KEY (blocked_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."blocked_users" ADD CONSTRAINT "blocked_users_blocker_id_fkey" FOREIGN KEY (blocker_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."friend_requests" ADD CONSTRAINT "friend_requests_receiver_id_fkey" FOREIGN KEY (receiver_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."friend_requests" ADD CONSTRAINT "friend_requests_sender_id_fkey" FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_chat18" ADD CONSTRAINT "loopa_chat18_author_fkey" FOREIGN KEY (author) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_chat18" ADD CONSTRAINT "loopa_chat18_code_fkey" FOREIGN KEY (code) REFERENCES loopa_rooms16(code) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_dm_messages_v87" ADD CONSTRAINT "loopa_dm_messages_v87_recipient_id_fkey" FOREIGN KEY (recipient_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_dm_messages_v87" ADD CONSTRAINT "loopa_dm_messages_v87_sender_id_fkey" FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_history27" ADD CONSTRAINT "loopa_history27_owner_fkey" FOREIGN KEY (owner) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_invites25" ADD CONSTRAINT "loopa_invites25_code_fkey" FOREIGN KEY (code) REFERENCES loopa_rooms16(code) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_invites25" ADD CONSTRAINT "loopa_invites25_recipient_fkey" FOREIGN KEY (recipient) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_invites25" ADD CONSTRAINT "loopa_invites25_sender_fkey" FOREIGN KEY (sender) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_members16" ADD CONSTRAINT "loopa_members16_code_fkey" FOREIGN KEY (code) REFERENCES loopa_rooms16(code) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_members16" ADD CONSTRAINT "loopa_members16_member_fkey" FOREIGN KEY (member) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_playback57" ADD CONSTRAINT "loopa_playback57_code_fkey" FOREIGN KEY (code) REFERENCES loopa_rooms16(code) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_playback57" ADD CONSTRAINT "loopa_playback57_owner_fkey" FOREIGN KEY (owner) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_resume_points" ADD CONSTRAINT "loopa_resume_points_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_rooms16" ADD CONSTRAINT "loopa_rooms16_host_fkey" FOREIGN KEY (host) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_titles26" ADD CONSTRAINT "loopa_titles26_code_fkey" FOREIGN KEY (code) REFERENCES loopa_rooms16(code) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_usage27" ADD CONSTRAINT "loopa_usage27_owner_fkey" FOREIGN KEY (owner) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."loopa_usage_v87" ADD CONSTRAINT "loopa_usage_v87_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."telegram_miniapp_links" ADD CONSTRAINT "telegram_miniapp_links_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."user_presence" ADD CONSTRAINT "user_presence_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX telegram_action_budgets_expiry ON loopa_private.telegram_action_budgets USING btree (budget_until);

CREATE INDEX telegram_login_claims_expiry ON loopa_private.telegram_login_claims USING btree (expires_at);

CREATE INDEX loopa_friends_receiver_idx ON public.friend_requests USING btree (receiver_id);

CREATE INDEX loopa_friends_sender_idx ON public.friend_requests USING btree (sender_id);

CREATE UNIQUE INDEX loopa_friends_unique_pair ON public.friend_requests USING btree (LEAST(sender_id, receiver_id), GREATEST(sender_id, receiver_id));

CREATE UNIQUE INDEX loopa_account_deletion_requests_v1_active_unique ON public.loopa_account_deletion_requests_v1 USING btree (user_id) WHERE (status = ANY (ARRAY['pending'::text, 'processing'::text]));

CREATE INDEX loopa_account_deletion_requests_v1_pending_queue ON public.loopa_account_deletion_requests_v1 USING btree (requested_at) WHERE (status = 'pending'::text);

CREATE INDEX loopa_chat18_room ON public.loopa_chat18 USING btree (code, id DESC);

CREATE INDEX loopa_dm_recipient_sender_time_idx ON public.loopa_dm_messages_v87 USING btree (recipient_id, sender_id, created_at DESC);

CREATE INDEX loopa_dm_sender_recipient_time_idx ON public.loopa_dm_messages_v87 USING btree (sender_id, recipient_id, created_at DESC);

CREATE INDEX loopa_invites25_inbox ON public.loopa_invites25 USING btree (recipient, sent DESC);

CREATE INDEX loopa_members16_member_code_idx ON public.loopa_members16 USING btree (member, code);

CREATE UNIQUE INDEX loopa_user_reports_v1_open_message_unique ON public.loopa_user_reports_v1 USING btree (reporter_id, message_ref) WHERE ((status = 'open'::text) AND (message_ref IS NOT NULL));

CREATE UNIQUE INDEX loopa_user_reports_v1_open_user_unique ON public.loopa_user_reports_v1 USING btree (reporter_id, reported_user_id) WHERE ((status = 'open'::text) AND (message_ref IS NULL));

CREATE INDEX loopa_user_reports_v1_review_queue ON public.loopa_user_reports_v1 USING btree (created_at) WHERE (status = 'open'::text);

CREATE UNIQUE INDEX profiles_username_unique_v1 ON public.profiles USING btree (username) WHERE (username IS NOT NULL);

REVOKE ALL ON TABLE "loopa_private"."request_budgets" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "loopa_private"."telegram_action_budgets" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "loopa_private"."telegram_finished_registrations" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "loopa_private"."telegram_login_claims" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "loopa_private"."telegram_pending_links" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "loopa_private"."telegram_profile_imports" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."blocked_users" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."friend_requests" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_account_deletion_requests_v1" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_bot_subscriptions" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_chat18" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON SEQUENCE "public"."loopa_chat18_id_seq" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_dm_messages_v87" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON SEQUENCE "public"."loopa_dm_messages_v87_id_seq" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_history27" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_invites25" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_members16" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_playback57" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_resume_points" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_rooms16" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_titles26" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_usage27" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_usage_v87" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."loopa_user_reports_v1" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."profiles" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."telegram_miniapp_links" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE "public"."user_presence" FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."avatar_account_accepts_writes"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."can_request_friend"(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."consume_budget"(text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."find_telegram_registration"(text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."guard_avatar_account_write"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."guard_telegram_link_email"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."guard_telegram_link_insert"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."guard_telegram_registration_insert"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."limit_insert_budget"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."lock_telegram_link"(text, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."loopa_collab27"(text, text, boolean, double precision, boolean, bigint) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "loopa_private"."seed_telegram_profile"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_account_deletion_process_v1"(text, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_activity26"(text, uuid, text, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_allowed_video_url"(text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_avatar_can_read"(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_block_user"(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_claim_invite_notices"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_claim_telegram_invite"(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_claim_telegram_login"(text, bigint) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_collab27"(text, text, boolean, double precision, boolean, bigint) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_complete_telegram_registration"(text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_control_generation"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_control_v2"(text, text, bigint, double precision, boolean) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_dm_inbox"(bigint, integer) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_dm_may_send_v87"(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_dm_policy_new_profile_default_v1"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_friend_stats_v87"(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_friend_stats_v88"(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_guard_friend_update"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_history27"(text, text, text, text, text, double precision) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_invite25"(text, text, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_pair_is_blocked"(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_profiles_by_ids"(uuid[]) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_public_profiles"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_repair_telegram_profile"(text, uuid, boolean, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_request_account_deletion"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_revoke_collab_on_video_change"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_room16"(text, text, text, double precision) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_search_budget"(text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_search_profiles"(text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_submit_user_report"(uuid, text, text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_sync57"(text, text, double precision, boolean, double precision, boolean) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_take_telegram_action_budget"(text, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_telegram_link_step"(text, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_touch_resume_point_updated_at"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_unblock_user"(uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_usage_ping_v87"() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_usage_snapshot_v88"(bigint) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."loopa_visible_presence"(uuid[]) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE "public"."blocked_users" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."blocked_users" TO "service_role";

GRANT REFERENCES ON TABLE "public"."blocked_users" TO "service_role";

GRANT TRIGGER ON TABLE "public"."blocked_users" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."blocked_users" TO "service_role";

GRANT DELETE ON TABLE "public"."friend_requests" TO "authenticated";

GRANT INSERT ON TABLE "public"."friend_requests" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."friend_requests" TO "authenticated";

GRANT SELECT ON TABLE "public"."friend_requests" TO "authenticated";

GRANT UPDATE ON TABLE "public"."friend_requests" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."friend_requests" TO "service_role";

GRANT REFERENCES ON TABLE "public"."friend_requests" TO "service_role";

GRANT TRIGGER ON TABLE "public"."friend_requests" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."friend_requests" TO "service_role";

GRANT INSERT ON TABLE "public"."loopa_bot_subscriptions" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_bot_subscriptions" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_bot_subscriptions" TO "service_role";

GRANT SELECT ON TABLE "public"."loopa_bot_subscriptions" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_bot_subscriptions" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_bot_subscriptions" TO "service_role";

GRANT UPDATE ON TABLE "public"."loopa_bot_subscriptions" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_chat18" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_chat18" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_chat18" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_chat18" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_dm_messages_v87" TO "authenticated";

GRANT SELECT ON TABLE "public"."loopa_dm_messages_v87" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."loopa_dm_messages_v87" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_dm_messages_v87" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_dm_messages_v87" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_dm_messages_v87" TO "service_role";

GRANT USAGE ON SEQUENCE "public"."loopa_dm_messages_v87_id_seq" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."loopa_history27" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_history27" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_history27" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_history27" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_invites25" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_invites25" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_invites25" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_invites25" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_members16" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_members16" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_members16" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_members16" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_playback57" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_playback57" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_playback57" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_playback57" TO "service_role";

GRANT DELETE ON TABLE "public"."loopa_resume_points" TO "authenticated";

GRANT INSERT ON TABLE "public"."loopa_resume_points" TO "authenticated";

GRANT SELECT ON TABLE "public"."loopa_resume_points" TO "authenticated";

GRANT UPDATE ON TABLE "public"."loopa_resume_points" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."loopa_resume_points" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_resume_points" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_resume_points" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_resume_points" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_rooms16" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_rooms16" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_rooms16" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_rooms16" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_titles26" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_titles26" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_titles26" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_titles26" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_usage27" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_usage27" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_usage27" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_usage27" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."loopa_usage_v87" TO "service_role";

GRANT REFERENCES ON TABLE "public"."loopa_usage_v87" TO "service_role";

GRANT TRIGGER ON TABLE "public"."loopa_usage_v87" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."loopa_usage_v87" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."profiles" TO "anon";

GRANT MAINTAIN ON TABLE "public"."profiles" TO "authenticated";

GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."profiles" TO "service_role";

GRANT REFERENCES ON TABLE "public"."profiles" TO "service_role";

GRANT TRIGGER ON TABLE "public"."profiles" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."profiles" TO "service_role";

GRANT INSERT ON TABLE "public"."telegram_miniapp_links" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."telegram_miniapp_links" TO "service_role";

GRANT REFERENCES ON TABLE "public"."telegram_miniapp_links" TO "service_role";

GRANT SELECT ON TABLE "public"."telegram_miniapp_links" TO "service_role";

GRANT TRIGGER ON TABLE "public"."telegram_miniapp_links" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."telegram_miniapp_links" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."user_presence" TO "anon";

GRANT INSERT ON TABLE "public"."user_presence" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."user_presence" TO "authenticated";

GRANT SELECT ON TABLE "public"."user_presence" TO "authenticated";

GRANT UPDATE ON TABLE "public"."user_presence" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."user_presence" TO "service_role";

GRANT REFERENCES ON TABLE "public"."user_presence" TO "service_role";

GRANT TRIGGER ON TABLE "public"."user_presence" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."user_presence" TO "service_role";

GRANT INSERT ("body") ON TABLE "public"."loopa_dm_messages_v87" TO "authenticated";

GRANT INSERT ("recipient_id") ON TABLE "public"."loopa_dm_messages_v87" TO "authenticated";

GRANT INSERT ("sender_id") ON TABLE "public"."loopa_dm_messages_v87" TO "authenticated";

GRANT INSERT ("allow_friend_requests") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("allow_friend_requests") ON TABLE "public"."profiles" TO "authenticated";

GRANT INSERT ("avatar_path") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("avatar_path") ON TABLE "public"."profiles" TO "authenticated";

GRANT INSERT ("display_name") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("display_name") ON TABLE "public"."profiles" TO "authenticated";

GRANT INSERT ("dm_policy") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("dm_policy") ON TABLE "public"."profiles" TO "authenticated";

GRANT INSERT ("id") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("id") ON TABLE "public"."profiles" TO "authenticated";

GRANT INSERT ("notification_sound") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("notification_sound") ON TABLE "public"."profiles" TO "authenticated";

GRANT INSERT ("room_invite_policy") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("room_invite_policy") ON TABLE "public"."profiles" TO "authenticated";

GRANT INSERT ("updated_at") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("updated_at") ON TABLE "public"."profiles" TO "authenticated";

GRANT INSERT ("username") ON TABLE "public"."profiles" TO "authenticated";

GRANT UPDATE ("username") ON TABLE "public"."profiles" TO "authenticated";

GRANT EXECUTE ON FUNCTION "loopa_private"."can_request_friend"(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_account_deletion_process_v1"(text, uuid, uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."loopa_activity26"(text, uuid, text, text, text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_allowed_video_url"(text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_avatar_can_read"(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_block_user"(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_claim_invite_notices"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_claim_telegram_invite"(uuid, uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."loopa_claim_telegram_login"(text, bigint) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."loopa_collab27"(text, text, boolean, double precision, boolean, bigint) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_complete_telegram_registration"(text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."loopa_control_v2"(text, text, bigint, double precision, boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_dm_inbox"(bigint, integer) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_dm_may_send_v87"(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_dm_policy_new_profile_default_v1"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_dm_policy_new_profile_default_v1"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."loopa_friend_stats_v87"(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_friend_stats_v88"(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_guard_friend_update"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."loopa_history27"(text, text, text, text, text, double precision) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_invite25"(text, text, uuid, uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_pair_is_blocked"(uuid, uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_profiles_by_ids"(uuid[]) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_repair_telegram_profile"(text, uuid, boolean, text, text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."loopa_request_account_deletion"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_room16"(text, text, text, double precision) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_search_budget"(text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_search_profiles"(text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_submit_user_report"(uuid, text, text, text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_sync57"(text, text, double precision, boolean, double precision, boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_take_telegram_action_budget"(text, text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."loopa_telegram_link_step"(text, uuid, boolean) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."loopa_unblock_user"(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_usage_ping_v87"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_usage_snapshot_v88"(bigint) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."loopa_visible_presence"(uuid[]) TO "authenticated";

GRANT USAGE ON SCHEMA "loopa_private" TO "authenticated";

GRANT USAGE ON SCHEMA "public" TO PUBLIC;

GRANT USAGE ON SCHEMA "public" TO "anon";

GRANT USAGE ON SCHEMA "public" TO "authenticated";

GRANT USAGE ON SCHEMA "public" TO "postgres";

GRANT USAGE ON SCHEMA "public" TO "service_role";

CREATE TRIGGER loopa_guard_telegram_link_email BEFORE UPDATE OF email ON auth.users FOR EACH ROW WHEN ((((new.email)::text ~~ 'miniapp-link-%@auth.loopacinema.invalid'::text) AND ((new.email)::text IS DISTINCT FROM (old.email)::text))) EXECUTE FUNCTION loopa_private.guard_telegram_link_email();

CREATE TRIGGER loopa_guard_telegram_registration_insert BEFORE INSERT ON auth.users FOR EACH ROW WHEN (((new.email)::text ~~ 'miniapp-%@auth.loopacinema.invalid'::text)) EXECUTE FUNCTION loopa_private.guard_telegram_registration_insert();

CREATE TRIGGER loopa_friend_request_budget AFTER INSERT ON public.friend_requests FOR EACH ROW EXECUTE FUNCTION loopa_private.limit_insert_budget();

CREATE TRIGGER loopa_guard_friend_update_trigger BEFORE UPDATE ON public.friend_requests FOR EACH ROW EXECUTE FUNCTION loopa_guard_friend_update();

CREATE TRIGGER loopa_chat_budget AFTER INSERT ON public.loopa_chat18 FOR EACH ROW EXECUTE FUNCTION loopa_private.limit_insert_budget();

CREATE TRIGGER loopa_message_budget AFTER INSERT ON public.loopa_dm_messages_v87 FOR EACH ROW EXECUTE FUNCTION loopa_private.limit_insert_budget();

CREATE TRIGGER loopa_room_invite_budget AFTER INSERT OR UPDATE OF sent ON public.loopa_invites25 FOR EACH ROW EXECUTE FUNCTION loopa_private.limit_insert_budget();

CREATE TRIGGER loopa_resume_points_touch_updated_at BEFORE INSERT OR UPDATE ON public.loopa_resume_points FOR EACH ROW EXECUTE FUNCTION loopa_touch_resume_point_updated_at();

CREATE TRIGGER loopa_control_grant_generation BEFORE UPDATE OF shared_control ON public.loopa_rooms16 FOR EACH ROW EXECUTE FUNCTION loopa_control_generation('grant');

CREATE TRIGGER loopa_control_video_generation BEFORE UPDATE OF video ON public.loopa_rooms16 FOR EACH ROW EXECUTE FUNCTION loopa_control_generation('video');

CREATE TRIGGER loopa_revoke_collab_video BEFORE UPDATE OF video ON public.loopa_rooms16 FOR EACH ROW EXECUTE FUNCTION loopa_revoke_collab_on_video_change();

CREATE TRIGGER loopa_room_budget AFTER INSERT ON public.loopa_rooms16 FOR EACH ROW EXECUTE FUNCTION loopa_private.limit_insert_budget();

CREATE TRIGGER loopa_dm_policy_new_profile_default_v1 BEFORE INSERT ON public.profiles FOR EACH ROW EXECUTE FUNCTION loopa_dm_policy_new_profile_default_v1();

CREATE TRIGGER loopa_guard_telegram_link_insert BEFORE INSERT ON public.telegram_miniapp_links FOR EACH ROW EXECUTE FUNCTION loopa_private.guard_telegram_link_insert();

CREATE TRIGGER loopa_seed_telegram_profile AFTER INSERT ON public.telegram_miniapp_links FOR EACH ROW EXECUTE FUNCTION loopa_private.seed_telegram_profile();

CREATE POLICY "LOOPA blocks read own" ON "public"."blocked_users" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((blocker_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "LOOPA friends participants remove" ON "public"."friend_requests" AS PERMISSIVE FOR DELETE TO "authenticated" USING (((sender_id = ( SELECT auth.uid() AS uid)) OR (receiver_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "LOOPA friends read participants" ON "public"."friend_requests" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((sender_id = ( SELECT auth.uid() AS uid)) OR (receiver_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "LOOPA friends recipient accepts" ON "public"."friend_requests" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (((receiver_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text))) WITH CHECK (((receiver_id = ( SELECT auth.uid() AS uid)) AND (status = 'accepted'::text)));

CREATE POLICY "LOOPA friends send own" ON "public"."friend_requests" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((sender_id = ( SELECT auth.uid() AS uid)) AND (receiver_id <> ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text) AND (responded_at IS NULL) AND loopa_private.can_request_friend(receiver_id)));

CREATE POLICY "DM participants read" ON "public"."loopa_dm_messages_v87" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((auth.uid() = sender_id) OR (auth.uid() = recipient_id)));

CREATE POLICY "DM sender allowed" ON "public"."loopa_dm_messages_v87" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((sender_id = auth.uid()) AND loopa_dm_may_send_v87(recipient_id)));

CREATE POLICY "Users manage their own LOOPA resume points" ON "public"."loopa_resume_points" AS PERMISSIVE FOR ALL TO "authenticated" USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

CREATE POLICY "LOOPA profile create own" ON "public"."profiles" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((( SELECT auth.uid() AS uid) = id));

CREATE POLICY "LOOPA profile edit own" ON "public"."profiles" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((( SELECT auth.uid() AS uid) = id)) WITH CHECK ((( SELECT auth.uid() AS uid) = id));

CREATE POLICY "LOOPA profile read own" ON "public"."profiles" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT auth.uid() AS uid) = id));

CREATE POLICY "LOOPA presence insert own" ON "public"."user_presence" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

CREATE POLICY "LOOPA presence read own" ON "public"."user_presence" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "LOOPA presence update own" ON "public"."user_presence" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

CREATE POLICY "LOOPA avatar delete own folder" ON "storage"."objects" AS PERMISSIVE FOR DELETE TO "authenticated" USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ( SELECT (auth.uid())::text AS uid))));

CREATE POLICY "LOOPA avatar read own folder" ON "storage"."objects" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ( SELECT (auth.uid())::text AS uid))));

CREATE POLICY "LOOPA avatar update own folder" ON "storage"."objects" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ( SELECT (auth.uid())::text AS uid)))) WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ( SELECT (auth.uid())::text AS uid))));

CREATE POLICY "LOOPA avatar upload own folder" ON "storage"."objects" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ( SELECT (auth.uid())::text AS uid))));

DO $bootstrap$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_event_trigger WHERE evtname = 'ensure_rls') THEN
    CREATE EVENT TRIGGER ensure_rls ON ddl_command_end
      WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      EXECUTE FUNCTION public.rls_auto_enable();
  ELSIF NOT EXISTS (
    SELECT FROM pg_event_trigger
    WHERE evtname = 'ensure_rls' AND evtevent = 'ddl_command_end'
      AND evtfoid = 'public.rls_auto_enable()'::regprocedure
      AND evtenabled = 'O'
      AND evttags @> ARRAY['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[]
  ) THEN
    RAISE EXCEPTION 'Review the existing ensure_rls event trigger before applying the baseline';
  END IF;
END;
$bootstrap$;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']);

ALTER PUBLICATION supabase_realtime ADD TABLE public.loopa_dm_messages_v87;

COMMIT;
