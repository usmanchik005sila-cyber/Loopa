# Security hardening — 2026-11-17

- Browser SDK pinned to supabase-js 2.119.0, the version served by the former @2 URL at verification time. SRI SHA-384 and crossorigin=anonymous verify the exact downloaded bytes. No API/version upgrade was introduced.
- Migration restrict_rls_auto_enable_execute removes EXECUTE from PUBLIC, anon, authenticated for the infrastructure event-trigger function. The postgres owner retains access. Application RPC grants are unchanged.
- Verification in a rolled-back transaction: application roles cannot execute the function; a newly created probe table still receives RLS automatically. The probe leaves no table behind.
- Supabase organization LOOPA is on Free. Native leaked-password protection requires Pro or higher and remains disabled. No billing changes were made. Once upgraded, enable it in Authentication → Email settings and verify the security advisor notice disappears.

Docs: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

Rollback SQL: rollback/restrict_rls_auto_enable_execute_down.sql (restores the old broad grant; use only if required).
