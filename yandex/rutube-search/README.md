# RUTUBE bridge security

Reconstructed from the owner's complete overlapping editor screenshots (lines 1–87). The HTTP handler, Supabase user check, RUTUBE query/pagination and result filtering are retained. Public Supabase configuration is not a secret.

The new database quota check runs before every catalog call, including direct calls to the public Yandex URL. It forwards the caller JWT to loopa_search_budget; there is no caller-supplied user id or adjustable quota. Missing/invalid quota responses fail closed with 503, exhaustion returns 429 and Retry-After.

Currently both the main Edge API and this bridge consume the shared search budget for an uncached RUTUBE query. This deliberately enforces a stricter effective allowance for that path (two tokens). Cached Edge results cost one token, direct bridge calls one. Autocomplete uses the separate suggestion budget. Per-account quotas do not prevent attackers rotating guest accounts.

Deployment: deploy-rutube-bridge.yml embeds the tested ZIP, uses only the existing GitHub Secret, and preserves the old version with tag before-rutube-limits-20261119. It refuses to overwrite a changed baseline or drop unexpected runtime configuration. Production version d4e0shn1vd4don2tmjgd remains the rollback code. To restore it, create a version with versionId set to that id and the baseline runtime/entrypoint/resources/timeout. Never print the service-account key, IAM token or raw cloud settings.

Tests: go test ./... covers successful result mapping, direct quota rejection without a RUTUBE call, malformed/unavailable quota, and missing auth. These tests use mocked HTTP transport. Deployment performs a real unauthenticated HTTP smoke check. A live authenticated user search remains a manual verification step.
