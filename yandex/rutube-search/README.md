# RUTUBE bridge security

Reconstructed from the owner's complete overlapping editor screenshots (lines 1–87). The HTTP handler, Supabase user check, RUTUBE query/pagination and result filtering are retained. Public Supabase configuration is not a secret.

The new database quota check runs before every catalog call, including direct calls to the public Yandex URL. It forwards the caller JWT to loopa_search_budget; there is no caller-supplied user id or adjustable quota. Missing/invalid quota responses fail closed with 503, exhaustion returns 429 and Retry-After.

Currently both the main Edge API and this bridge consume the shared search budget for an uncached RUTUBE query. This deliberately enforces a stricter effective allowance for that path (two tokens). Cached Edge results cost one token, direct bridge calls one. Autocomplete uses the separate suggestion budget. Per-account quotas do not prevent attackers rotating guest accounts.

Deployment: deploy-rutube-bridge.yml tests the checked-out Go source and packages that same source. It uses the existing GitHub Secret and tags the previous active version as rollback-<version-id>. It aborts if the active version changes during preparation or if the runtime settings cannot be preserved.

Tests: go test ./... covers successful result mapping, missing auth, malformed requests, Auth outages, and quota rejection before a RUTUBE call. These tests use mocked HTTP transport. Deployment checks that the live bridge returns 401 for missing authorization and 400 for malformed input, and rolls back on failure. The Edge API forwards 429 and Retry-After to the Mini App. Live authenticated RUTUBE searches are separate from the deployment checks.
