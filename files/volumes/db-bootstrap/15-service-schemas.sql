-- Minimal Supabase database contract before Auth/Storage run their own migrations.
\set app_db `printf '%s' "$POSTGRES_DB"`
\connect :app_db

CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;
CREATE SCHEMA IF NOT EXISTS realtime AUTHORIZATION supabase_admin;
GRANT USAGE, CREATE ON SCHEMA realtime TO supabase_realtime_admin;
GRANT USAGE ON SCHEMA realtime TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT USAGE ON SCHEMA auth, storage, public TO postgres, anon, authenticated, service_role;
GRANT CREATE ON DATABASE :app_db TO supabase_auth_admin, supabase_storage_admin, supabase_admin;
GRANT supabase_auth_admin, supabase_storage_admin, supabase_functions_admin TO postgres;
GRANT authenticator TO supabase_storage_admin;
ALTER ROLE supabase_auth_admin SET search_path TO auth;
ALTER ROLE supabase_storage_admin SET search_path TO storage;
ALTER ROLE supabase_admin SET search_path TO public, extensions;

-- Auth owns and creates its JWT helper functions through its startup migrations.
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_storage_admin IN SCHEMA storage
  GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_storage_admin IN SCHEMA storage
  GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;

-- Postgres Changes must have a publication even before application tables exist.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END
$$;
