# Server abuse limits

Per-account token buckets live in loopa_private.request_budgets (RLS, no application grants, auth.users FK with cascading removal). At most four rows per account. Counters are updated under a row lock, shared by all devices and Edge isolates. Values refill continuously; these are burst budgets, not exact rolling-minute caps.

| Action | Initial burst | Refill |
| --- | --- | --- |
| DM and room chat combined | 8 messages | 1 message/second |
| Create room | 5 rooms | 1 room/12 seconds |
| Full catalog search (all providers) | 10 requests | 1 request/3 seconds |
| Autocomplete (all providers) | 30 requests | 10 requests/second |

Message and room creation checks are AFTER INSERT database triggers, so direct DM inserts and room RPC calls cannot bypass them. Failed transactions do not consume budget. Trusted maintenance without an end-user JWT bypasses insert limits. Existing invite/report limits remain unchanged. Room reads, playback synchronization, joining rooms, history and inbox paging do not consume these budgets.

video-search checks an authenticated RPC budget before serving cached responses or calling an external API. Exhaustion returns HTTP 429, Retry-After and a Russian message; unavailable quota service returns 503 with no external search. The RPC takes no user id or adjustable quota. Authentication is still validated separately.

Validation: tests/abuse-rate-limits.sql runs with transactional fixtures in BEGIN/ROLLBACK. It covers burst rejection, shared messaging budget, refill, separate autocomplete budget, actor isolation and internal privileges. Node tests cover 429, failure closure and cached-call quotas. Actual parallel-connection load testing has not been performed.

Limits reduce abuse by one account; they do not stop distributed attacks or attackers continuously creating new anonymous accounts. Signup/IP-level protection is a separate layer. All Auth users, including anonymous guests, share the same per-account policy.

Rollback: deploy the previous video-search source before executing rollback/abuse_rate_limits_down.sql. The rollback keeps counters, so re-enabling should reuse the existing table rather than recreate it. No paid infrastructure is required.

## RUTUBE direct-call protection (2026-11-19)

The Yandex bridge now checks the same durable account quota before calling RUTUBE, including direct public URL calls. Source and Go tests live in yandex/rutube-search. Deployed version: d4eifd0b9quegqm2qt92. Previous version d4e0shn1vd4don2tmjgd is retained under before-rutube-limits-20261119 for rollback. Deployment smoke checks and independent calls rejected missing/invalid authorization with HTTP 401. Authenticated success, quota exhaustion and quota failure were verified with mocked HTTP transport, not a live user session.

An uncached RUTUBE search through Edge currently consumes two search tokens (Edge and bridge). This stricter allowance is documented; direct bridge calls consume one. Cached Edge results consume one. Autocomplete is unaffected and uses its own quota. These are per-account limits, not a global anti-DDoS boundary.
