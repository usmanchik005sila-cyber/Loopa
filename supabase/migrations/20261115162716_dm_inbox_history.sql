begin;
-- Invoker preserves the existing participant-only RLS. No caller-supplied user ID.
create or replace function public.loopa_dm_inbox(before_id bigint default null,page_size integer default 51)
returns table(id bigint,sender_id uuid,recipient_id uuid,body text,created_at timestamptz)
language sql stable security invoker set search_path=''
as $$
 select latest.id,latest.sender_id,latest.recipient_id,latest.body,latest.created_at
 from (
  select distinct on (case when m.sender_id=(select auth.uid()) then m.recipient_id else m.sender_id end)
   m.id,m.sender_id,m.recipient_id,m.body,m.created_at
  from public.loopa_dm_messages_v87 m
  where m.sender_id=(select auth.uid()) or m.recipient_id=(select auth.uid())
  order by case when m.sender_id=(select auth.uid()) then m.recipient_id else m.sender_id end,m.id desc
 ) latest
 where before_id is null or latest.id<before_id
 order by latest.id desc limit greatest(1,least(coalesce(page_size,51),101));
$$;
revoke all on function public.loopa_dm_inbox(bigint,integer) from public,anon;
grant execute on function public.loopa_dm_inbox(bigint,integer) to authenticated;
notify pgrst,'reload schema';
commit;
