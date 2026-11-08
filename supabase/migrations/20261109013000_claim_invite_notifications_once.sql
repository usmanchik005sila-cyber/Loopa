-- A notification is delivered once for each invitation send timestamp.
-- Starting another video does not change "sent" and cannot trigger the same popup.
alter table public.loopa_invites25
  add column if not exists notified_sent timestamptz;

create or replace function public.loopa_claim_invite_notices()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient_id uuid := auth.uid();
  claimed jsonb;
begin
  if recipient_id is null then
    raise exception 'Authentication required';
  end if;

  with updated as (
    update public.loopa_invites25 as v
    set notified_sent = v.sent
    where v.recipient = recipient_id
      and v.status = 'pending'
      and v.sent > now() - interval '24 hours'
      and v.notified_sent is distinct from v.sent
      and exists (
        select 1 from public.loopa_rooms16 rm
        where rm.code = v.code and rm.host = v.sender
      )
      and not public.loopa_pair_is_blocked(recipient_id, v.sender)
      and exists (
        select 1 from public.friend_requests fr
        where fr.status = 'accepted'
          and (
            (fr.sender_id = recipient_id and fr.receiver_id = v.sender)
            or (fr.sender_id = v.sender and fr.receiver_id = recipient_id)
          )
      )
      and exists (
        select 1 from public.profiles me
        where me.id = recipient_id
          and coalesce(me.room_invite_policy, 'friends') <> 'nobody'
      )
    returning v.id, v.sent
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'sent', sent)), '[]'::jsonb)
    into claimed
  from updated;
  return claimed;
end;
$$;

revoke all on function public.loopa_claim_invite_notices() from public, anon;
grant execute on function public.loopa_claim_invite_notices() to authenticated;
