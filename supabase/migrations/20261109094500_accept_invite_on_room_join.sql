-- Direct room joins must consume a matching pending room invitation.
-- Keep the existing room RPC behavior/access checks unchanged.
CREATE OR REPLACE FUNCTION public.loopa_room16(op text, room text DEFAULT ''::text, media text DEFAULT ''::text, seconds double precision DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); r public.loopa_rooms16; stamp timestamptz;
begin
 if u is null then raise exception 'Войди в аккаунт'; end if;
 room:=upper(trim(room));
 if op='list' then return coalesce((select jsonb_agg(x.code order by x.changed desc) from public.loopa_rooms16 x join public.loopa_members16 m using(code) where m.member=u and not public.loopa_pair_is_blocked(u,x.host) and (x.host=u or x.access_mode='code' or (x.access_mode='private' and u=any(x.allowed)) or (x.access_mode='friends' and exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=x.host) or (f.sender_id=x.host and f.receiver_id=u)))))),'[]'::jsonb); end if;
 if op='create' then
 insert into public.loopa_rooms16(host) values(u) returning * into r;
 insert into public.loopa_members16(code,member) values(r.code,u);
 else
 select * into r from public.loopa_rooms16 where code=room for update;
 if r.code is null or public.loopa_pair_is_blocked(u,r.host) then raise exception 'Комната недоступна'; end if;
 if u<>r.host and ((r.access_mode='friends' and not exists(select from public.friend_requests f where f.status='accepted' and ((f.sender_id=u and f.receiver_id=r.host) or (f.sender_id=r.host and f.receiver_id=u)))) or (r.access_mode='private' and not(u=any(r.allowed)))) then raise exception 'Комната недоступна'; end if;
 if op='join' then insert into public.loopa_members16(code,member) values(room,u) on conflict do nothing;
 -- An actual successful join also accepts the host's outstanding room invite,
 -- even if the user entered through a Telegram startapp/deep link or room code.
 -- This runs after access checks and membership insert, inside one transaction.
 update public.loopa_invites25 v
   set status='accepted'
   where v.code=r.code and v.recipient=u and v.sender=r.host
     and v.status='pending' and v.sent>now()-interval '24 hours';
 elsif not exists(select from public.loopa_members16 where code=room and member=u) then raise exception 'Нет доступа'; end if;
 if op in ('video','play','pause') then
 if r.host<>u then raise exception 'Управлять может ведущий'; end if;
 if op='video' and length(media) not between 10 and 1500 then raise exception 'Проверь ссылку'; end if;
 if seconds not between 0 and 864000 then raise exception 'Проверь время'; end if;
 update public.loopa_rooms16 set video=case when op='video' then media else video end,playing=op='play',pos=case when op='video' then 0 else seconds end,changed=clock_timestamp() where code=room returning * into r;
 elsif op='chat' then
 if length(trim(media)) not between 1 and 1000 then raise exception 'Сообщение: от 1 до 1000 символов'; end if;
 insert into public.loopa_chat18(code,author,body) values(room,u,trim(media));
 elsif op='access' then
 if u<>r.host or coalesce(media::jsonb->>'mode','') not in ('code','friends','private') then raise exception 'Нет доступа'; end if;
 update public.loopa_rooms16 set access_mode=media::jsonb->>'mode',allowed=array(select value::uuid from jsonb_array_elements_text(media::jsonb->'ids')) where code=room returning * into r;
 elsif op not in ('join','read') then raise exception 'Неизвестная команда'; end if;
 end if;
 update public.loopa_members16 set seen=clock_timestamp() where code=r.code and member=u;
 stamp:=clock_timestamp();
 return (to_jsonb(r)-'allowed')||jsonb_build_object('allowed',case when u=r.host then r.allowed else '{}'::uuid[] end,'server_time',stamp,
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.member,'name',coalesce(p.display_name,'Участник'),'online',coalesce(m.seen>stamp-interval '20 seconds',false))) from public.loopa_members16 m left join public.profiles p on p.id=m.member where m.code=r.code),'[]'::jsonb),
 'chat',coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from(select c.id,c.author,c.body,c.sent,p.display_name as name from public.loopa_chat18 c left join public.profiles p on p.id=c.author where c.code=r.code order by c.id desc limit 60)t),'[]'::jsonb));
end $function$;

-- Reconcile prior Telegram direct joins: a recipient activity timestamp
-- after the invite's send time confirms they were in the same room afterwards.
-- Do not touch other rooms or invitations with no post-invite room activity.
update public.loopa_invites25 v
set status='accepted'
from public.loopa_members16 m, public.loopa_rooms16 r
where v.status='pending' and v.sent>now()-interval '24 hours'
  and m.code=v.code and m.member=v.recipient and m.seen>v.sent
  and r.code=v.code and r.host=v.sender;
