# LOOPA — Telegram Mini App enhancements

## Implemented in this PR

1. **Share a room**: from an active room tap the existing Share link button. In a Telegram Mini App with `shareMessage`, the authenticated host asks the bot for a prepared inline message, then opens Telegram's recipient picker. The shared card includes a button to open the exact room using `startapp=room_<code>`. On older clients, falls back to `t.me/share/url`; browsers keep Web Share / copy.
2. **Bot invite notifications**: when the host explicitly invites an existing LOOPA friend, the server checks recipient friendship, block list, room, notification policy, Telegram account link and bot subscription before delivering a private bot message. The recipient must have started @LOOPAvideo_bot with `/start`. They can opt out using `/stop` and opt back in using `/start`. The server claims a given invitation/send timestamp once, avoiding repeats on player reload.
3. **Branded opening transition**: in Telegram's WebView, a short dark splash with LOOPA wordmark and tagline fades away. It has a 2.4-second failsafe. This is **not** the Telegram-native loading splash.

## Native Telegram launch splash — action required in BotFather

Telegram draws its own splash **before** the LOOPA web page loads. This cannot
be changed through the HTML, the website's CSS, or the bot webhook.

Official Telegram path (verified November 2026):
1. Open **@BotFather** and send `/mybots`.
2. Select **@LOOPAvideo_bot**.
3. Open **Bot Settings → Configure Mini App → Configure Splash Screen**.
4. Upload **`assets/loopa-telegram-splash.svg`** as a **file/document** (512×512 SVG,
   under 1 KB; its artwork matches the in-app opening monogram).
5. When offered colors, use **`#090A0C`** for the background in **both light and dark**
   themes and **`#090A0C`** for the header where separately configurable.
6. Tap **Open Splash Screen Preview** in BotFather to inspect the native result.

Official source: https://core.telegram.org/bots/features#customizable-loading-screens

Notes:
- Telegram may show slightly different labels on different clients.
- Do **not** edit the Main Mini App URL (`https://loopacinema.ru/`) or
  short name (`loopa`). Those control room invitation deep links.
- The in-app transition in `index.html` is separate: it uses matching
  graphite colors and monogram, exits automatically, honors reduced-motion,
  and has a 1.65-second fail-safe even if external players do not load.
- Browser visits outside Telegram do not show the in-app splash.
- Actual native BotFather settings can only be completed by a bot administrator.

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
