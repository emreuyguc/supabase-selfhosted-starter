#!/bin/sh
set -eu

: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"

export PGHOST=/run/postgresql
export PGPORT="${POSTGRES_PORT:-5432}"
export PGDATABASE="${POSTGRES_DB:-postgres}"

psql --username supabase_admin --no-password --set=ON_ERROR_STOP=1 --file=/sync-passwords.sql
