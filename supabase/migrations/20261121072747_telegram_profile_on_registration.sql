begin;

create table loopa_private.telegram_profile_imports (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table loopa_private.telegram_profile_imports enable row level security;
revoke all on loopa_private.telegram_profile_imports from public, anon, authenticated, service_role;

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
$$;
revoke all on function loopa_private.seed_telegram_profile() from public, anon, authenticated, service_role;

create trigger loopa_seed_telegram_profile
after insert on public.telegram_miniapp_links
for each row execute function loopa_private.seed_telegram_profile();

-- Complete the import for Telegram accounts created before this migration.
-- The Edge Function has already authenticated the signed Telegram payload.
create function public.loopa_repair_telegram_profile(
  p_telegram_id text, p_user_id uuid, p_apply boolean,
  p_display_name text default null, p_username text default null
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
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
$$;
revoke all on function public.loopa_repair_telegram_profile(text,uuid,boolean,text,text) from public, anon, authenticated;
grant execute on function public.loopa_repair_telegram_profile(text,uuid,boolean,text,text) to service_role;
notify pgrst,'reload schema';
commit;
