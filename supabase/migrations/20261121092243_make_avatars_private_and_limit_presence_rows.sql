-- Apply after the avatar gateway and updated client are live.
begin;

update storage.buckets set public = false where id = 'avatars';

drop policy "LOOPA presence read friends or own" on public.user_presence;
create policy "LOOPA presence read own" on public.user_presence
  for select to authenticated using (user_id = (select auth.uid()));

commit;
