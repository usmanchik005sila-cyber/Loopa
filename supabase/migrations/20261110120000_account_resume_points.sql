-- Personal resume points belong to one Supabase Auth user, including anonymous
-- users until they link a permanent sign-in identity.
begin;

create table if not exists public.loopa_resume_points (
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  media text not null
    check (length(media) between 1 and 2048),
  position_seconds integer not null
    check (position_seconds between 20 and 360000),
  duration_seconds integer not null default 0
    check (duration_seconds between 0 and 360000),
  updated_at timestamptz not null default now(),
  primary key (user_id, media)
);

alter table public.loopa_resume_points enable row level security;

drop policy if exists "Users manage their own LOOPA resume points"
  on public.loopa_resume_points;
create policy "Users manage their own LOOPA resume points"
  on public.loopa_resume_points
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on table public.loopa_resume_points from public, anon;
grant select, insert, update, delete on table public.loopa_resume_points to authenticated;

create or replace function public.loopa_touch_resume_point_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function public.loopa_touch_resume_point_updated_at()
  from public, anon, authenticated;

drop trigger if exists loopa_resume_points_touch_updated_at
  on public.loopa_resume_points;
create trigger loopa_resume_points_touch_updated_at
  before update on public.loopa_resume_points
  for each row execute function public.loopa_touch_resume_point_updated_at();

comment on table public.loopa_resume_points is
  'Private per-user playback position; contains no chat messages or video titles.';

commit;
