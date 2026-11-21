begin;

-- The database assigns the message ID and timestamp.
revoke insert on public.loopa_dm_messages_v87 from authenticated;
grant insert (sender_id, recipient_id, body) on public.loopa_dm_messages_v87 to authenticated;

notify pgrst, 'reload schema';

commit;
