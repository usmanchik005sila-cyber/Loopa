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

create function loopa_private.guard_telegram_link_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform loopa_private.lock_telegram_link(new.telegram_id, new.user_id);
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

notify pgrst, 'reload schema';
commit;
