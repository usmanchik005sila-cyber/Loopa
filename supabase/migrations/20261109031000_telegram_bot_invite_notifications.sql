-- Idempotent schema matching the already provisioned production bot invite service.
-- No Telegram chat IDs are exposed to the browser.
create table if not exists public.loopa_bot_subscriptions (
  telegram_id text primary key,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
revoke all on public.loopa_bot_subscriptions from public, anon, authenticated;
alter table public.loopa_bot_subscriptions enable row level security;
alter table public.loopa_invites25 add column if not exists bot_notified_sent timestamptz;

create or replace function public.loopa_claim_telegram_invite(p_invitation uuid,p_sender uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare payload jsonb;
begin
  if p_invitation is null or p_sender is null then return null; end if;
  with claimed as (
    update public.loopa_invites25 v
    set bot_notified_sent=v.sent
    where v.id=p_invitation and v.sender=p_sender
      and v.status='pending' and v.sent>now()-interval '24 hours'
      and v.bot_notified_sent is distinct from v.sent
      and exists(select 1 from public.loopa_rooms16 rm where rm.code=v.code and rm.host=p_sender)
      and exists(select 1 from public.profiles me where me.id=v.recipient
        and coalesce(me.room_invite_policy,'friends')<>'nobody')
      and not public.loopa_pair_is_blocked(v.recipient,p_sender)
      and exists(select 1 from public.friend_requests f
        where f.status='accepted' and
          ((f.sender_id=p_sender and f.receiver_id=v.recipient)
          or (f.sender_id=v.recipient and f.receiver_id=p_sender)))
      and exists(select 1 from public.telegram_miniapp_links l
        join public.loopa_bot_subscriptions b on b.telegram_id=l.telegram_id
        where l.user_id=v.recipient and b.enabled)
    returning v.recipient,v.code
  )
  select jsonb_build_object(
    'telegram_id',l.telegram_id,'code',c.code,
    'sender_name',left(coalesce(nullif(p.display_name,''),'Друг'),80)
  ) into payload
  from claimed c
  join public.telegram_miniapp_links l on l.user_id=c.recipient
  join public.loopa_bot_subscriptions b on b.telegram_id=l.telegram_id and b.enabled
  left join public.profiles p on p.id=p_sender;
  return payload;
end;
$$;
revoke all on function public.loopa_claim_telegram_invite(uuid,uuid) from public, anon, authenticated;
grant execute on function public.loopa_claim_telegram_invite(uuid,uuid) to service_role;
