-- Analytics records events without retaining room codes or user identifiers.
create table loopa_private.bot_stats_room_events (
  occurred_at timestamptz not null default clock_timestamp(),
  kind text not null check (kind in ('tracking_started', 'created', 'youtube', 'vk', 'rutube'))
);
alter table loopa_private.bot_stats_room_events enable row level security;
revoke all on table loopa_private.bot_stats_room_events from public, anon, authenticated, service_role;

create index bot_stats_room_events_occurred_at_idx
  on loopa_private.bot_stats_room_events (occurred_at) where kind <> 'tracking_started';

insert into loopa_private.bot_stats_room_events(kind) values ('tracking_started');

create function loopa_private.record_bot_stats_room_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  provider text;
begin
  if tg_op = 'INSERT' then
    insert into loopa_private.bot_stats_room_events(kind) values ('created');
  elsif new.video is not distinct from old.video then
    return null;
  end if;

  if new.video <> '' and public.loopa_allowed_video_url(new.video) then
    provider := case pg_catalog.split_part(new.video, '/', 3)
      when 'www.youtube.com' then 'youtube'
      when 'vkvideo.ru' then 'vk'
      when 'rutube.ru' then 'rutube'
    end;
    if provider is not null then
      insert into loopa_private.bot_stats_room_events(kind) values (provider);
    end if;
  end if;
  return null;
end;
$$;

revoke all on function loopa_private.record_bot_stats_room_event() from public, anon, authenticated, service_role;

create trigger loopa_bot_stats_room_event
after insert or update of video on public.loopa_rooms16
for each row execute function loopa_private.record_bot_stats_room_event();

-- The private implementation reads Auth and restricted room tables and returns only aggregates.
create function loopa_private.owner_bot_stats()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with bounds as (
    select statement_timestamp() as as_of,
      date_trunc('day', statement_timestamp(), 'Europe/Moscow') as today
  ), registrations as (
    select count(*) as total,
      count(*) filter (where not a.is_test and a.registered_at >= b.today) as today,
      count(*) filter (where not a.is_test and a.registered_at >= b.as_of - interval '168 hours') as days_7,
      count(*) filter (where not a.is_test and a.registered_at >= b.as_of - interval '720 hours') as days_30
    from bounds b cross join lateral (
      select coalesce(l.linked_at, u.confirmed_at) as registered_at,
        coalesce(u.raw_app_meta_data->'loopa_test_account' = 'true'::jsonb, false) as is_test
      from auth.users u
      left join loopa_private.telegram_finished_registrations f on f.user_id = u.id
      left join public.telegram_miniapp_links l on l.user_id = f.user_id
      where u.confirmed_at <= b.as_of and u.deleted_at is null and not u.is_anonymous
        and (u.raw_app_meta_data->>'loopa_telegram_registration' is null or f.user_id is not null)
    ) a
  ), activity as (
    select count(*) filter (where p.last_active_at > b.as_of - interval '90 seconds') as online,
      count(*) filter (where p.last_active_at > b.as_of - interval '24 hours') as day,
      count(*) as month
    from bounds b join public.user_presence p
      on p.last_active_at > b.as_of - interval '720 hours' and p.last_active_at <= b.as_of
    join auth.users u on u.id = p.user_id
    where u.confirmed_at <= b.as_of and u.deleted_at is null and not u.is_anonymous
  ), fresh_members as materialized (
    select m.code, m.member
    from bounds b join public.loopa_members16 m
      on m.seen > b.as_of - interval '20 seconds' and m.seen <= b.as_of
    join auth.users u on u.id = m.member
    where u.confirmed_at <= b.as_of and u.deleted_at is null and not u.is_anonymous
  ), active_rooms as (
    select code, count(*) as members from fresh_members group by code
  ), shared_playback as (
    select r.code
    from active_rooms a
    join public.loopa_rooms16 r on r.code = a.code
    join public.loopa_playback57 p on p.code = r.code and p.video = r.video and p.owner = r.host
    cross join bounds b
    where a.members >= 2 and p.playing and r.video <> ''
      and p.stamp > b.as_of - interval '20 seconds' and p.stamp <= b.as_of
  ), room_events as (
    select count(*) filter (where e.kind = 'created' and e.occurred_at > b.as_of - interval '24 hours') as rooms_day,
      count(*) filter (where e.kind = 'youtube') as youtube,
      count(*) filter (where e.kind = 'vk') as vk,
      count(*) filter (where e.kind = 'rutube') as rutube
    from bounds b join loopa_private.bot_stats_room_events e
      on e.occurred_at > b.as_of - interval '720 hours' and e.occurred_at <= b.as_of
    where e.kind <> 'tracking_started'
  )
  select jsonb_build_object(
    'as_of', b.as_of,
    'room_tracking_started_at', (select min(occurred_at) from loopa_private.bot_stats_room_events
      where kind = 'tracking_started'),
    'registered', r.total, 'new_today', r.today, 'new_7d', r.days_7, 'new_30d', r.days_30,
    'online', a.online, 'active_24h', a.day, 'active_30d', a.month,
    'active_rooms', (select count(*) from active_rooms),
    'watching_together', (select count(distinct m.member) from fresh_members m join shared_playback s using (code)),
    'rooms_created_24h', e.rooms_day,
    'providers', jsonb_build_object('youtube', e.youtube, 'vk', e.vk, 'rutube', e.rutube)
  )
  from bounds b cross join registrations r cross join activity a cross join room_events e;
$$;

revoke all on function loopa_private.owner_bot_stats() from public, anon, authenticated, service_role;
grant usage on schema loopa_private to service_role;
grant execute on function loopa_private.owner_bot_stats() to service_role;

create function public.loopa_owner_bot_stats()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select loopa_private.owner_bot_stats();
$$;

revoke all on function public.loopa_owner_bot_stats() from public, anon, authenticated, service_role;
grant execute on function public.loopa_owner_bot_stats() to service_role;
