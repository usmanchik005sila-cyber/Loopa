begin;

create table loopa_private.telegram_pending_links (
  telegram_id text primary key check (telegram_id ~ '^[1-9][0-9]{0,15}$'),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  started_at timestamptz not null default clock_timestamp()
);
alter table loopa_private.telegram_pending_links enable row level security;
revoke all on loopa_private.telegram_pending_links from public, anon, authenticated, service_role;

-- Acquire both keys in the same order for reservations and active inserts.
create function loopa_private.lock_telegram_link(p_telegram_id text, p_user_id uuid)
returns void language plpgsql set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(171406, hashtext(p_telegram_id));
  perform pg_advisory_xact_lock(171407, hashtext(p_user_id::text));
end;
$$;
revoke all on function loopa_private.lock_telegram_link(text, uuid) from public, anon, authenticated, service_role;

-- Keep the consumption record for as long as the Auth account exists.
-- A later unlink must never make a completed registration recoverable again.
create table loopa_private.telegram_finished_registrations (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table loopa_private.telegram_finished_registrations enable row level security;
revoke all on loopa_private.telegram_finished_registrations from public, anon, authenticated, service_role;

create function loopa_private.find_telegram_registration(p_telegram_id text)
returns uuid language sql stable set search_path = ''
as $$
  select u.id from auth.users u
  where u.email = 'miniapp-' || p_telegram_id || '@auth.loopacinema.invalid'
    and u.raw_app_meta_data->>'loopa_telegram_registration' = p_telegram_id
    and u.email_confirmed_at is not null
    and not exists (select 1 from loopa_private.telegram_finished_registrations f where f.user_id = u.id);
$$;
revoke all on function loopa_private.find_telegram_registration(text) from public, anon, authenticated, service_role;

create function loopa_private.guard_telegram_link_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
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
$$;
revoke all on function loopa_private.guard_telegram_link_insert() from public, anon, authenticated, service_role;

create trigger loopa_guard_telegram_link_insert
before insert on public.telegram_miniapp_links
for each row execute function loopa_private.guard_telegram_link_insert();

create function public.loopa_telegram_link_step(p_telegram_id text, p_user_id uuid, p_finish boolean)
returns text language plpgsql security definer set search_path = ''
as $$
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
$$;
revoke all on function public.loopa_telegram_link_step(text, uuid, boolean) from public, anon, authenticated;
grant execute on function public.loopa_telegram_link_step(text, uuid, boolean) to service_role;

-- GoTrue Admin updates the email and its identity in one transaction. This
-- guard sees the current row under its write lock and rolls back the whole
-- operation if a real email was added while the Edge function was in flight.
create function loopa_private.guard_telegram_link_email()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if nullif(old.email, '') is not null
     or new.email <> 'miniapp-link-' || new.id::text || '@auth.loopacinema.invalid'
     or not exists (select 1 from loopa_private.telegram_pending_links p where p.user_id = new.id) then
    raise check_violation using message = 'Telegram link email update rejected';
  end if;
  return new;
end;
$$;
revoke all on function loopa_private.guard_telegram_link_email() from public, anon, authenticated, service_role;

create trigger loopa_guard_telegram_link_email
before update of email on auth.users
for each row
when (new.email like 'miniapp-link-%@auth.loopacinema.invalid' and new.email is distinct from old.email)
execute function loopa_private.guard_telegram_link_email();

-- An Auth registration and an explicit link must not start for the same
-- Telegram account. Auth holds this lock through creation and confirmation.
create function loopa_private.guard_telegram_registration_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
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
$$;
revoke all on function loopa_private.guard_telegram_registration_insert() from public, anon, authenticated, service_role;

create trigger loopa_guard_telegram_registration_insert
before insert on auth.users
for each row when (new.email like 'miniapp-%@auth.loopacinema.invalid')
execute function loopa_private.guard_telegram_registration_insert();

-- Recover the UUID after a lost Auth or PostgREST response. Only accounts
-- tagged by Auth Admin during this registration flow are eligible.
create function public.loopa_complete_telegram_registration(p_telegram_id text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
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
$$;
revoke all on function public.loopa_complete_telegram_registration(text) from public, anon, authenticated;
grant execute on function public.loopa_complete_telegram_registration(text) to service_role;

notify pgrst, 'reload schema';
commit;
