#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

VARIANT="${VARIANT:-full}"
STORAGE="${STORAGE:-local}"
OUTPUT="${OUTPUT:-dokploy/templates/full-local.json}"
RENDER_ALL="${RENDER_ALL:-1}"
VALIDATE="${VALIDATE:-1}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --variant)
      if [ "$#" -lt 2 ]; then
        echo "--variant requires a value" >&2
        exit 1
      fi
      VARIANT="$2"
      RENDER_ALL=0
      shift 2
      ;;
    --variant=*)
      VARIANT="${1#--variant=}"
      RENDER_ALL=0
      shift
      ;;
    --storage)
      if [ "$#" -lt 2 ]; then
        echo "--storage requires a value" >&2
        exit 1
      fi
      STORAGE="$2"
      RENDER_ALL=0
      shift 2
      ;;
    --storage=*)
      STORAGE="${1#--storage=}"
      RENDER_ALL=0
      shift
      ;;
    --output)
      if [ "$#" -lt 2 ]; then
        echo "--output requires a value" >&2
        exit 1
      fi
      OUTPUT="$2"
      RENDER_ALL=0
      shift 2
      ;;
    --output=*)
      OUTPUT="${1#--output=}"
      RENDER_ALL=0
      shift
      ;;
    --all)
      RENDER_ALL=1
      shift
      ;;
    --no-validate)
      VALIDATE=0
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$VARIANT" in
  full|external-db|external-prebuilt) ;;
  *)
    echo "Unsupported variant: $VARIANT" >&2
    echo "Supported variants: full, external-db, external-prebuilt" >&2
    exit 1
    ;;
esac

case "$STORAGE" in
  local|external-s3) ;;
  *)
    echo "Unsupported storage: $STORAGE" >&2
    echo "Supported storage: local, external-s3" >&2
    exit 1
    ;;
esac

python3 - "$VARIANT" "$STORAGE" "$OUTPUT" "$RENDER_ALL" <<'PY'
import copy
import json
import sys
from pathlib import Path
import yaml

variant = sys.argv[1]
storage = sys.argv[2]
output = Path(sys.argv[3])
render_all = sys.argv[4] == "1"

templates_dir = Path("dokploy/templates")
config_path = Path("dokploy/config.toml")
compose_path = Path("compose.yaml")
files_root = Path("files")

if not config_path.exists():
    raise SystemExit("dokploy/config.toml does not exist")
if not compose_path.exists():
    raise SystemExit("compose.yaml does not exist")
if not files_root.exists():
    raise SystemExit("files/ does not exist")

dokploy_config = config_path.read_text().rstrip()
compose = compose_path.read_text()
compose_data = yaml.safe_load(compose)

templates_dir.mkdir(parents=True, exist_ok=True)


def adjust_compose_paths(compose_text):
    # Dokploy template runs from a generated compose context where bind files are
    # referenced through ../files. The canonical root compose uses ./files.
    text = compose_text.replace("source: ./files/", "source: ../files/")
    return text.replace("- ./files/", "- ../files/")


def add_dokploy_fallbacks(compose_text):
    # Dokploy may keep platform-safe fallbacks in the generated artifact even
    # when root compose is strict. This protects imports where CONTAINER_PREFIX
    # is absent.
    text = compose_text.replace("name: ${CONTAINER_PREFIX}", "name: ${CONTAINER_PREFIX:-supabase}")
    return text.replace(
        "container_name: realtime-dev.${CONTAINER_PREFIX}.supabase-realtime",
        "container_name: realtime-dev.${CONTAINER_PREFIX:-supabase}.supabase-realtime",
    )


def variant_config(config_text, external_db=False, bootstrap=False, external_s3=False):
    text = config_text
    if external_s3:
        for line in [
            'minio_root_user = "supabase"',
            'minio_root_password = "${password:32}"',
            '"MINIO_ROOT_USER=${minio_root_user}",',
            '"MINIO_ROOT_PASSWORD=${minio_root_password}",',
            '"SERVICE_USER_MINIO=${minio_root_user}",',
            '"SERVICE_PASSWORD_MINIO=${minio_root_password}",',
        ]:
            text = text.replace(line + "\n", "")
    if external_db:
        text = text.replace(
            'postgres_password = "${password:32}"',
            'postgres_password = "replace_with_external_postgres_password"\npostgres_host = "db.example.com"',
        )
    if external_db and bootstrap:
        text = text.replace(
            'postgres_host = "db.example.com"',
            'postgres_host = "db.example.com"\npostgres_bootstrap_password = "replace_with_external_postgres_admin_password"',
        )
    if external_s3:
        text = text.replace(
            's3_access_key_id = "${password:32}"',
            's3_access_key_id = "${password:32}"\nglobal_s3_endpoint = "http://s3.example.com"\nglobal_s3_protocol = "http"\nglobal_s3_bucket = "supabase-storage"\nglobal_s3_access_key_id = "replace_with_external_s3_access_key"\nglobal_s3_secret_access_key = "replace_with_external_s3_secret_key"\nglobal_s3_region = "us-east-1"\nglobal_s3_force_path_style = "true"',
        )
    if external_db:
        text = text.replace(
            '"POSTGRES_HOST=supabase-db"',
            '"POSTGRES_HOST=${postgres_host}"',
        )
        text = text.replace(
            '"POSTGRES_HOSTNAME=supabase-db"',
            '"POSTGRES_HOSTNAME=${postgres_host}"',
        )
    if bootstrap:
        text = text.replace(
            '"POSTGRES_PORT=5432"',
            '"POSTGRES_PORT=5432",\n"POSTGRES_DB_OWNER=supabase_admin",\n"POSTGRES_BOOTSTRAP_DB=postgres",\n"POSTGRES_BOOTSTRAP_USER=postgres",\n"POSTGRES_BOOTSTRAP_PASSWORD=${postgres_bootstrap_password}"',
        )
    if external_s3:
        text = text.replace(
            '"GLOBAL_S3_BUCKET=supabase-storage"',
            '"GLOBAL_S3_BUCKET=${global_s3_bucket}"',
        )
        text = text.replace(
            '"REGION=us-east-1"',
            '"REGION=${global_s3_region}",\n"GLOBAL_S3_ENDPOINT=${global_s3_endpoint}",\n"GLOBAL_S3_PROTOCOL=${global_s3_protocol}",\n"GLOBAL_S3_FORCE_PATH_STYLE=${global_s3_force_path_style}",\n"STORAGE_S3_ACCESS_KEY_ID=${global_s3_access_key_id}",\n"STORAGE_S3_SECRET_ACCESS_KEY=${global_s3_secret_access_key}"',
        )
    return text


def remove_dependency(service, dependency):
    depends_on = service.get("depends_on")
    if isinstance(depends_on, dict):
        depends_on.pop(dependency, None)
        if not depends_on:
            service.pop("depends_on", None)
    elif isinstance(depends_on, list):
        service["depends_on"] = [item for item in depends_on if item != dependency]
        if not service["depends_on"]:
            service.pop("depends_on", None)


def add_dependency(service, dependency, condition):
    depends_on = service.setdefault("depends_on", {})
    if isinstance(depends_on, dict):
        depends_on[dependency] = {"condition": condition}


def add_bootstrap_service(data):
    services = data["services"]
    services["supabase-db-bootstrap"] = {
        "image": "supabase/postgres:17.6.1.136",
        "restart": "no",
        "environment": [
            "POSTGRES_HOSTNAME=${POSTGRES_HOSTNAME}",
            "POSTGRES_PORT=${POSTGRES_PORT}",
            "POSTGRES_BOOTSTRAP_DB=${POSTGRES_BOOTSTRAP_DB}",
            "POSTGRES_BOOTSTRAP_USER=${POSTGRES_BOOTSTRAP_USER}",
            "POSTGRES_BOOTSTRAP_PASSWORD=${POSTGRES_BOOTSTRAP_PASSWORD}",
            "POSTGRES_DB=${POSTGRES_DB}",
            "POSTGRES_DB_OWNER=${POSTGRES_DB_OWNER}",
            "SERVICE_PASSWORD_POSTGRES=${SERVICE_PASSWORD_POSTGRES}",
            "SERVICE_PASSWORD_JWT=${SERVICE_PASSWORD_JWT}",
            "JWT_EXPIRY=${JWT_EXPIRY}",
        ],
        "entrypoint": ["/bin/sh", "/db-bootstrap/bootstrap-external-db.sh"],
        "volumes": [
            {
                "type": "bind",
                "source": "../files/volumes/db-bootstrap",
                "target": "/db-bootstrap",
                "read_only": True,
            }
        ],
    }

    for name in [
        "supabase-analytics",
        "supabase-rest",
        "supabase-auth",
        "realtime-dev",
        "supabase-storage",
        "supabase-meta",
        "supabase-supavisor",
    ]:
        add_dependency(services[name], "supabase-db-bootstrap", "service_completed_successfully")


def apply_external_s3(data):
    services = data["services"]
    services.pop("supabase-minio", None)
    services.pop("minio-createbucket", None)
    storage = services["supabase-storage"]
    remove_dependency(storage, "supabase-minio")
    remove_dependency(storage, "minio-createbucket")
    env = storage.get("environment", [])
    replacements = {
        "SERVER_REGION=": "SERVER_REGION=${REGION}",
        "REGION=": "REGION=${REGION}",
        "GLOBAL_S3_BUCKET=": "GLOBAL_S3_BUCKET=${GLOBAL_S3_BUCKET}",
        "GLOBAL_S3_ENDPOINT=": "GLOBAL_S3_ENDPOINT=${GLOBAL_S3_ENDPOINT}",
        "GLOBAL_S3_PROTOCOL=": "GLOBAL_S3_PROTOCOL=${GLOBAL_S3_PROTOCOL}",
        "GLOBAL_S3_FORCE_PATH_STYLE=": "GLOBAL_S3_FORCE_PATH_STYLE=${GLOBAL_S3_FORCE_PATH_STYLE}",
        "AWS_ACCESS_KEY_ID=": "AWS_ACCESS_KEY_ID=${STORAGE_S3_ACCESS_KEY_ID}",
        "AWS_SECRET_ACCESS_KEY=": "AWS_SECRET_ACCESS_KEY=${STORAGE_S3_SECRET_ACCESS_KEY}",
    }
    new_env = []
    seen = set()
    for item in env:
        replaced = False
        for prefix, value in replacements.items():
            if item.startswith(prefix):
                new_env.append(value)
                seen.add(prefix)
                replaced = True
                break
        if not replaced:
            new_env.append(item)
    for prefix, value in replacements.items():
        if prefix not in seen:
            new_env.append(value)
    storage["environment"] = new_env

    volumes = data.get("volumes")
    if isinstance(volumes, dict):
        volumes.pop("supabase-minio-data", None)


def external_compose(prebuilt=False, bootstrap=False, external_s3=False):
    data = copy.deepcopy(compose_data)
    services = data["services"]
    services.pop("supabase-db", None)

    for service in services.values():
        if isinstance(service, dict):
            remove_dependency(service, "supabase-db")

    volumes = data.get("volumes")
    if isinstance(volumes, dict):
        volumes.pop("supabase-db-data", None)
        volumes.pop("supabase-db-config", None)

    if bootstrap:
        add_bootstrap_service(data)

    if prebuilt:
        realtime_env = services["realtime-dev"].get("environment", [])
        services["realtime-dev"]["environment"] = [
            "SEED_SELF_HOST=false" if item == "SEED_SELF_HOST=true" else item
            for item in realtime_env
        ]
        services["realtime-dev"]["command"] = "/app/bin/server"
        services["supabase-supavisor"]["command"] = [
            "/bin/sh",
            "-c",
            'if [ ! -f /etc/ssl/server.crt ]; then\n  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \\\n    -keyout /etc/ssl/server.key -out /etc/ssl/server.crt \\\n    -subj "/CN=supabase-pooler"\nfi\n/app/bin/server\n',
        ]

    if external_s3:
        apply_external_s3(data)

    return yaml.safe_dump(data, sort_keys=False)


def full_compose(external_s3=False):
    data = copy.deepcopy(compose_data)
    if external_s3:
        apply_external_s3(data)
    return yaml.safe_dump(data, sort_keys=False)


def render_data(compose_text, config_text):
    data = {}
    data["compose"] = add_dokploy_fallbacks(adjust_compose_paths(compose_text))
    data["config"] = config_text.rstrip() + "\n\n" + "\n\n".join(mount_blocks) + "\n"
    return data


def build_artifact(selected_variant, selected_storage):
    external_s3 = selected_storage == "external-s3"

    if selected_variant == "full":
        return render_data(
            full_compose(external_s3=external_s3) if external_s3 else compose,
            variant_config(dokploy_config, external_s3=external_s3),
        )

    if selected_variant == "external-db":
        return render_data(
            external_compose(prebuilt=False, bootstrap=True, external_s3=external_s3),
            variant_config(dokploy_config, external_db=True, bootstrap=True, external_s3=external_s3),
        )

    if selected_variant == "external-prebuilt":
        return render_data(
            external_compose(prebuilt=True, external_s3=external_s3),
            variant_config(dokploy_config, external_db=True, external_s3=external_s3),
        )

    raise SystemExit(f"Unsupported variant: {selected_variant}")


def preset_name(selected_variant, selected_storage):
    return f"{selected_variant}-{selected_storage}.json"


mount_files = []
for path in sorted(files_root.rglob("*")):
    if path.is_file() and path.name != ".gitkeep":
        if path.name.startswith("."):
            continue
        rel = path.relative_to(files_root).as_posix()
        if rel == "entrypoint.sh":
            file_path = "/entrypoint.sh"
        else:
            file_path = "/" + rel
        mount_files.append((file_path, path))

mount_blocks = []
for file_path, source_path in mount_files:
    content = source_path.read_text()
    mount_blocks.append(
        f'[[config.mounts]]\nfilePath = "{file_path}"\ncontent = """{content}"""'
    )

if render_all:
    presets = [
        ("full", "local"),
        ("full", "external-s3"),
        ("external-db", "local"),
        ("external-db", "external-s3"),
        ("external-prebuilt", "local"),
        ("external-prebuilt", "external-s3"),
    ]
    for selected_variant, selected_storage in presets:
        data = build_artifact(selected_variant, selected_storage)
        (templates_dir / preset_name(selected_variant, selected_storage)).write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        )
    print(f"Rendered {templates_dir}/*.json from compose.yaml and files/ ({len(mount_files)} mounts).")
else:
    output.parent.mkdir(parents=True, exist_ok=True)
    data = build_artifact(variant, storage)
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"Rendered {output} for variant={variant} storage={storage} from compose.yaml and files/ ({len(mount_files)} mounts).")
PY

if [ "$VALIDATE" = "1" ]; then
  ./scripts/validate.sh
fi
