# LOOPA schema bootstrap

This baseline describes the application schema at `e5b0af1d57f27a44b7542fe486af2525d423fc73` and hosted migration `20261121140032`. The first historical migration alters `public.loopa_chat18`, which predates the SQL in this repository. Keep the baseline outside `supabase/migrations` so the CLI never queues it for an existing project.

## Verify on an empty database

Run `bash supabase/bootstrap/verify.sh` from the repository. It needs Docker and Python 3. The script starts a disposable PostgreSQL 17 container without network access and creates the minimal Supabase Auth, Storage and Realtime objects required by the application schema. It applies `schema.sql` in one transaction, checks that a second apply refuses to run, compares the catalog fingerprints and runs the SQL suites in `tests/`.

The baseline creates the private avatar bucket and adds the messages table to the Realtime publication. The catalog comparison includes existing table, column, schema and function privileges, RLS, triggers and function definitions. The fixture substitutes for managed Auth and Storage. Before a hosted staging installation, review ownership of `public.rls_auto_enable()`, the existing `ensure_rls` event trigger and the privileges provided by the target. A full rehearsal with Supabase services and Edge Functions remains a separate check.

## Historical versions

The hosted journal contains 36 entries and the repository contains 44 historical SQL files at the baseline. Of the 36 hosted entries, 33 match repository content after ignoring formatting differences. Three earlier definitions differ from the checked-in files. Their current effects are accounted for as follows.

| Hosted version | Current baseline and repository trail |
| --- | --- |
| `20261108235233` | The subscription table, invite delivery marker and restricted delivery claim are present. `20261109031000_telegram_bot_invite_notifications.sql` records the repository implementation. `20261109083000_fix_bot_subscription_service_grants.sql` and `20261109092000_fix_bot_invite_claim_block_check.sql` record the later grants and block checks. |
| `20261110051955` | The schema keeps `share_room_activity` and the current activity RPC. `20261110080000_friends_only_activity.sql` and `20261110093000_fix_room_activity_freshness.sql` record intervening changes. `20261121085615_respect_room_access_in_friend_activity.sql` supplies the current RPC behavior for private rooms. |
| `20261115132758` | The schema keeps the current collaboration columns, context checks and RPCs. `20261114131500_authoritative_collaboration.sql`, `20261115162000_shared_control_explicit_grant.sql` and `20261115171240_playback_command_context.sql` record the lineage. `20261120184424_require_room_command_context.sql` requires the video and grant context for guest commands. |

Replaying those earlier definitions on top of the baseline could replace current behavior. The baseline includes no production rows or media. Recover archived account and application data, Storage objects, Edge configuration, grants for future objects and migration history in a separate restore rehearsal.

## Rollback

An error before commit rolls back the schema transaction. Recreate the disposable staging database after a committed rehearsal. Removing the bootstrap files from Git has no effect on deployed databases.
