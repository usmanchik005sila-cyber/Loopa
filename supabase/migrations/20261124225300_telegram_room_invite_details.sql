begin;

create function public.loopa_room_invite_details(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object('video', room.video, 'title', metadata.title, 'image', metadata.image)
  from public.loopa_rooms16 as room
  left join public.loopa_titles26 as metadata
    on metadata.code = room.code and metadata.video = room.video
  where room.code = p_code and room.host = (select auth.uid());
$function$;

revoke all on function public.loopa_room_invite_details(text) from public, anon, authenticated, service_role;
grant execute on function public.loopa_room_invite_details(text) to authenticated;

notify pgrst, 'reload schema';

commit;
