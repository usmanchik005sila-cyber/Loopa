begin;

-- Keep the existing authorization and state transitions, but make the
-- implementation inaccessible through the public RPC.
alter function public.loopa_collab27(text,text,boolean,double precision,boolean,bigint)
  set schema loopa_private;
revoke all on function loopa_private.loopa_collab27(text,text,boolean,double precision,boolean,bigint)
  from public, anon, authenticated, service_role;

create function public.loopa_collab27(
  action text, room_code text, enabled boolean default null,
  position_seconds double precision default null, is_playing boolean default null,
  sequence bigint default null
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if action is null or action not in ('mode', 'renew', 'pull', 'ack') then
    raise exception 'Команда недоступна. Обнови LOOPA';
  end if;
  return loopa_private.loopa_collab27(action, room_code, enabled, position_seconds, is_playing, sequence);
end;
$$;
revoke all on function public.loopa_collab27(text,text,boolean,double precision,boolean,bigint) from public, anon, service_role;
grant execute on function public.loopa_collab27(text,text,boolean,double precision,boolean,bigint) to authenticated;

create or replace function public.loopa_control_v2(
  room_code text, expected_video text, expected_generation bigint,
  position_seconds double precision, is_playing boolean
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  r public.loopa_rooms16;
begin
  if auth.uid() is null then raise exception 'login_required'; end if;

  select * into r from public.loopa_rooms16 where code = upper(trim(room_code)) for update;
  if r.code is null or r.video is distinct from expected_video
     or r.control_generation is distinct from expected_generation then
    raise exception 'Комната или разрешение изменились';
  end if;

  return loopa_private.loopa_collab27(
    action => 'control', room_code => r.code,
    position_seconds => position_seconds, is_playing => is_playing
  );
end;
$$;

notify pgrst, 'reload schema';
commit;
