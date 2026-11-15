-- Require an explicit current-video grant for guest playback control.
-- Permission expires 30 seconds after the host disconnects and is refreshed by host RPC.
-- Clear legacy grants, including any grant left enabled by a previous viewing.
begin;
alter table public.loopa_rooms16
  add column if not exists shared_control_video text not null default '',
  add column if not exists shared_control_until timestamptz;
update public.loopa_rooms16 set
  shared_control=false,shared_control_video='',shared_control_until=null,
  control_applied_seq=control_seq
where shared_control=true;

CREATE OR REPLACE FUNCTION public.loopa_collab27(action text, room_code text, enabled boolean DEFAULT NULL::boolean, position_seconds double precision DEFAULT NULL::double precision, is_playing boolean DEFAULT NULL::boolean, sequence bigint DEFAULT NULL::bigint)
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

create or replace function public.loopa_revoke_collab_on_video_change()
returns trigger language plpgsql security invoker set search_path = ''
as $trigger$
begin
  if new.video is distinct from old.video then
    new.shared_control=false;
    new.shared_control_video='';
    new.shared_control_until=null;
    new.control_applied_seq=new.control_seq;
  end if;
  return new;
end
$trigger$;
drop trigger if exists loopa_revoke_collab_video on public.loopa_rooms16;
create trigger loopa_revoke_collab_video
before update of video on public.loopa_rooms16
for each row execute function public.loopa_revoke_collab_on_video_change();
revoke all on function public.loopa_revoke_collab_on_video_change() from public, anon, authenticated;
notify pgrst, 'reload schema';
commit;
