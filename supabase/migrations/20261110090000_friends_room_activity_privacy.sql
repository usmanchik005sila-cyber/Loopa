-- LOOPA: friends-only activity. Default OFF, no room code or video URL leaked.
-- The existing friend activity RPC is restricted server-side for BOTH listing and joining.
ALTER TABLE public.user_presence
  ADD COLUMN IF NOT EXISTS share_room_activity boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.user_presence.share_room_activity IS
  'Opt-in to showing friends whether the user is in a room or watching video';

CREATE OR REPLACE FUNCTION public.loopa_activity26(action text, peer uuid DEFAULT NULL::uuid, room_code text DEFAULT ''::text, media text DEFAULT ''::text, title text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); chosen public.loopa_rooms16;
begin
 if u is null then raise exception 'Войди в аккаунт'; end if;
 if action='title' then
 select * into chosen from public.loopa_rooms16 where code=room_code for update;
 if chosen.host is distinct from u or chosen.video<>media or length(trim(title)) not between 1 and 200 then raise exception 'Нет доступа'; end if;
 insert into public.loopa_titles26 values(room_code,media,trim(title)) on conflict(code) do update set video=excluded.video,title=excluded.title;
 return '{}'::jsonb;
 elsif action='friends' then
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'private',rm.access_mode='private' and not(u=any(rm.allowed)) and rm.host<>u,'state',case when rm.video<>'' then 'watching' else 'in_room' end,'title',case when rm.video='' or rm.access_mode='private' and not(u=any(rm.allowed)) and rm.host<>u then null else coalesce(t.title,'Видео') end)) from public.profiles p join lateral (select r.* from public.loopa_members16 m join public.loopa_rooms16 r on r.code=m.code where m.member=p.id and m.seen>now()-interval '25 seconds' and not public.loopa_pair_is_blocked(u,r.host) order by m.seen desc limit 1) rm on true left join public.loopa_titles26 t on t.code=rm.code and t.video=rm.video where p.id<>u and not public.loopa_pair_is_blocked(u,p.id) and exists(select from public.user_presence pr where pr.user_id=p.id and pr.visible and pr.share_room_activity and pr.last_active_at>now()-interval '90 seconds') and exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=p.id) or (f.sender_id=p.id and f.receiver_id=u)))),'[]'::jsonb);
 elsif action='join' then
 if peer is null or public.loopa_pair_is_blocked(u,peer) or not exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=peer) or (f.sender_id=peer and f.receiver_id=u))) or not exists(select from public.user_presence pr where pr.user_id=peer and pr.visible and pr.share_room_activity and pr.last_active_at>now()-interval '90 seconds') then raise exception 'Просмотр недоступен'; end if;
 select r.* into chosen from public.loopa_members16 m join public.loopa_rooms16 r on r.code=m.code where m.member=peer and m.seen>now()-interval '25 seconds' and r.video<>'' order by m.seen desc limit 1;
 if chosen.code is null then raise exception 'Друг уже завершил просмотр'; end if;
 if chosen.access_mode='private' and chosen.host<>u and not(u=any(chosen.allowed)) then raise exception 'Друг смотрит в приватной комнате. Войти можно по приглашению'; end if;
 return public.loopa_room16('join',chosen.code);
 end if;
 raise exception 'Неизвестная команда';
end $function$;
