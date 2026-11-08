-- Add safe video thumbnail data to the existing invite inbox RPC.
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
