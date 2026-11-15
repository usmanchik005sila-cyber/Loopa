-- Emergency SQL rollback for PR #83. Restore site to pre-#83 main FIRST.
-- This removes only PR #83 collaboration metadata and restores former sync RPC.
begin;
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
  insert into public.loopa_playback57(code,video,pos,playing,stamp,owner)
  values(room_code,media,position_seconds+case when is_playing then sample_age else 0 end,is_playing,t,u)
  on conflict(code) do update set video=excluded.video,pos=excluded.pos,playing=excluded.playing,stamp=excluded.stamp,owner=excluded.owner;
 end if;
 select * into snap from public.loopa_playback57 where code=room_code;
 if snap.code is null or snap.video<>r.video or snap.owner<>r.host then return jsonb_build_object('ready',false); end if;
 return jsonb_build_object('ready',true,'video',snap.video,'pos',snap.pos,'playing',snap.playing,'age',greatest(0,extract(epoch from clock_timestamp()-snap.stamp)));
end $function$;
drop function if exists public.loopa_collab27(text,text,boolean,double precision,boolean,bigint);
alter table public.loopa_rooms16
  drop column if exists shared_control,
  drop column if exists control_seq,
  drop column if exists control_applied_seq,
  drop column if exists control_pos,
  drop column if exists control_playing,
  drop column if exists control_video,
  drop column if exists control_at,
  drop column if exists control_actor;
notify pgrst, 'reload schema';
commit;
