-- Shared, bounded per-account budgets. Persisted and locked in Postgres so
-- concurrent API calls and separate Edge isolates share the same allowance.
create table loopa_private.request_budgets (
 user_id uuid not null references auth.users(id) on delete cascade,
 scope text not null check(scope in ('message','room_create','search','suggest')),
 tokens double precision not null,
 updated_at timestamptz not null,
 primary key(user_id,scope)
);
alter table loopa_private.request_budgets enable row level security;
revoke all on loopa_private.request_budgets from public,anon,authenticated;

create function loopa_private.consume_budget(p_scope text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid(); v_capacity double precision; v_rate double precision;
 v_tokens double precision; v_updated timestamptz; v_now timestamptz;
begin
 if v_user is null then raise exception 'Войди в аккаунт'; end if;
 case p_scope
  when 'message' then v_capacity:=8; v_rate:=1;
  when 'room_create' then v_capacity:=5; v_rate:=1.0/12;
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
end $$;
revoke all on function loopa_private.consume_budget(text) from public,anon,authenticated;

create function public.loopa_search_budget(p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_mode not in ('search','suggest') or p_mode is null then raise exception 'Неизвестный режим'; end if;
 return loopa_private.consume_budget(p_mode);
end $$;
revoke all on function public.loopa_search_budget(text) from public,anon;
grant execute on function public.loopa_search_budget(text) to authenticated;

create function loopa_private.limit_insert_budget()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_result jsonb; v_scope text;
begin
 -- Trusted maintenance without an end-user JWT is unaffected.
 if auth.uid() is null then return new; end if;
 v_scope:=case when tg_table_name='loopa_rooms16' then 'room_create' else 'message' end;
 v_result:=loopa_private.consume_budget(v_scope);
 if not (v_result->>'allowed')::boolean then
  raise exception using errcode='P0001',message=case when v_scope='message'
   then 'Слишком много сообщений. Подожди немного и отправь снова.'
   else 'Слишком часто создаёшь комнаты. Подожди немного и попробуй снова.' end;
 end if;
 return new;
end $$;
revoke all on function loopa_private.limit_insert_budget() from public,anon,authenticated;
create trigger loopa_message_budget after insert on public.loopa_dm_messages_v87
 for each row execute function loopa_private.limit_insert_budget();
create trigger loopa_chat_budget after insert on public.loopa_chat18
 for each row execute function loopa_private.limit_insert_budget();
create trigger loopa_room_budget after insert on public.loopa_rooms16
 for each row execute function loopa_private.limit_insert_budget();

notify pgrst, 'reload schema';
