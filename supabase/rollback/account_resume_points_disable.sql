-- Emergency disable without destroying already saved progress.
-- The client falls back to local progress and shows a sync error.
begin;
revoke all on table public.loopa_resume_points from public,anon,authenticated;
notify pgrst, 'reload schema';
commit;
