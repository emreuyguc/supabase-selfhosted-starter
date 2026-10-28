-- This security-definer function requires the bootstrap owner to read pg_authid.
-- Providers which prohibit it cannot use this starter's managed Supavisor.
\set app_db `printf '%s' "$POSTGRES_DB"`
\connect :app_db

CREATE SCHEMA IF NOT EXISTS pgbouncer;
REVOKE ALL ON SCHEMA pgbouncer FROM PUBLIC;
GRANT USAGE ON SCHEMA pgbouncer TO pgbouncer;

CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_usename text)
RETURNS TABLE(username text, password text)
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT rolname::text,
    CASE WHEN rolvaliduntil < now() THEN NULL ELSE rolpassword::text END
  FROM pg_authid WHERE rolname = p_usename AND rolcanlogin
$$;
REVOKE ALL ON FUNCTION pgbouncer.get_auth(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pgbouncer.get_auth(text) TO pgbouncer;
