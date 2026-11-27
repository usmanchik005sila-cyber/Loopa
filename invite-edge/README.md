# Telegram invitations

The Worker returns crawler-readable HTML for signed invitation links. The bot and the Worker share `LOOPA_INVITE_SIGNING_SECRET`, a separate 32-byte random secret represented as 64 hex characters. Tokens contain shareable video metadata and the existing Telegram launch parameter. The landing cannot join a room or read account data.

## Rehearsal

Deploy the default Worker to a separate Workers.dev hostname. Set `LOOPA_INVITE_PUBLIC_ORIGIN` to that HTTPS origin, without a trailing slash, in both the Worker and the bot under test. Install the rehearsal signing secret in both services. Use a separate test bot or a designated test chat. In tests, assert that the page responds anonymously with `text/html` and that `og:image` can be fetched by Telegram.

Check a YouTube, VK Видео and RUTUBE invitation in Telegram. Inspect the inline result and the sent message. Test the button and the landing link for a room. The bot requests a large preview above the message text and the blue `primary` button style. Telegram chooses the actual crop, may reuse cached metadata, and can ignore the size preference for unsupported URLs.

## Production after approval

1. Route only `loopacinema.ru/invite/*` to the production Worker. Cloudflare Workers Routes require the DNS record to be proxied. If it is DNS-only, validate the proxy setup and the rest of the site before enabling it. The remaining paths continue to use GitHub Pages.
2. Add the production signing secret to the Worker first. Confirm the invite route and the existing home page before adding the same secret to the production bot. The production origin defaults to `https://loopacinema.ru`. A bot without a valid signing secret uses the existing invitation mechanism.
3. Run the three Telegram checks again. Keep the Worker and its signing secret available for previously sent links if rolling back the bot. Changing the signing secret invalidates URLs signed with the old value.
