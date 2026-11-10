-- LOOPA: friends-only activity visibility.
-- Deploy this migration before the updated index.html.
-- The existing 'visible' privacy switch remains authoritative:
-- when false, neither last-seen nor room activity is exposed.
begin;

alter table public.user_presence
  alter column share_room_activity set default true;

-- The old client did not offer a room-sharing switch and wrote false by default.
-- Bring existing accounts onto the new friends-only default without touching
-- their separate 'visible' preference (including users who hid all activity).
update public.user_presence
set share_room_activity = true
where share_room_activity is false;

drop policy if exists "LOOPA presence read visible or own"
  on public.user_presence;
drop policy if exists "LOOPA presence read friends or own"
  on public.user_presence;

create policy "LOOPA presence read friends or own"
on public.user_presence
for select
to authenticated
using (
  user_id = (select auth.uid())
  or (
    visible is true
    and not public.loopa_pair_is_blocked((select auth.uid()), user_id)
    and exists (
      select 1
      from public.friend_requests f
      where f.status = 'accepted'
        and (
          (f.sender_id = (select auth.uid()) and f.receiver_id = user_presence.user_id)
          or (f.receiver_id = (select auth.uid()) and f.sender_id = user_presence.user_id)
        )
    )
  )
);

commit;
