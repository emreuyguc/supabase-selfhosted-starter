#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

VARIANT="${VARIANT:-internal-db}"
STORAGE="${STORAGE:-minio}"
OUTPUT="${OUTPUT:-}"
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
  full) VARIANT=internal-db ;;
  external-db) VARIANT=external-db-bootstrap ;;
  external-prebuilt) VARIANT=external-db-existing ;;
  internal-db|external-db-bootstrap|external-db-existing) ;;
  *)
    echo "Unsupported variant: $VARIANT" >&2
    echo "Supported variants: internal-db, external-db-bootstrap, external-db-existing" >&2
    exit 1
    ;;
esac

case "$STORAGE" in
  local) STORAGE=minio ;;
  minio|external-s3) ;;
  *)
    echo "Unsupported storage: $STORAGE" >&2
    echo "Supported storage: minio, external-s3" >&2
    exit 1
    ;;
esac

OUTPUT="${OUTPUT:-dokploy/templates/$VARIANT-$STORAGE.json}"

python3 - "$VARIANT" "$STORAGE" "$OUTPUT" "$RENDER_ALL" <<'PY'
import json
import sys
from pathlib import Path
import yaml

sys.path.insert(0, str(Path("scripts").resolve()))
from compose_model import compose_model, dokploy_model

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

templates_dir.mkdir(parents=True, exist_ok=True)


def variant_config(config_text, external_db=False, bootstrap=False, external_s3=False):
    text = config_text
    if external_s3:
        for line in [
            'minio_root_user = "supabase"',
            'minio_root_password = "${password:32}"',
            '"MINIO_ROOT_USER=${minio_root_user}",',
            '"MINIO_ROOT_PASSWORD=${minio_root_password}",',
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
            's3_access_key_id = "${password:32}"\nstorage_s3_endpoint = "http://s3.example.com"\nstorage_s3_bucket = "supabase-storage"\nstorage_s3_access_key_id = "replace_with_external_s3_access_key"\nstorage_s3_secret_access_key = "replace_with_external_s3_secret_key"\nstorage_s3_region = "us-east-1"\nstorage_s3_force_path_style = "true"',
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
            '"STORAGE_S3_BUCKET=supabase-storage"',
            '"STORAGE_S3_BUCKET=${storage_s3_bucket}"',
        )
        text = text.replace(
            '"STORAGE_S3_REGION=us-east-1"',
            '"STORAGE_S3_REGION=${storage_s3_region}",\n"STORAGE_S3_ENDPOINT=${storage_s3_endpoint}",\n"STORAGE_S3_ACCESS_KEY_ID=${storage_s3_access_key_id}",\n"STORAGE_S3_SECRET_ACCESS_KEY=${storage_s3_secret_access_key}",\n"STORAGE_S3_FORCE_PATH_STYLE=${storage_s3_force_path_style}"',
        )
    return text


def build_artifact(selected_variant, selected_storage):
    model = dokploy_model(compose_model(Path.cwd(), selected_variant, selected_storage))
    return {
        "compose": yaml.safe_dump(model, sort_keys=False),
        "config": variant_config(
            dokploy_config,
            external_db=selected_variant != "internal-db",
            bootstrap=selected_variant == "external-db-bootstrap",
            external_s3=selected_storage == "external-s3",
        ).rstrip() + "\n\n" + "\n\n".join(mount_blocks) + "\n",
    }


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
        f'[[config.mounts]]\nfilePath = {json.dumps(file_path, ensure_ascii=False)}\ncontent = {json.dumps(content, ensure_ascii=False)}'
    )

if render_all:
    presets = [
        ("internal-db", "minio"),
        ("internal-db", "external-s3"),
        ("external-db-bootstrap", "minio"),
        ("external-db-bootstrap", "external-s3"),
        ("external-db-existing", "minio"),
        ("external-db-existing", "external-s3"),
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
