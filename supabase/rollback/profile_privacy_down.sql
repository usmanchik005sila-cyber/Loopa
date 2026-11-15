-- Restore access before rolling the website back. Keep the narrow directory RPC.
begin;
create policy "LOOPA profiles read authenticated" on public.profiles
 for select to authenticated using (true);
alter policy "LOOPA friends send own" on public.friend_requests
with check (
 sender_id=(select auth.uid()) and receiver_id<>(select auth.uid())
 and status='pending' and responded_at is null
 and exists(select 1 from public.profiles p where p.id=friend_requests.receiver_id and p.allow_friend_requests)
 and not public.loopa_pair_is_blocked((select auth.uid()),receiver_id)
);
-- Restore only grants recorded before this release.
grant truncate,references,trigger on public.profiles,public.user_presence to anon,authenticated;
grant truncate,references,trigger on public.friend_requests,public.loopa_dm_messages_v87 to authenticated;
notify pgrst, 'reload schema';
commit;
