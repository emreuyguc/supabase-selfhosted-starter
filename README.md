# Supabase Self-Hosted Starter

Fast, production-oriented Supabase self-hosting starter for Docker Compose and Dokploy.

This repository is Supabase-specific. It is designed as a clean single-app starter/boilerplate kit, not a multi-app catalog.

## Quick start

Generate a real local env:

```sh
SUPABASE_PUBLIC_URL=http://localhost:8000 ./scripts/generate-env.sh --variant full
```

Validate the stack:

```sh
make validate
```

Run with Docker Compose:

```sh
docker compose --env-file .env -f compose.yaml -f compose.full.yaml up -d
```

Run with production override:

```sh
docker compose --env-file .env -f compose.yaml -f compose.full.yaml -f compose.prod.yaml up -d
```

Run an external DB variant:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db.yaml up -d
```

Run with an external S3 backend:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db.yaml -f compose.features.external-s3.yaml up -d
```

Run smoke tests against a live deployment:

```sh
cp tests/runtime/.env.example tests/runtime/.env
npm --prefix tests/runtime install
npm --prefix tests/runtime test
```

## Dokploy quick usage

Use the generated Dokploy import template matching the target topology:

```text
dokploy/template.json
dokploy/templates/full.json
dokploy/templates/full-external-s3.json
dokploy/templates/external-db.json
dokploy/templates/external-db-external-s3.json
dokploy/templates/external-prebuilt.json
dokploy/templates/external-prebuilt-external-s3.json
```

If you changed `compose.yaml`, `files/` or `dokploy/config.toml`, regenerate it first:

```sh
make -C dokploy render-all
```

Build a selected Dokploy template:

```sh
make -C dokploy render-template VARIANT=external-db STORAGE=external-s3
```

Then import the selected file in Dokploy. `dokploy/template.json` is kept as the full-stack compatibility artifact.

Dokploy-specific variables, domains and env mappings are defined in:

```text
dokploy/config.toml
```

The template embeds required files from `files/` as Dokploy mounts, so do not edit `dokploy/template.json` by hand.

## Common commands

| Command | Purpose |
|---|---|
| `make validate` | Validate variant Compose, Dokploy templates and required files |
| `make render-readme` | Regenerate README system/service summary from `manifest.yaml` |
| `make render-dokploy` | Regenerate Dokploy templates |
| `make generate-env` | Generate `.env` with strong local secrets |
| `make backup-postgres` | Create a Postgres backup under `backups/` |
| `make backup-minio` | Create a MinIO data backup under `backups/` |
| `make typecheck-runtime` | Type-check the Vitest runtime test package |
| `make test-smoke` | Run Vitest runtime smoke tests |

<!-- BEGIN GENERATED:STACK_SUMMARY -->

## System summary

| Field | Value |
|---|---|
| App | `supabase` |
| Starter version | `0.1.0` |
| Last updated | `2026-07-14` |
| Repository type | `single-app-template` |
| Canonical Compose | `compose.yaml` |
| Production override | `compose.prod.yaml` |
| Env example | `.env.example` |
| Runtime tests | `tests/runtime` |
| Test framework | `vitest` |
| Dokploy artifact | `dokploy/template.json` |

## Variant inventory

Generated from `manifest.yaml`.

| Variant | Status | Topology | Env example |
|---|---|---|---|
| `full` | current-default | local-postgres-local-minio | `.env.full.example` |
| `external-db` | supported-compose-overlay | external-postgres-with-bootstrap | `.env.external-db.example` |
| `external-prebuilt` | supported-compose-overlay | external-postgres-managed-pooler-runtime-only | `.env.external-prebuilt.example` |

## Feature Overlay Inventory

Generated from `manifest.yaml`.

| Overlay | Status | Topology | Env example |
|---|---|---|---|
| `external-s3` | supported-feature-overlay | external-object-storage | `.env.external-s3.example` |

## Service inventory

Generated from `manifest.yaml`.

| Service | Role | Image | Public access |
|---|---|---|---|
| `supabase-kong` | public-api-gateway | `kong/kong:3.9.1` | `true` |
| `supabase-studio` | dashboard | `supabase/studio:2026.06.03-sha-0bca601` | `behind-kong-basic-auth` |
| `supabase-db` | database | `supabase/postgres:17.6.1.136` | `false` |
| `supabase-analytics` | analytics-logs | `supabase/logflare:1.31.2` | `false` |
| `supabase-vector` | log-router | `timberio/vector:0.53.0-alpine` | `false` |
| `supabase-auth` | auth | `supabase/gotrue:v2.189.0` | `via-kong` |
| `supabase-rest` | rest-api | `postgrest/postgrest:v14.12` | `via-kong` |
| `realtime-dev` | realtime | `supabase/realtime:v2.102.3` | `via-kong` |
| `supabase-storage` | storage-api | `supabase/storage-api:v1.60.4` | `via-kong` |
| `supabase-minio` | object-storage | `ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z` | `false` |
| `minio-createbucket` | object-storage-bootstrap | `minio/mc` | `false` |
| `supabase-edge-functions` | edge-functions | `supabase/edge-runtime:v1.74.0` | `via-kong` |
| `imgproxy` | image-transformer | `darthsim/imgproxy:v3.30.1` | `false` |
| `supabase-meta` | postgres-admin-api | `supabase/postgres-meta:v0.96.6` | `via-kong-admin-acl` |
| `supabase-supavisor` | connection-pooler | `supabase/supavisor:2.9.5` | `false` |

<!-- END GENERATED:STACK_SUMMARY -->

## Primary files

| Path | Purpose |
|---|---|
| `compose.yaml` | Canonical Docker Compose stack |
| `compose.full.yaml` | Explicit full-stack variant overlay |
| `compose.external-db.yaml` | External Postgres variant overlay |
| `compose.external-prebuilt.yaml` | External preconfigured database variant overlay |
| `compose.features.external-s3.yaml` | External S3 object storage feature overlay |
| `compose.prod.yaml` | Production override for restart policy and bounded Docker logs |
| `.env.example` | Non-secret complete env inventory |
| `.env.full.example` | Full-stack env example |
| `.env.external-db.example` | External DB env example |
| `.env.external-prebuilt.example` | External preconfigured DB env example |
| `.env.external-s3.example` | External S3 env example |
| `files/` | Supabase runtime config, init SQL, Edge Functions, Kong, Vector and pooler files |
| `dokploy/template.json` | Generated Dokploy import template |
| `dokploy/templates/*.json` | Generated Dokploy variant templates |
| `manifest.yaml` | Machine-readable source for versions, services, features and validation commands |
| `scripts/README.md` | Script usage, inputs, outputs and safety notes |
| `dokploy/README.md` | Dokploy template generation and import details |
| `tests/README.md` | Test layer entrypoint |
| `tests/runtime/README.md` | Vitest runtime test usage and coverage |
| `docs/USER_GUIDE.md` | Human-facing usage and operations guide |
| `docs/STARTER_KIT_AI_RULES.md` | Generic AI checklist/rules for starter-kit repositories |
| `docs/SUPABASE_AI_GUIDE.md` | Supabase-specific AI/development guide |
| `docs/DOCUMENTATION_STRUCTURE.md` | Documentation policy |

## Important notes

- Do not commit real `.env` files or deployment secrets.
- `manifest.yaml` is the machine-readable inventory for version/service metadata.
- `compose.yaml` is the canonical stack source.
- Dokploy artifact changes must be generated, not hand-edited.
- Coolify can use the root Compose file as a manual/user-defined Compose base; there is no separate Coolify artifact in this repo.

## Docs

- [User guide](docs/USER_GUIDE.md)
- [Generic starter-kit AI rules](docs/STARTER_KIT_AI_RULES.md)
- [Supabase AI guide](docs/SUPABASE_AI_GUIDE.md)
- [Documentation structure](docs/DOCUMENTATION_STRUCTURE.md)
