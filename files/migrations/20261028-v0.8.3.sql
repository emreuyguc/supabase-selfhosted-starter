-- Manual application-database migration. Review and back up before running.
-- This does not migrate component schemas; upgraded services do that separately.
BEGIN;
DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I RESET "app.settings.jwt_secret"', current_database());
END
$$;
GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role, supabase_functions_admin;
COMMIT;
NOTIFY pgrst, 'reload schema';
