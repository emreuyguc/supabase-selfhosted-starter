\set app_db `printf '%s' "$POSTGRES_DB"`
\connect :app_db

CREATE EXTENSION IF NOT EXISTS pg_cron;

REVOKE ALL ON SCHEMA cron FROM PUBLIC;
GRANT USAGE ON SCHEMA cron TO postgres, supabase_admin, service_role;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA cron FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA cron TO postgres, supabase_admin, service_role;

REVOKE ALL ON ALL TABLES IN SCHEMA cron FROM PUBLIC, anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA cron TO postgres, supabase_admin, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA cron REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA cron GRANT SELECT ON TABLES TO postgres, supabase_admin, service_role;
