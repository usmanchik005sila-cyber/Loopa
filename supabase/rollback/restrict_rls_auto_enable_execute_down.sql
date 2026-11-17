-- Restore the pre-migration default EXECUTE grant only if a rollback is needed.
grant execute on function public.rls_auto_enable() to public;
