-- Apply only AFTER the new client is deployed. Old open tabs must reload.
begin;
create schema if not exists loopa_private;
revoke all on schema loopa_private from public,anon;
grant usage on schema loopa_private to authenticated;
create or replace function loopa_private.can_request_friend(target uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
 select (select auth.uid()) is not null and target<>(select auth.uid())
 and exists(select 1 from public.profiles p where p.id=target and p.allow_friend_requests)
 and not public.loopa_pair_is_blocked((select auth.uid()),target);
$$;
revoke all on function loopa_private.can_request_friend(uuid) from public,anon;
grant execute on function loopa_private.can_request_friend(uuid) to authenticated;

alter policy "LOOPA friends send own" on public.friend_requests
with check (
 sender_id=(select auth.uid()) and receiver_id<>(select auth.uid())
 and status='pending' and responded_at is null
 and loopa_private.can_request_friend(receiver_id)
);
-- Existing owner-only SELECT/INSERT/UPDATE policies remain in force.
drop policy "LOOPA profiles read authenticated" on public.profiles;

-- Remove DDL-like privileges only from the four inspected application tables.
revoke truncate,references,trigger on table
 public.profiles,public.user_presence,public.friend_requests,public.loopa_dm_messages_v87
 from public,anon,authenticated;
notify pgrst, 'reload schema';
commit;
