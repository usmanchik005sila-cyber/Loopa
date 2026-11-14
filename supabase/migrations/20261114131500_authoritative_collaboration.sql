-- LOOPA server-authoritative shared control. Apply before publishing the corresponding site build.
-- Eliminates trust in client-authored Realtime Broadcast identity and control messages.
-- The room creator keeps the only permission to toggle shared mode.
begin;
alter table public.loopa_rooms16
  add column if not exists shared_control boolean not null default false;

create or replace function public.loopa_collab27(
  action text, room_code text, enabled boolean default null,
  position_seconds double precision default null, is_playing boolean default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $fn$
declare
  actor uuid := auth.uid();
  room_row public.loopa_rooms16;
  code text := upper(trim(room_code));
begin
  if actor is null then raise exception 'Войди в аккаунт'; end if;
  select * into room_row from public.loopa_rooms16 r where r.code=code for update;
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
    where m.code=code and m.member=actor and m.seen>now()-interval '45 seconds'
  ) then raise exception 'Нет активного участия в комнате'; end if;

  if action='mode' then
    if room_row.host<>actor or enabled is null then raise exception 'Управлять режимом может только создатель'; end if;
    update public.loopa_rooms16 r set shared_control=enabled where r.code=code;
    return jsonb_build_object('shared_control',enabled);
  elsif action='control' then
    if room_row.host=actor then raise exception 'Создатель использует штатное управление'; end if;
    if not room_row.shared_control or room_row.video='' then raise exception 'Совместное управление выключено'; end if;
    if position_seconds is null or position_seconds not between 0 and 864000 or is_playing is null then
      raise exception 'Некорректная позиция';
    end if;
    update public.loopa_rooms16 r
      set pos=position_seconds,playing=is_playing,changed=clock_timestamp()
      where r.code=code;
    insert into public.loopa_playback57(code,video,pos,playing,stamp,owner)
      values(code,room_row.video,position_seconds,is_playing,clock_timestamp(),room_row.host)
      on conflict(code) do update set
        video=excluded.video,pos=excluded.pos,playing=excluded.playing,
        stamp=excluded.stamp,owner=excluded.owner;
    return jsonb_build_object('ok',true,'pos',position_seconds,'playing',is_playing);
  else
    raise exception 'Неизвестная команда';
  end if;
end
$fn$;

revoke all on function public.loopa_collab27(text,text,boolean,double precision,boolean) from public, anon;
grant execute on function public.loopa_collab27(text,text,boolean,double precision,boolean) to authenticated;
commit;
