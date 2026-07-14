#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
import os
import yaml

readme_path = Path("README.md")
manifest = yaml.safe_load(Path("manifest.yaml").read_text())

begin = "<!-- BEGIN GENERATED:STACK_SUMMARY -->"
end = "<!-- END GENERATED:STACK_SUMMARY -->"

services = manifest["services"]
variants = manifest.get("variants", {})
feature_overlays = manifest.get("feature_overlays", {})

lines = [
    begin,
    "",
    "## System summary",
    "",
    "| Field | Value |",
    "|---|---|",
    f"| App | `{manifest['app']}` |",
    f"| Starter version | `{manifest['starter_version']}` |",
    f"| Last updated | `{manifest['last_updated']}` |",
    f"| Repository type | `{manifest['repository_type']}` |",
    f"| Canonical base Compose | `{manifest.get('base_compose', manifest['canonical_compose'])}` |",
    f"| Production override | `{manifest['production_override']}` |",
    f"| Env example | `{manifest['env_example']}` |",
    f"| Runtime tests | `{manifest['runtime_tests']}` |",
    f"| Test framework | `{manifest['test_framework']}` |",
    f"| Dokploy artifact | `{manifest['platform_templates']['dokploy']}` |",
    "",
    "## Variant inventory",
    "",
    "Generated from `manifest.yaml`.",
    "",
    "| Variant | Status | Topology | Env example |",
    "|---|---|---|---|",
]

for name, data in variants.items():
    lines.append(
        f"| `{name}` | {data['status']} | {data['topology']} | `{data['env_example']}` |"
    )

if feature_overlays:
    lines += [
        "",
        "## Feature Overlay Inventory",
        "",
        "Generated from `manifest.yaml`.",
        "",
        "| Overlay | Status | Topology | Env example |",
        "|---|---|---|---|",
    ]

    for name, data in feature_overlays.items():
        lines.append(
            f"| `{name}` | {data['status']} | {data['topology']} | `{data['env_example']}` |"
        )

lines += [
    "",
    "## Service inventory",
    "",
    "Generated from `manifest.yaml`.",
    "",
    "| Service | Role | Image | Public access |",
    "|---|---|---|---|",
]

for name, data in services.items():
    image = data["image"]
    role = data["role"]
    public = str(data["public"]).lower() if isinstance(data["public"], bool) else data["public"]
    lines.append(f"| `{name}` | {role} | `{image}` | `{public}` |")

lines += [
    "",
    end,
]

content = readme_path.read_text()
if begin not in content or end not in content:
    raise SystemExit(f"{readme_path} must contain generated summary markers")

before = content.split(begin, 1)[0].rstrip()
after = content.split(end, 1)[1].lstrip()
rendered = before + "\n\n" + "\n".join(lines) + "\n\n" + after

if os.environ.get("CHECK") == "1":
    if content != rendered:
        raise SystemExit("README generated summary is out of sync. Run: make render-readme")
    print("README generated summary is in sync.")
else:
    readme_path.write_text(rendered)
    print("Rendered generated README summary from manifest.yaml")
PY
