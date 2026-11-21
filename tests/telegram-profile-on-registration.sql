-- Run in an isolated database after applying telegram_profile_on_registration.
begin;
do $test$
declare
  existing_user uuid := gen_random_uuid();
  new_user uuid := gen_random_uuid();
  next_user uuid := gen_random_uuid();
  unmarked uuid := gen_random_uuid();
  legacy_user uuid := gen_random_uuid();
  handle text := 't' || left(replace(gen_random_uuid()::text,'-',''),12);
begin
  insert into auth.users(id,raw_app_meta_data,raw_user_meta_data) values
    (existing_user,jsonb_build_object('loopa_telegram_registration','27101', 'loopa_telegram_username',handle,'loopa_telegram_profile_seed',true),'{"display_name":"Telegram Name"}'),
    (new_user,jsonb_build_object('loopa_telegram_registration','27102', 'loopa_telegram_username',handle,'loopa_telegram_profile_seed',true),'{"display_name":"Новое имя"}'),
    (next_user,jsonb_build_object('loopa_telegram_registration','27103', 'loopa_telegram_username','another_fixture','loopa_telegram_profile_seed',true),'{"display_name":"Второе имя"}'),
    (unmarked,'{}','{"display_name":"Unmarked"}'),
    (legacy_user,'{"loopa_telegram_registration":"27105"}','{"display_name":"Участник LOOPA"}');
  insert into public.profiles(id,display_name,username)
    values(existing_user,'Мой профиль',handle),(legacy_user,'Участник LOOPA','my_own_handle');
  insert into storage.objects(bucket_id,name) values('avatars',next_user::text || '/telegram-avatar.jpg');
  insert into public.telegram_miniapp_links(telegram_id,user_id)
    values('27101',existing_user),('27102',new_user),('27103',next_user),('27104',unmarked),('27105',legacy_user);

  if not exists (select 1 from public.profiles where id=existing_user and display_name='Мой профиль' and username=handle)
    or not exists (select 1 from public.profiles where id=new_user and display_name='Новое имя' and username is null)
    or not exists (select 1 from public.profiles where id=next_user and display_name='Второе имя' and username='another_fixture'
      and avatar_path=next_user::text || '/telegram-avatar.jpg')
    or exists (select 1 from public.profiles where id=unmarked) then
    raise exception 'Telegram profile import did not preserve existing profiles or username rules';
  end if;
  insert into storage.objects(bucket_id,name) values('avatars',legacy_user::text || '/telegram-avatar.jpg');
  if public.loopa_repair_telegram_profile('27105',legacy_user,false)->>'eligible' is distinct from 'true'
     or public.loopa_repair_telegram_profile('27104',legacy_user,false)->>'eligible' is distinct from 'false' then
    raise exception 'Repair was not limited to the matching linked account';
  end if;
  if public.loopa_repair_telegram_profile('27105',legacy_user,true,'Имя Telegram','telegram_name')->>'imported' is distinct from 'true' then
    raise exception 'Legacy defaults were not restored from Telegram';
  end if;
  if not exists (select 1 from public.profiles where id=legacy_user and display_name='Имя Telegram'
      and username='my_own_handle' and avatar_path=legacy_user::text || '/telegram-avatar.jpg')
     or public.loopa_repair_telegram_profile('27105',legacy_user,false)->>'eligible' is distinct from 'false' then
    raise exception 'Repair modified a chosen nickname or was repeated';
  end if;
end $test$;
rollback;
