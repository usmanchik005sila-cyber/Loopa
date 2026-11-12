# LOOPA: setup for reports and automatic account deletion

This operator guide is committed to a public repository and is therefore publicly readable; it is **not** the user-facing privacy policy. The owner confirmed `@loopasupport` as the support contact. Retention periods are not approved, so no privacy-policy text is published.

## Deployment order

1. Confirm the profile, direct-message, room, invite, playback, and safety-request tables are installed.
2. Run `migrations/20261110180000_user_safety_requests.sql` in Supabase SQL Editor if it has not already been applied.
3. Run `migrations/20261110190000_dm_policy_default_everyone.sql` if it has not already been applied.
4. Run `migrations/20261112100000_account_deletion_approval.sql`. It checks required tables before installing the cleanup RPC.
5. To receive Telegram notifications, set the optional Edge Function secret `LOOPA_OWNER_TELEGRAM_ID` as described in `BOT_WELCOME_SETUP.md`, then redeploy `loopa-bot`.
6. Publish the matching site build.

New profiles default to `everyone`; the privacy settings let each user choose between `everyone` and `friends`. The migrations change only the column default and the new-profile trigger. They do not update existing profile rows or overwrite users' saved preferences.

## Private report review queue

Regular users cannot select, update, or delete report rows. The site submits reports through a narrowly scoped RPC that takes the reporter from `auth.uid()`. No user-facing admin screen is added. Only the project owner should run the following queries in Supabase SQL Editor.

### Review open reports

The report stores the message ID, not a second copy of its text. The owner can read the referenced message in place while reviewing it:

```sql
select
  r.id,
  r.created_at,
  r.reporter_id,
  r.reported_user_id,
  r.message_ref,
  r.reason,
  r.details,
  m.body as reported_message
from public.loopa_user_reports_v1 r
left join public.loopa_dm_messages_v87 m
  on m.id::text = r.message_ref
where r.status = 'open'
order by r.created_at asc;
```

After review, set `status` to `reviewed`, `actioned`, or `dismissed` and set `reviewed_at`:

```sql
update public.loopa_user_reports_v1
set status = 'reviewed', reviewed_at = now()
where id = 'REPORT_UUID';
```

### Check a deletion that needs recovery

Normally the account is removed automatically after the user checks the confirmation box and presses **Удалить сейчас**. The bot receives an informational message; it does not approve the deletion. The request row is removed after the Auth account and associated data are deleted.

If a technical failure happens after the Auth account is removed, the request remains in `processing` so cleanup can be retried. The owner bot message includes the request ID and `/retrydelete <UUID>` command. To inspect stuck requests:

```sql
select id, user_id, requested_at, status, handled_at
from public.loopa_account_deletion_requests_v1
where status = 'processing'
order by requested_at asc;
```

The retry command is for recovering a failed cleanup only; it is not an approval step. If a request remains stuck after retry, keep the request ID and inspect the Edge Function logs before running manual SQL.

## Current data map (based on the checked-in client and SQL)

| Category | Data currently used |
| --- | --- |
| Sign-in | Supabase Auth account ID and the email, phone, or provider identity supplied by the selected sign-in method. Telegram linking records a Telegram ID. |
| Profile | Display name, avatar path/image, notification preference, DM policy, friend-request and room-invite preferences. Avatar images use the `avatars` storage bucket and the app currently serves their public URL. |
| Social graph | Friend requests and accepted relationships, plus directional blocks. |
| Direct messages | Sender, recipient, message text, row ID, and timestamp in `loopa_dm_messages_v87`. The UI loads the latest 100 for a conversation; this is a display limit, not a deletion rule. |
| Watch rooms | Room code, host, access mode, members, current media URL and playback position; room-chat author, text, and timestamp. `loopa_room16` returns the latest 60 chat rows; this is not a retention limit. |
| Invitations and Telegram | Room-invite sender, recipient, room code, status and sent time; Telegram account linkage and bot-notification preference. |
| Presence and activity | Visibility preferences and activity timestamps, plus accumulated usage seconds and room/video activity used by friend features. |
| Resume progress | Account ID, video key, position and timestamp in `loopa_resume_points`; the client offers points for up to 90 days. That UI window does not prove that old database rows are physically erased. |
| Browser-local data | Theme, wallpaper preference, local resume fallback, invite-notice dismissal state, notification preference and local recommendation-frequency scores. These values remain in site storage until the browser/site data is cleared. |
| Safety requests | The private report queue stores reporter/profile IDs, message reference, reason, optional comment, status, and time; deletion requests exist only while the automatic deletion is being processed. Message text is not copied into reports. |

The report queue intentionally has no foreign key to `auth.users`; report retention remains a separate owner decision. Successful account deletion removes its request row and all account-linked records. The Telegram message is an owner-only completion notice containing only the request ID, not the user's name or email.

## Retention facts still requiring owner confirmation

Active accounts keep their cloud data until the user requests deletion; that request now triggers immediate cleanup. There is no reliable automatic deletion schedule for reports or backups. A 24-hour invite-acceptance rule, 20-second online indicator, latest-60/latest-100 display limits, and 90-day resume prompt are **not** data-deletion periods.

Before writing or publishing a policy, the owner must confirm:

- how long profile, account, social, room, message, and usage data remain;
- how long reports remain after resolution; deletion-request rows are removed on successful deletion;
- how backups are handled and when they expire;
- the support contact and how users can reach it;
- whether deletion means immediate removal, staged removal, or removal with a stated backup exception.

Until retention facts are confirmed, do not present a retention promise in the app. The confirmed support contact may be shown separately.
