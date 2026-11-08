# LOOPA Telegram Mini App — sharing, notifications, splash

## Native loading screen
Telegram's pre-page splash is configured in @BotFather, not by web page JavaScript.
Open @BotFather → /mybots → @LOOPAvideo_bot → Bot Settings → Configure Mini App → Configure Splash Screen.
Use assets/loopa-splash.svg as an icon source. Convert to BotFather's required image format if necessary.
Background for dark and light themes: #090A0C; foreground: #F4F0EF. Preview and save in BotFather.
The new HTML transition splash runs only inside the Telegram Mini App and is distinct from the native pre-page screen.

## Sharing
The room sharing button uses Telegram.WebApp.shareMessage and a server-created prepared inline message when Telegram supports it and the room owner has linked Telegram.
Fallback: t.me/share/url, native OS share or copying the normal website room link.
The prepared message includes an Open room button pointing to t.me/LOOPAvideo_bot/loopa?startapp=room_<code>.

## Bot notifications
The recipient links the same LOOPA profile with Telegram and sends /start to @LOOPAvideo_bot to opt in.
/stop opts out; /start opts in again. The bot only sends for manually submitted pending room invitations.
The server validates the sender via Supabase Auth, friendship and room permissions. Each send timestamp is claimed once server-side.
Without opt-in, the in-app invitation works normally. Bot delivery can fail if the chat is blocked or inaccessible.

## After merging
SQL migration must be applied and loopa-bot Edge Function deployed before the frontend change goes live.
Test two linked accounts, /stop and /start, shareMessage fallback, and iPhone/Android splash.
No bot tokens or service-role keys are shipped to the browser.