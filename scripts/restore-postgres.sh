#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
BACKUP_FILE="${1:-${BACKUP_FILE:-}}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
  echo "Usage: CONFIRM_RESTORE=1 $0 /path/to/postgres-backup.sql" >&2
  exit 1
fi

if [ "${CONFIRM_RESTORE:-0}" != "1" ]; then
  echo "Refusing to restore without CONFIRM_RESTORE=1." >&2
  exit 1
fi

python3 "$ROOT_DIR/scripts/restore-postgres.py" "$ENV_FILE" "$BACKUP_FILE"
echo "Restored Postgres from $BACKUP_FILE"
