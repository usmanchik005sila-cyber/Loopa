-- Event-trigger execution remains available to its owner; application roles
-- have no reason to execute this privileged infrastructure function.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
