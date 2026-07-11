#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "Validating root compose..."
docker compose --env-file .env.example -f compose.yaml config --quiet

if [ -f compose.prod.yaml ]; then
  echo "Validating production compose override..."
  docker compose --env-file .env.example -f compose.yaml -f compose.prod.yaml config --quiet
fi

echo "Validating README generated summary..."
CHECK=1 ./scripts/render-readme.sh

echo "Validating Dokploy template JSON and embedded compose..."
python3 - <<'PY'
import json
from pathlib import Path
import yaml

template = Path("dokploy/template.json")
data = json.loads(template.read_text())
if "compose" not in data or "config" not in data:
    raise SystemExit("dokploy/template.json must contain compose and config")
yaml.safe_load(data["compose"])

required_files = [
    "files/volumes/api/kong.yml",
    "files/volumes/api/kong-entrypoint.sh",
    "files/volumes/db/graphql.sql",
    "files/volumes/db/cron.sql",
    "files/volumes/logs/vector.yml",
    "files/volumes/pooler/pooler.exs",
    "files/entrypoint.sh",
]
missing = [p for p in required_files if not Path(p).exists()]
if missing:
    raise SystemExit("Missing required bind-mounted files: " + ", ".join(missing))

print("Dokploy JSON, embedded compose and required files are valid.")
PY

echo "Validation complete."
