# LOOPA — Telegram Mini App enhancements

## Implemented in this PR

1. **Share a room**: from an active room tap the existing Share link button. In a Telegram Mini App with `shareMessage`, the authenticated host asks the bot for a prepared inline message, then opens Telegram's recipient picker. The shared card includes a button to open the exact room using `startapp=room_<code>`. On older clients, falls back to `t.me/share/url`; browsers keep Web Share / copy.
2. **Bot invite notifications**: when the host explicitly invites an existing LOOPA friend, the server checks recipient friendship, block list, room, notification policy, Telegram account link and bot subscription before delivering a private bot message. The recipient must have started @LOOPAvideo_bot with `/start`. They can opt out using `/stop` and opt back in using `/start`. The server claims a given invitation/send timestamp once, avoiding repeats on player reload.
3. **Branded opening transition**: in Telegram's WebView, a short dark splash with LOOPA wordmark and tagline fades away. It has a 2.4-second failsafe. This is **not** the Telegram-native loading splash.

## Native Telegram launch splash — BotFather action required

Telegram controls its own splash *before* the WebView is loaded. Site HTML and bot webhook APIs cannot change that native screen. In @BotFather, select **@LOOPAvideo_bot → Bot Settings → Configure Mini App / Main Mini App → Launch screen / Splash screen** (labels may differ by Telegram version). Use the existing LOOPA logo, background `#090A0C`, and light foreground `#F4F0EF` if the configuration offers those controls. Do not change the Mini App URL (`https://loopacinema.ru/`) or short name (`loopa`). If no native splash setting is available, the in-app transition is still active.

## Security

- No bot token or service-role key in HTML or GitHub. `loopa-bot` accesses secrets via Supabase Edge Function environment.
- Both `notify_invite` and `share_room` require a valid Supabase user JWT. The room host and invite sender are checked server-side.
- Webhook secret verification remains in place for Telegram updates.
- Database function `loopa_claim_telegram_invite` is callable only by `service_role`.
- Opt-in subscriptions are server-only. `/stop` disables bot alerts.
- The SQL migration is idempotent and documents the schema already provisioned on Supabase.

## Test plan

- Telegram iOS/Android: create room, tap Share, select recipient, check formatted invitation and one-tap join.
- Older Telegram/browser: verify share fallback.
- Two linked friends: recipient sends `/start`, host invites → one bot message; change video → no repeated message.
- Recipient sends `/stop`, host sends a fresh invitation after rate limit → no bot notification; `/start` re-enables.
- No Telegram link or not-friends: bot message must not be sent.
- Reload Mini App and verify short opening screen never blocks navigation.
