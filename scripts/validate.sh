#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "Validating root compose..."
docker compose --env-file .env.example -f compose.yaml config --quiet

echo "Validating full variant compose..."
docker compose --env-file .env.full.example -f compose.yaml -f compose.full.yaml config --quiet

if [ -f compose.prod.yaml ]; then
  echo "Validating production compose override..."
  docker compose --env-file .env.example -f compose.yaml -f compose.prod.yaml config --quiet
  docker compose --env-file .env.full.example -f compose.yaml -f compose.full.yaml -f compose.prod.yaml config --quiet
fi

echo "Validating external DB variant compose..."
docker compose --env-file .env.external-db.example -f compose.yaml -f compose.external-db.yaml config --quiet
if docker compose --env-file .env.external-db.example -f compose.yaml -f compose.external-db.yaml config --services | grep -qx supabase-db; then
  echo "external-db variant must not activate supabase-db" >&2
  exit 1
fi
if ! docker compose --env-file .env.external-db.example -f compose.yaml -f compose.external-db.yaml config --services | grep -qx supabase-db-bootstrap; then
  echo "external-db variant must activate supabase-db-bootstrap" >&2
  exit 1
fi

echo "Validating external prebuilt variant compose..."
docker compose --env-file .env.external-prebuilt.example -f compose.yaml -f compose.external-prebuilt.yaml config --quiet
if docker compose --env-file .env.external-prebuilt.example -f compose.yaml -f compose.external-prebuilt.yaml config --services | grep -qx supabase-db; then
  echo "external-prebuilt variant must not activate supabase-db" >&2
  exit 1
fi
if docker compose --env-file .env.external-prebuilt.example -f compose.yaml -f compose.external-prebuilt.yaml config --services | grep -qx supabase-db-bootstrap; then
  echo "external-prebuilt variant must not activate supabase-db-bootstrap" >&2
  exit 1
fi
if ! docker compose --env-file .env.external-prebuilt.example -f compose.yaml -f compose.external-prebuilt.yaml config --services | grep -qx supabase-supavisor; then
  echo "external-prebuilt variant must keep managed supabase-supavisor active" >&2
  exit 1
fi
if docker compose --env-file .env.external-prebuilt.example -f compose.yaml -f compose.external-prebuilt.yaml config | grep -Eq '/app/bin/migrate|supavisor eval'; then
  echo "external-prebuilt variant must not run Supavisor/Realtime migration commands" >&2
  exit 1
fi

echo "Validating external S3 feature overlay..."
docker compose --env-file .env.full.example --env-file .env.external-s3.example -f compose.yaml -f compose.full.yaml -f compose.features.external-s3.yaml config --quiet
if docker compose --env-file .env.full.example --env-file .env.external-s3.example -f compose.yaml -f compose.full.yaml -f compose.features.external-s3.yaml config --services | grep -Eq '^(supabase-minio|minio-createbucket)$'; then
  echo "external-s3 feature must not activate local MinIO services" >&2
  exit 1
fi
docker compose --env-file .env.external-db.example --env-file .env.external-s3.example -f compose.yaml -f compose.external-db.yaml -f compose.features.external-s3.yaml config --quiet
docker compose --env-file .env.external-prebuilt.example --env-file .env.external-s3.example -f compose.yaml -f compose.external-prebuilt.yaml -f compose.features.external-s3.yaml config --quiet

if [ -f compose.prod.yaml ]; then
  docker compose --env-file .env.external-db.example -f compose.yaml -f compose.external-db.yaml -f compose.prod.yaml config --quiet
  docker compose --env-file .env.external-prebuilt.example -f compose.yaml -f compose.external-prebuilt.yaml -f compose.prod.yaml config --quiet
  docker compose --env-file .env.external-db.example --env-file .env.external-s3.example -f compose.yaml -f compose.external-db.yaml -f compose.features.external-s3.yaml -f compose.prod.yaml config --quiet
  docker compose --env-file .env.external-prebuilt.example --env-file .env.external-s3.example -f compose.yaml -f compose.external-prebuilt.yaml -f compose.features.external-s3.yaml -f compose.prod.yaml config --quiet
fi

echo "Validating README generated summary..."
CHECK=1 ./scripts/render-readme.sh

echo "Validating Dokploy template JSON and embedded compose..."
python3 - <<'PY'
import json
from pathlib import Path
import yaml

templates = [
    Path("dokploy/template.json"),
    Path("dokploy/templates/full.json"),
    Path("dokploy/templates/full-external-s3.json"),
    Path("dokploy/templates/external-db.json"),
    Path("dokploy/templates/external-db-external-s3.json"),
    Path("dokploy/templates/external-prebuilt.json"),
    Path("dokploy/templates/external-prebuilt-external-s3.json"),
]
missing_templates = [str(path) for path in templates if not path.exists()]
if missing_templates:
    raise SystemExit("Missing Dokploy templates: " + ", ".join(missing_templates))

for template in templates:
    data = json.loads(template.read_text())
    if "compose" not in data or "config" not in data:
        raise SystemExit(f"{template} must contain compose and config")
    compose = yaml.safe_load(data["compose"])
    services = compose.get("services", {})
    if template.name in {"template.json", "full.json", "full-external-s3.json"} and "supabase-db" not in services:
        raise SystemExit(f"{template} must include supabase-db")
    if template.name in {"external-db.json", "external-db-external-s3.json", "external-prebuilt.json", "external-prebuilt-external-s3.json"} and "supabase-db" in services:
        raise SystemExit(f"{template} must not include supabase-db")
    if template.name in {"external-db.json", "external-db-external-s3.json"} and "supabase-db-bootstrap" not in services:
        raise SystemExit(f"{template} must include supabase-db-bootstrap")
    if template.name in {"external-prebuilt.json", "external-prebuilt-external-s3.json"} and "supabase-db-bootstrap" in services:
        raise SystemExit(f"{template} must not include supabase-db-bootstrap")
    if template.name in {"external-prebuilt.json", "external-prebuilt-external-s3.json"}:
        if "supabase-supavisor" not in services:
            raise SystemExit(f"{template} must keep managed supabase-supavisor")
        supavisor_command = str(services["supabase-supavisor"].get("command", ""))
        realtime_command = str(services["realtime-dev"].get("command", ""))
        forbidden = ("/app/bin/migrate", "supavisor eval", "Realtime.Release.seeds")
        if any(item in supavisor_command or item in realtime_command for item in forbidden):
            raise SystemExit(f"{template} must not run prebuilt DB migration or seed commands")
    if "external-s3" in template.name:
        for local_storage_service in ("supabase-minio", "minio-createbucket"):
            if local_storage_service in services:
                raise SystemExit(f"{template} must not include {local_storage_service}")

required_files = [
    "files/volumes/api/kong.yml",
    "files/volumes/api/kong-entrypoint.sh",
    "files/volumes/db/graphql.sql",
    "files/volumes/db/cron.sql",
    "files/volumes/logs/vector.yml",
    "files/volumes/pooler/pooler.exs",
    "files/entrypoint.sh",
    "files/volumes/db-bootstrap/bootstrap-external-db.sh",
    "files/volumes/db-bootstrap/00-roles.sql",
    "files/volumes/db-bootstrap/10-databases.sql",
    "files/volumes/db-bootstrap/20-app-schemas.sql",
    "files/volumes/db-bootstrap/30-internal-schemas.sql",
    "files/volumes/db-bootstrap/40-jwt-settings.sql",
    "files/volumes/db-bootstrap/50-graphql.sql",
    "files/volumes/db-bootstrap/60-cron.sql",
]
missing = [p for p in required_files if not Path(p).exists()]
if missing:
    raise SystemExit("Missing required bind-mounted files: " + ", ".join(missing))

print("Dokploy JSON, embedded compose and required files are valid.")
PY

sh -n files/volumes/db-bootstrap/bootstrap-external-db.sh

echo "Validation complete."
