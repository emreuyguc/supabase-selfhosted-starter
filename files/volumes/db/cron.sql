-- Enable PostgreSQL scheduled jobs for admin/developer workflows.
-- pg_cron is available in the Supabase Postgres image and installs its objects
-- in the cron schema while the extension itself is registered in pg_catalog.
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Keep cron management admin-only by default. Application roles should not be
-- able to create, modify or inspect scheduled jobs unless the developer grants
-- that explicitly for a specific project.
REVOKE ALL ON SCHEMA cron FROM PUBLIC;
GRANT USAGE ON SCHEMA cron TO postgres, supabase_admin, service_role;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA cron FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA cron TO postgres, supabase_admin, service_role;

REVOKE ALL ON ALL TABLES IN SCHEMA cron FROM PUBLIC, anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA cron TO postgres, supabase_admin, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA cron REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA cron GRANT SELECT ON TABLES TO postgres, supabase_admin, service_role;
