begin;
alter table public.loopa_rooms16 add column control_generation bigint not null default 0;
create function public.loopa_control_generation() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if TG_ARGV[0]='grant' or new.video is distinct from old.video then
  new.control_generation=old.control_generation+1;
 end if;
 return new;
end $$;
create trigger loopa_control_grant_generation before update of shared_control on public.loopa_rooms16
 for each row execute function public.loopa_control_generation('grant');
create trigger loopa_control_video_generation before update of video on public.loopa_rooms16
 for each row execute function public.loopa_control_generation('video');
revoke all on function public.loopa_control_generation() from public,anon,authenticated;
-- New clients bind commands to a video AND explicit grant generation.
-- Keep the previous RPC for already-open clients and host mode/renew/ack.
create function public.loopa_control_v2(room_code text,expected_video text,expected_generation bigint,position_seconds double precision,is_playing boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.loopa_rooms16;
begin
 if auth.uid() is null then raise exception 'login_required'; end if;
 select * into r from public.loopa_rooms16 where code=upper(trim(room_code)) for update;
 if r.code is null or r.video is distinct from expected_video or r.control_generation is distinct from expected_generation then
  raise exception 'Комната или разрешение изменились';
 end if;
 return public.loopa_collab27(action=>'control',room_code=>r.code,position_seconds=>position_seconds,is_playing=>is_playing);
end $$;
revoke all on function public.loopa_control_v2(text,text,bigint,double precision,boolean) from public,anon;
grant execute on function public.loopa_control_v2(text,text,bigint,double precision,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
