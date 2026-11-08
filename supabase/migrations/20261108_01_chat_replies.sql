BEGIN;

    ALTER TABLE public.loopa_chat18
      ADD COLUMN IF NOT EXISTS reply_to text;

    CREATE OR REPLACE FUNCTION public.loopa_room16(
      op text,
      room text DEFAULT ''::text,
      media text DEFAULT ''::text,
      seconds double precision DEFAULT 0
    )
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO ''
    AS $function$
    declare
      u uuid := auth.uid();
      r public.loopa_rooms16;
      stamp timestamptz;
      chat_payload jsonb;
      chat_body text;
      chat_reply_to text;
    begin
      if u is null then raise exception 'Войди в аккаунт'; end if;
      room := upper(trim(room));

      if op = 'list' then
        return coalesce((
          select jsonb_agg(x.code order by x.changed desc)
          from public.loopa_rooms16 x
          join public.loopa_members16 m using (code)
          where m.member = u
            and not public.loopa_pair_is_blocked(u, x.host)
            and (x.host = u or x.access_mode = 'code'
              or (x.access_mode = 'private' and u = any(x.allowed))
              or (x.access_mode = 'friends' and exists (
                select from public.friend_requests f
                where f.status = 'accepted'
                  and ((f.sender_id = u and f.receiver_id = x.host)
                    or (f.sender_id = x.host and f.receiver_id = u))
              )))
        ), '[]'::jsonb);
      end if;

      if op = 'create' then
        insert into public.loopa_rooms16(host) values (u) returning * into r;
        insert into public.loopa_members16(code, member) values (r.code, u);
      else
        select * into r from public.loopa_rooms16 where code = room for update;
        if r.code is null or public.loopa_pair_is_blocked(u, r.host) then
          raise exception 'Комната недоступна';
        end if;
        if u <> r.host and (
          (r.access_mode = 'friends' and not exists (
            select from public.friend_requests f
            where f.status = 'accepted'
              and ((f.sender_id = u and f.receiver_id = r.host)
                or (f.sender_id = r.host and f.receiver_id = u))
          ))
          or (r.access_mode = 'private' and not (u = any(r.allowed)))
        ) then raise exception 'Комната недоступна'; end if;

        if op = 'join' then
          insert into public.loopa_members16(code, member) values (room, u) on conflict do nothing;
        elsif not exists (select from public.loopa_members16 where code = room and member = u) then
          raise exception 'Нет доступа';
        end if;

        if op in ('video', 'play', 'pause') then
          if r.host <> u then raise exception 'Управлять может ведущий'; end if;
          if op = 'video' and length(media) not between 10 and 1500 then raise exception 'Проверь ссылку'; end if;
          if seconds not between 0 and 864000 then raise exception 'Проверь время'; end if;
          update public.loopa_rooms16
          set video = case when op = 'video' then media else video end,
              playing = op = 'play',
              pos = case when op = 'video' then 0 else seconds end,
              changed = clock_timestamp()
          where code = room returning * into r;
        elsif op = 'chat' then
          chat_payload := null;
          if left(trim(media), 1) = '{' then
            begin
              chat_payload := trim(media)::jsonb;
            exception when others then
              chat_payload := null;
            end;
          end if;
          if chat_payload->>'_loopa_reply_v1' = '1' then
            chat_body := trim(coalesce(chat_payload->>'body', ''));
            chat_reply_to := nullif(chat_payload->>'reply_to', '');
          else
            chat_body := trim(media);
            chat_reply_to := null;
          end if;
          if length(chat_body) not between 1 and 1000 then
            raise exception 'Сообщение: от 1 до 1000 символов';
          end if;
          if chat_reply_to is not null and not exists (
            select 1 from public.loopa_chat18 c
            where c.code = room and c.id::text = chat_reply_to
          ) then raise exception 'Исходное сообщение недоступно'; end if;
          insert into public.loopa_chat18(code, author, body, reply_to)
          values (room, u, chat_body, chat_reply_to);
        elsif op = 'access' then
          if u <> r.host or coalesce(media::jsonb->>'mode', '') not in ('code', 'friends', 'private') then
            raise exception 'Нет доступа';
          end if;
          update public.loopa_rooms16
          set access_mode = media::jsonb->>'mode',
              allowed = array(select value::uuid from jsonb_array_elements_text(media::jsonb->'ids'))
          where code = room returning * into r;
        elsif op not in ('join', 'read') then
          raise exception 'Неизвестная команда';
        end if;
      end if;

      update public.loopa_members16 set seen = clock_timestamp() where code = r.code and member = u;
      stamp := clock_timestamp();
      return (to_jsonb(r)-'allowed') || jsonb_build_object(
        'allowed', case when u = r.host then r.allowed else '{}'::uuid[] end,
        'server_time', stamp,
        'members', coalesce((
          select jsonb_agg(jsonb_build_object('id', m.member, 'name', coalesce(p.display_name, 'Участник'), 'online', coalesce(m.seen > stamp - interval '20 seconds', false)))
          from public.loopa_members16 m
          left join public.profiles p on p.id = m.member
          where m.code = r.code
        ), '[]'::jsonb),
        'chat', coalesce((
          select jsonb_agg(to_jsonb(t) order by t.id)
          from (
            select c.id, c.author, c.body, c.sent, c.reply_to, p.display_name as name,
              case when parent.id is null then null else jsonb_build_object(
                'id', parent.id, 'author', parent.author, 'body', parent.body,
                'name', coalesce(parent_profile.display_name, 'Участник')
              ) end as reply
            from public.loopa_chat18 c
            left join public.profiles p on p.id = c.author
            left join public.loopa_chat18 parent on parent.code = c.code and parent.id::text = c.reply_to
            left join public.profiles parent_profile on parent_profile.id = parent.author
            where c.code = r.code
            order by c.id desc limit 60
          ) t
        ), '[]'::jsonb)
      );
    end
    $function$;

    COMMIT;
    