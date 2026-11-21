begin;

create function loopa_private.seed_telegram_profile()
returns trigger language plpgsql security definer set search_path = ''
as $$
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
    and u.raw_app_meta_data->>'loopa_telegram_registration' = new.telegram_id;
  if not found then return new; end if;

  v_name := coalesce(nullif(v_name, ''), 'Участник LOOPA');
  if v_username !~ '^[a-z][a-z0-9_]{3,15}$' then v_username := null; end if;
  select o.name into v_avatar from storage.objects o
  where o.bucket_id = 'avatars' and o.name = new.user_id::text || '/avatar.jpg';

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
  return new;
end;
$$;
revoke all on function loopa_private.seed_telegram_profile() from public, anon, authenticated, service_role;

create trigger loopa_seed_telegram_profile
after insert on public.telegram_miniapp_links
for each row execute function loopa_private.seed_telegram_profile();

commit;
