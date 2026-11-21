-- Run on an isolated database with the direct-message policies applied.
begin;

insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000301'),
  ('00000000-0000-4000-8000-000000000302'),
  ('00000000-0000-4000-8000-000000000303');

insert into public.profiles(id, display_name, dm_policy) values
  ('00000000-0000-4000-8000-000000000301', 'Sender', 'everyone'),
  ('00000000-0000-4000-8000-000000000302', 'Recipient', 'everyone'),
  ('00000000-0000-4000-8000-000000000303', 'Other', 'everyone')
on conflict (id) do update set dm_policy = excluded.dm_policy;

set local role authenticated;

do $test$
declare
  sender constant uuid := '00000000-0000-4000-8000-000000000301';
  recipient constant uuid := '00000000-0000-4000-8000-000000000302';
  outsider constant uuid := '00000000-0000-4000-8000-000000000303';
  message_id bigint;
  sent_at timestamptz;
begin
  perform set_config('request.jwt.claim.sub', sender::text, true);
  insert into public.loopa_dm_messages_v87(sender_id, recipient_id, body)
  values (sender, recipient, 'DM fixture')
  returning id, created_at into message_id, sent_at;
  if message_id is null or sent_at is null then
    raise exception 'Missing generated message metadata';
  end if;
  if has_column_privilege('authenticated', 'public.loopa_dm_messages_v87', 'created_at', 'INSERT')
     or has_column_privilege('authenticated', 'public.loopa_dm_messages_v87', 'id', 'INSERT') then
    raise exception 'Message metadata must be server assigned';
  end if;

  perform set_config('request.jwt.claim.sub', recipient::text, true);
  if not exists (select 1 from public.loopa_dm_inbox() where id = message_id) then
    raise exception 'The recipient cannot read the message';
  end if;

  perform set_config('request.jwt.claim.sub', outsider::text, true);
  if exists (select 1 from public.loopa_dm_messages_v87 where id = message_id)
     or exists (select 1 from public.loopa_dm_inbox() where id = message_id) then
    raise exception 'A nonparticipant can see the message';
  end if;
end;
$test$;

reset role;
insert into public.blocked_users(blocker_id, blocked_id)
values ('00000000-0000-4000-8000-000000000302', '00000000-0000-4000-8000-000000000301');

set local role authenticated;

do $test$
declare
  sender constant uuid := '00000000-0000-4000-8000-000000000301';
  recipient constant uuid := '00000000-0000-4000-8000-000000000302';
begin
  perform set_config('request.jwt.claim.sub', sender::text, true);
  if public.loopa_dm_may_send_v87(recipient) is distinct from false then
    raise exception 'A block must prevent contacting the user who set it';
  end if;
  perform set_config('request.jwt.claim.sub', recipient::text, true);
  if public.loopa_dm_may_send_v87(sender) is distinct from false then
    raise exception 'A block must prevent contacting the blocked user';
  end if;
end;
$test$;

rollback;
