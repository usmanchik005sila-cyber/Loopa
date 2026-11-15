# Playback command context rollback

Restore the previous website commit fdc4a23ed08cd034cc4c18f94f614079c3287581 first.
The additive server column, trigger, and v2 RPC can remain: they do not change the
signature or permissions of loopa_collab27, and preserve existing rooms and data.
Do not remove the new RPC while new clients may still be open.

After deployment, reload open clients on both accounts. Old clients still use the
legacy control RPC and do not send the video/generation context.

The client now acknowledges only fresh player observations after a command.
An ignored command remains pending and retries; it is never falsely acknowledged.
Actual provider autoplay failures and offline/device transitions need device tests.
