#!/usr/bin/env sh
set -eu

required() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "$name is required" >&2
    exit 1
  fi
}

required POSTGRES_HOSTNAME
required POSTGRES_PORT
required POSTGRES_BOOTSTRAP_DB
required POSTGRES_BOOTSTRAP_USER
required POSTGRES_BOOTSTRAP_PASSWORD
required POSTGRES_DB
required POSTGRES_DB_OWNER
required SERVICE_PASSWORD_POSTGRES
required JWT_EXPIRY

export PGHOST="$POSTGRES_HOSTNAME"
export PGPORT="$POSTGRES_PORT"
export PGDATABASE="$POSTGRES_BOOTSTRAP_DB"
export PGUSER="$POSTGRES_BOOTSTRAP_USER"
export PGPASSWORD="$POSTGRES_BOOTSTRAP_PASSWORD"
export POSTGRES_PASSWORD="$SERVICE_PASSWORD_POSTGRES"
export JWT_EXP="$JWT_EXPIRY"

# Use native superuser DDL during bootstrap. Supabase images load supautils
# per session, which can delegate extension hooks to a different role (even
# when the connecting role is a superuser). Keep this client-side only.
export PGOPTIONS="${PGOPTIONS:+$PGOPTIONS }-c session_preload_libraries="

echo "Checking external DB extension availability..."
psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  missing text;
  extension_superuser text;
BEGIN
  IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    RAISE EXCEPTION 'External DB bootstrap requires a PostgreSQL superuser; current user "%" is not a superuser', current_user
      USING HINT = 'Set POSTGRES_BOOTSTRAP_USER and POSTGRES_BOOTSTRAP_PASSWORD to the external server superuser credentials. Supabase images may use supabase_admin instead of postgres. Runtime credentials remain separate. Extension hooks (pg_read_file) and CREATE EVENT TRIGGER require elevated privileges.';
  END IF;

  -- A server may preload supautils globally, where the client override cannot
  -- unload it. Reject a broken delegation target before changing roles/schemas.
  SELECT setting INTO extension_superuser FROM pg_settings
  WHERE name = 'supautils.privileged_extensions_superuser';
  IF extension_superuser IS NOT NULL AND extension_superuser <> '' AND NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = extension_superuser AND rolsuper
  ) THEN
    RAISE EXCEPTION 'supautils extension delegation target "%" is not a PostgreSQL superuser', extension_superuser
      USING HINT = 'Have the external DB administrator correct supautils.privileged_extensions_superuser or load supautils per session instead of globally. Bootstrap does not change cluster configuration or elevate runtime roles.';
  END IF;

  SELECT string_agg(required_extension.name, ', ' ORDER BY required_extension.name)
  INTO missing
  FROM (VALUES ('pg_cron'), ('pg_graphql'), ('pg_net')) AS required_extension(name)
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_available_extensions
    WHERE pg_available_extensions.name = required_extension.name
  );

  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'External Postgres is missing required Supabase extensions: %', missing;
  END IF;

  IF NOT has_table_privilege(current_user, 'pg_authid', 'SELECT') THEN
    RAISE EXCEPTION 'Bootstrap owner must read pg_authid for the managed Supavisor auth function; this provider is not supported';
  END IF;
END
$$;
SQL

for sql in /db-bootstrap/*.sql; do
  echo "Running external DB bootstrap: $sql"
  psql -v ON_ERROR_STOP=1 -f "$sql"
done

echo "External DB bootstrap complete."
