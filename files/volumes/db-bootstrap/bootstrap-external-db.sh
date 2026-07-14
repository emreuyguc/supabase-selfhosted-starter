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
required SERVICE_PASSWORD_JWT
required JWT_EXPIRY

export PGHOST="$POSTGRES_HOSTNAME"
export PGPORT="$POSTGRES_PORT"
export PGDATABASE="$POSTGRES_BOOTSTRAP_DB"
export PGUSER="$POSTGRES_BOOTSTRAP_USER"
export PGPASSWORD="$POSTGRES_BOOTSTRAP_PASSWORD"
export POSTGRES_PASSWORD="$SERVICE_PASSWORD_POSTGRES"
export JWT_SECRET="$SERVICE_PASSWORD_JWT"
export JWT_EXP="$JWT_EXPIRY"

echo "Checking external DB extension availability..."
psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  missing text;
BEGIN
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
END
$$;
SQL

for sql in /db-bootstrap/*.sql; do
  echo "Running external DB bootstrap: $sql"
  psql -v ON_ERROR_STOP=1 -f "$sql"
done

echo "External DB bootstrap complete."
