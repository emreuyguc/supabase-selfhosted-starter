#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import json
from pathlib import Path

template_path = Path("dokploy/template.json")
config_path = Path("dokploy/config.toml")
compose_path = Path("compose.yaml")
files_root = Path("files")

if not config_path.exists():
    raise SystemExit("dokploy/config.toml does not exist")
if not compose_path.exists():
    raise SystemExit("compose.yaml does not exist")
if not files_root.exists():
    raise SystemExit("files/ does not exist")

data = {}
dokploy_config = config_path.read_text().rstrip()

compose = compose_path.read_text()

# Dokploy template runs from a generated compose context where bind files are
# referenced through ../files. The canonical root compose uses ./files.
dokploy_compose = compose.replace("source: ./files/", "source: ../files/")
dokploy_compose = dokploy_compose.replace("- ./files/", "- ../files/")

# Dokploy may keep platform-safe fallbacks in the generated artifact even when
# root compose is strict. This protects imports where CONTAINER_PREFIX is absent.
dokploy_compose = dokploy_compose.replace("name: ${CONTAINER_PREFIX}", "name: ${CONTAINER_PREFIX:-supabase}")
dokploy_compose = dokploy_compose.replace(
    "container_name: ${CONTAINER_PREFIX}.supabase-realtime",
    "container_name: ${CONTAINER_PREFIX:-supabase}.supabase-realtime",
)

data["compose"] = dokploy_compose

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

data["config"] = dokploy_config + "\n\n" + "\n\n".join(mount_blocks) + "\n"

template_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
print(f"Rendered {template_path} from compose.yaml and files/ ({len(mount_files)} mounts).")
PY

./scripts/validate.sh
