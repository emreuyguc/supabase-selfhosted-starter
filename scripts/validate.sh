#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "Validating manifest base Compose contract..."
python3 - <<'PY'
from pathlib import Path
import yaml

manifest = yaml.safe_load(Path("manifest.yaml").read_text())
base_compose = manifest.get("base_compose")
if base_compose != "compose.yaml":
    raise SystemExit("manifest.yaml base_compose must be compose.yaml")
if manifest.get("canonical_compose") != base_compose:
    raise SystemExit("manifest.yaml canonical_compose must match base_compose")
if not Path(base_compose).exists():
    raise SystemExit(f"Missing base compose file: {base_compose}")

for name, variant in manifest.get("variants", {}).items():
    compose_files = variant.get("compose_files", [])
    if not compose_files or compose_files[0] != base_compose:
        raise SystemExit(f"variant {name} must start compose_files with {base_compose}")

external_s3 = manifest.get("feature_overlays", {}).get("external-s3")
if not external_s3:
    raise SystemExit("manifest.yaml must define feature_overlays.external-s3")
if external_s3.get("status") != "base-compose":
    raise SystemExit("feature_overlays.external-s3 status must be base-compose")
if external_s3.get("compose_file") != "compose.features.external-s3.yaml":
    raise SystemExit("feature_overlays.external-s3 compose_file must be compose.features.external-s3.yaml")
if not Path(external_s3["compose_file"]).exists():
    raise SystemExit(f"Missing external S3 compose overlay: {external_s3['compose_file']}")
PY

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

echo "Validating Dokploy import JSON and embedded compose..."
python3 - <<'PY'
import json
from pathlib import Path
import yaml

templates = [
    Path("dokploy/templates/full-local.json"),
    Path("dokploy/templates/full-external-s3.json"),
    Path("dokploy/templates/external-db-local.json"),
    Path("dokploy/templates/external-db-external-s3.json"),
    Path("dokploy/templates/external-prebuilt-local.json"),
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
    if template.name in {"full-local.json", "full-external-s3.json"} and "supabase-db" not in services:
        raise SystemExit(f"{template} must include supabase-db")
    if template.name in {"external-db-local.json", "external-db-external-s3.json", "external-prebuilt-local.json", "external-prebuilt-external-s3.json"} and "supabase-db" in services:
        raise SystemExit(f"{template} must not include supabase-db")
    if template.name in {"external-db-local.json", "external-db-external-s3.json"} and "supabase-db-bootstrap" not in services:
        raise SystemExit(f"{template} must include supabase-db-bootstrap")
    if template.name in {"external-prebuilt-local.json", "external-prebuilt-external-s3.json"} and "supabase-db-bootstrap" in services:
        raise SystemExit(f"{template} must not include supabase-db-bootstrap")
    if template.name in {"external-prebuilt-local.json", "external-prebuilt-external-s3.json"}:
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
    storage_service = services.get("supabase-storage")
    if storage_service:
        storage_env = storage_service.get("environment", [])
        if isinstance(storage_env, list):
            env_names = {str(item).split("=", 1)[0] for item in storage_env}
        elif isinstance(storage_env, dict):
            env_names = set(storage_env)
        else:
            env_names = set()
        required_storage_s3 = {
            "STORAGE_BACKEND",
            "STORAGE_S3_BUCKET",
            "STORAGE_S3_ENDPOINT",
            "STORAGE_S3_FORCE_PATH_STYLE",
            "STORAGE_S3_REGION",
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY",
        }
        missing_storage_s3 = sorted(required_storage_s3 - env_names)
        if missing_storage_s3:
            raise SystemExit(
                f"{template} supabase-storage missing S3 env: "
                + ", ".join(missing_storage_s3)
            )
        forbidden_storage_s3 = sorted(
            env_names & {"GLOBAL_S3_ENDPOINT", "GLOBAL_S3_PROTOCOL", "GLOBAL_S3_FORCE_PATH_STYLE"}
        )
        if forbidden_storage_s3:
            raise SystemExit(
                f"{template} supabase-storage must use STORAGE_S3_* env, not: "
                + ", ".join(forbidden_storage_s3)
            )

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

required_local_password_roles = [
    "authenticator",
    "pgbouncer",
    "supabase_auth_admin",
    "supabase_functions_admin",
    "supabase_storage_admin",
]

required_bootstrap_password_roles = [
    "supabase_admin",
    "authenticator",
    "pgbouncer",
    "supabase_auth_admin",
    "supabase_functions_admin",
    "supabase_storage_admin",
]

local_roles_sql = Path("files/volumes/db/roles.sql").read_text()
missing_local_password_roles = [
    role for role in required_local_password_roles
    if f"ALTER USER {role} WITH PASSWORD :'pgpass';" not in local_roles_sql
]
if missing_local_password_roles:
    raise SystemExit(
        "files/volumes/db/roles.sql must set the shared Postgres password for: "
        + ", ".join(missing_local_password_roles)
    )

bootstrap_roles_sql = Path("files/volumes/db-bootstrap/00-roles.sql").read_text()
missing_bootstrap_password_roles = [
    role for role in required_bootstrap_password_roles
    if f"ALTER ROLE {role} WITH PASSWORD :'pgpass';" not in bootstrap_roles_sql
]
if missing_bootstrap_password_roles:
    raise SystemExit(
        "files/volumes/db-bootstrap/00-roles.sql must set the shared Postgres password for: "
        + ", ".join(missing_bootstrap_password_roles)
    )

print("Dokploy import JSON, embedded compose and required files are valid.")
PY

sh -n files/volumes/db-bootstrap/bootstrap-external-db.sh

echo "Validation complete."
