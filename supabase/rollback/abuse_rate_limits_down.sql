-- First redeploy the previous video-search source, which does not require quota RPC.
drop trigger if exists loopa_message_budget on public.loopa_dm_messages_v87;
drop trigger if exists loopa_chat_budget on public.loopa_chat18;
drop trigger if exists loopa_room_budget on public.loopa_rooms16;
drop function if exists public.loopa_search_budget(text);
drop function if exists loopa_private.limit_insert_budget();
drop function if exists loopa_private.consume_budget(text);
-- Keep the bounded quota counters for investigation; do not delete user data.
