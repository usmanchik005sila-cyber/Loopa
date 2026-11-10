# LOOPA: setup for reports and account deletion requests

This operator guide is committed to a public repository and is therefore publicly readable; it is **not** the user-facing privacy policy. It contains no support contact and does not set retention periods. Do not publish a privacy-policy statement until the owner confirms the actual periods and support contact.

## Deployment order

1. Confirm the `profiles` table and direct-message SQL `loopa_dm_messages_v87` are installed.
2. Run `migrations/20261110180000_user_safety_requests.sql` in Supabase SQL Editor.
3. Publish the matching site build.
4. Review the report and deletion-request queues from the project owner's Supabase SQL Editor.

The migration changes only the default for new `profiles.dm_policy` inserts to `friends` and fills an explicit `NULL` on a new profile insert with that same value. It does not update existing profile rows. Existing choices remain as stored; legacy rows with no choice retain the client’s prior “all users” behavior.

## Private owner review queue

Regular users cannot select, update, or delete rows in either queue. The site can submit through two narrowly scoped RPCs; the functions take the reporter/request owner from `auth.uid()`. No user-facing admin or review screen is added. Only the project owner should run the following queries in Supabase SQL Editor.

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

### Review account deletion requests

```sql
select id, user_id, requested_at, status, handled_at
from public.loopa_account_deletion_requests_v1
where status in ('pending', 'processing')
order by requested_at asc;
```

Submitting this request does **not** delete the account or data. No account is deleted automatically by this migration. The owner must review each request and decide how to process it after confirming the data-retention policy.

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
| Safety requests | The new private queue stores reporter/profile IDs, message reference, reason, optional comment, status, and time; deletion requests store profile ID, status, and request/handling times. Message text is not copied into the report. |

The two queues intentionally have no foreign key to `auth.users`, so their review records do not disappear automatically if an account is removed. They remain until the owner processes and removes them according to a retention rule that still needs confirmation.

## Retention facts still requiring owner confirmation

The checked-in code shows some display/freshness windows, but no reliable automatic deletion schedule for Auth accounts, profiles, avatars, friendships, direct messages, room chats, invitations, usage history, Telegram linkage, reports, deletion requests, or backups. A 24-hour invite-acceptance rule, 20-second online indicator, latest-60/latest-100 display limits, and 90-day resume prompt are **not** data-deletion periods.

Before writing or publishing a policy, the owner must confirm:

- how long profile, account, social, room, message, and usage data remain;
- how long reports and deletion requests remain after resolution;
- how backups are handled and when they expire;
- the support contact and how users can reach it;
- whether deletion means immediate removal, staged removal, or removal with a stated backup exception.

Until those facts are confirmed, do not present a retention promise or support address in the app.
