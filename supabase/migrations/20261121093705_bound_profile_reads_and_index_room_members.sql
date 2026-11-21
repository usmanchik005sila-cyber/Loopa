begin;

set local lock_timeout = '3s';

create index loopa_members16_member_code_idx on public.loopa_members16 (member, code);

alter table loopa_private.request_budgets
  drop constraint request_budgets_scope_check,
  add constraint request_budgets_scope_check
  check (scope in ('message','room_create','search','suggest','friend_request','room_invite','user_search'));

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
  when 'user_search' then v_capacity:=10; v_rate:=1.0/3;
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

create function public.loopa_profiles_by_ids(p_ids uuid[])
returns table(id uuid, display_name text, username text, avatar_path text, updated_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.display_name, p.username,
    case when not public.loopa_pair_is_blocked((select auth.uid()), p.id) then p.avatar_path end,
    p.updated_at
  from public.profiles p
  where (select auth.uid()) is not null
    and cardinality(p_ids) between 1 and 150
    and p.id = any(p_ids);
$$;

create function public.loopa_search_profiles(p_term text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  needle text := lower(btrim(p_term));
  handle text := btrim(regexp_replace(needle, '^@', ''));
  budget jsonb;
  exact_id uuid;
  results jsonb;
begin
  if viewer is null then raise exception 'Войди в аккаунт'; end if;
  if needle is null or char_length(needle) not between 2 and 40 then
    return jsonb_build_object('profiles', '[]'::jsonb);
  end if;

  budget := loopa_private.consume_budget('user_search');
  if (budget->>'allowed')::boolean is distinct from true then
    return jsonb_build_object('profiles', '[]'::jsonb, 'retry_after', budget->'retry_after');
  end if;

  if handle ~ '^[a-z][a-z0-9_]{3,15}$' then
    select p.id into exact_id from public.profiles p
    where p.username = handle and p.id <> viewer and not exists (
      select 1 from public.blocked_users b where b.blocker_id = viewer and b.blocked_id = p.id
    );
  end if;

  with candidates as (
    select exact_id as id, 0 as rank where exact_id is not null
    union all
    select matches.id, 1 from (
      select p.id from public.profiles p
      where p.id <> viewer and p.id is distinct from exact_id
        and strpos(lower(p.display_name), needle) > 0 and not exists (
          select 1 from public.blocked_users b where b.blocker_id = viewer and b.blocked_id = p.id
        )
      order by p.id limit 15
    ) matches
  )
  select coalesce(jsonb_agg(to_jsonb(p) order by c.rank, p.id), '[]'::jsonb) into results
  from public.loopa_profiles_by_ids(array(select c.id from candidates c)) p
  join candidates c on c.id = p.id;
  return jsonb_build_object('profiles', results);
end;
$$;

revoke all on function public.loopa_profiles_by_ids(uuid[]), public.loopa_search_profiles(text) from public, anon;
grant execute on function public.loopa_profiles_by_ids(uuid[]), public.loopa_search_profiles(text) to authenticated;

notify pgrst, 'reload schema';
commit;
