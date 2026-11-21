begin;

set local lock_timeout = '3s';

alter table loopa_private.request_budgets
  drop constraint request_budgets_scope_check,
  add constraint request_budgets_scope_check
  check (scope in ('message','room_create','search','suggest','friend_request','room_invite'));

CREATE OR REPLACE FUNCTION loopa_private.consume_budget(p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid(); v_capacity double precision; v_rate double precision;
 v_tokens double precision; v_updated timestamptz; v_now timestamptz;
begin
 if v_user is null then raise exception 'Войди в аккаунт'; end if;
 case p_scope
  when 'message' then v_capacity:=8; v_rate:=1;
  when 'room_create' then v_capacity:=5; v_rate:=1.0/12;
  when 'friend_request' then v_capacity:=5; v_rate:=1.0/12;
  when 'room_invite' then v_capacity:=20; v_rate:=1.0/3;
  when 'search' then v_capacity:=10; v_rate:=1.0/3;
  when 'suggest' then v_capacity:=30; v_rate:=10;
  else raise exception 'Неизвестный лимит';
 end case;
 insert into loopa_private.request_budgets(user_id,scope,tokens,updated_at)
 values(v_user,p_scope,v_capacity,clock_timestamp()) on conflict do nothing;
 select tokens,updated_at into v_tokens,v_updated
 from loopa_private.request_budgets where user_id=v_user and scope=p_scope for update;
 v_now:=clock_timestamp();
 v_tokens:=least(v_capacity,v_tokens+greatest(0,extract(epoch from v_now-v_updated))*v_rate);
 if v_tokens<1 then
  update loopa_private.request_budgets set tokens=v_tokens,updated_at=v_now
  where user_id=v_user and scope=p_scope;
  return jsonb_build_object('allowed',false,'retry_after',greatest(1,ceil((1-v_tokens)/v_rate)::integer));
 end if;
 update loopa_private.request_budgets set tokens=v_tokens-1,updated_at=v_now
 where user_id=v_user and scope=p_scope;
 return jsonb_build_object('allowed',true,'retry_after',0);
end $function$;

CREATE OR REPLACE FUNCTION loopa_private.limit_insert_budget()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb; v_scope text;
begin
 -- Trusted maintenance without an end-user JWT is unaffected.
 if auth.uid() is null then return new; end if;
 v_scope:=case tg_table_name
  when 'loopa_rooms16' then 'room_create'
  when 'friend_requests' then 'friend_request'
  when 'loopa_invites25' then 'room_invite'
  else 'message'
 end;
 v_result:=loopa_private.consume_budget(v_scope);
 if not (v_result->>'allowed')::boolean then
  raise exception using errcode='P0001',message=case v_scope
   when 'message' then 'Слишком много сообщений. Подожди немного и отправь снова.'
   when 'friend_request' then 'Слишком много заявок в друзья. Подожди немного и попробуй снова.'
   when 'room_invite' then 'Слишком много приглашений. Подожди немного и попробуй снова.'
   else 'Слишком часто создаёшь комнаты. Подожди немного и попробуй снова.'
  end;
 end if;
 return new;
end $function$;

create trigger loopa_friend_request_budget after insert on public.friend_requests
  for each row execute function loopa_private.limit_insert_budget();

-- Count both the first send and a resend. Accepting or notifying does not edit sent.
create trigger loopa_room_invite_budget after insert or update of sent on public.loopa_invites25
  for each row execute function loopa_private.limit_insert_budget();

commit;
