-- Allow only the backend service role to manage Telegram bot opt-in subscriptions.
-- /start and /stop are handled by a webhook-secret-verified Edge Function.
-- The claims function also needs to read the recipient's opt-in status.
grant select, insert, update on table public.loopa_bot_subscriptions to service_role;
revoke all on table public.loopa_bot_subscriptions from anon, authenticated;
