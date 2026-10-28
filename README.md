# Supabase Self-Hosted Starter

Fast, production-oriented Supabase self-hosting starter for Docker Compose and Dokploy.

This repository is Supabase-specific. It is designed as a clean single-app starter/boilerplate kit, not a multi-app catalog.

## Deployment scenarios

Choose a database setup and an object store. Scenario names combine these two choices:

| Scenario | Database | Object store |
|---|---|---|
| `internal-db-minio` | PostgreSQL created by this stack | MinIO in this stack |
| `internal-db-external-s3` | PostgreSQL created by this stack | External S3-compatible service |
| `external-db-bootstrap-minio` | External PostgreSQL prepared by the bootstrap job | MinIO in this stack |
| `external-db-bootstrap-external-s3` | External PostgreSQL prepared by the bootstrap job | External S3-compatible service |
| `external-db-existing-minio` | Previously prepared/restored external Supabase database | MinIO in this stack |
| `external-db-existing-external-s3` | Previously prepared/restored external Supabase database | External S3-compatible service |

Use `--variant internal-db`, `external-db-bootstrap` or `external-db-existing`,
with `--storage minio` or `external-s3`. An external database must support the
required Supabase extensions, permissions and logical replication; a generic
managed PostgreSQL instance is not automatically compatible. Existing databases
skip the explicit Realtime/Supavisor startup migration paths, while other services
can still run their own migrations.

For previous names, command aliases and file-path compatibility, see the
[upgrade guide](docs/UPGRADE.md#scenario-name-migration).

## Quick start

Generate a real local env:

```sh
SUPABASE_PUBLIC_URL=http://localhost:8000 ./scripts/generate-env.sh --variant internal-db
```

Validate the stack:

```sh
make validate
```

Run with Docker Compose:

```sh
docker compose --env-file .env -f compose.yaml -f compose.internal-db.yaml -f compose.local.yaml up -d
```

The local overlay publishes only `127.0.0.1:8000`. For production, configure a
TLS reverse proxy and first configure a maintained external S3 backend as described
in the [user guide](docs/USER_GUIDE.md). Then apply the production override:

```sh
docker compose --env-file .env -f compose.yaml -f compose.internal-db.yaml -f compose.features.external-s3.yaml -f compose.prod.yaml up -d
```

Run an external DB variant:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db-bootstrap.yaml up -d
```

Run with an external S3 backend:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db-bootstrap.yaml -f compose.features.external-s3.yaml up -d
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
dokploy/templates/internal-db-minio.json
dokploy/templates/internal-db-external-s3.json
dokploy/templates/external-db-bootstrap-minio.json
dokploy/templates/external-db-bootstrap-external-s3.json
dokploy/templates/external-db-existing-minio.json
dokploy/templates/external-db-existing-external-s3.json
```

If you changed the base Compose file, variant overlays, `files/` or `dokploy/config.toml`, regenerate first:

```sh
make -C dokploy render-all
```

Build a selected Dokploy template:

```sh
make -C dokploy render-template VARIANT=external-db-bootstrap STORAGE=external-s3
```

Then import the selected file in Dokploy.

Dokploy-specific variables, domains and env mappings are defined in:

```text
dokploy/config.toml
```

The templates embed required files from `files/` as Dokploy mounts, so do not edit generated JSON files by hand.

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
| `make test-matrix` | Test all six topologies with disposable local fixtures |

<!-- BEGIN GENERATED:STACK_SUMMARY -->

## System summary

| Field | Value |
|---|---|
| App | `supabase` |
| Starter version | `0.2.0` |
| Last updated | `2026-10-28` |
| Repository type | `single-app-template` |
| Canonical base Compose | `compose.yaml` |
| Production override | `compose.prod.yaml` |
| Env example | `.env.example` |
| Runtime tests | `tests/runtime` |
| Test framework | `vitest` |
| Dokploy artifact | `dokploy/templates/internal-db-minio.json` |

## Variant inventory

Generated from `manifest.yaml`.

| Variant | Status | Topology | Env example |
|---|---|---|---|
| `internal-db` | current-default | internal-postgres | `.env.internal-db.example` |
| `external-db-bootstrap` | supported-compose-overlay | external-postgres-with-bootstrap | `.env.external-db-bootstrap.example` |
| `external-db-existing` | supported-compose-overlay | existing-external-postgres-managed-pooler | `.env.external-db-existing.example` |

## Feature Overlay Inventory

Generated from `manifest.yaml`.

| Overlay | Status | Topology | Env example |
|---|---|---|---|
| `external-s3` | base-compose | external-object-storage | `.env.external-s3.example` |

## Service inventory

Generated from `manifest.yaml`.

| Service | Role | Image | Public access |
|---|---|---|---|
| `supabase-kong` | public-api-gateway | `kong/kong:3.9.3` | `true` |
| `supabase-studio` | dashboard | `supabase/studio:2026.10.12-sha-3699278` | `behind-kong-basic-auth` |
| `supabase-db` | database | `supabase/postgres:17.6.1.136` | `false` |
| `supabase-analytics` | analytics-logs | `supabase/logflare:1.50.15` | `false` |
| `supabase-vector` | log-router | `timberio/vector:0.53.0-alpine` | `false` |
| `supabase-auth` | auth | `supabase/gotrue:v2.197.0` | `via-kong` |
| `supabase-rest` | rest-api | `postgrest/postgrest:v14.18` | `via-kong` |
| `realtime-dev` | realtime | `supabase/realtime:v2.143.3` | `via-kong` |
| `supabase-storage` | storage-api | `supabase/storage-api:v1.81.0` | `via-kong` |
| `supabase-minio` | object-storage | `ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z` | `false` |
| `minio-createbucket` | object-storage-bootstrap | `ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z` | `false` |
| `supabase-edge-functions` | edge-functions | `supabase/edge-runtime:v1.77.4` | `via-kong` |
| `imgproxy` | image-transformer | `darthsim/imgproxy:v3.31.4` | `false` |
| `supabase-meta` | postgres-admin-api | `supabase/postgres-meta:v0.100.0` | `via-kong-admin-acl` |
| `supabase-supavisor` | connection-pooler | `supabase/supavisor:2.9.13` | `false` |

<!-- END GENERATED:STACK_SUMMARY -->

## Primary files

| Path | Purpose |
|---|---|
| `compose.yaml` | Canonical Docker Compose stack |
| `compose.internal-db.yaml` | Internal PostgreSQL variant overlay |
| `compose.external-db-bootstrap.yaml` | External PostgreSQL with bootstrap overlay |
| `compose.external-db-existing.yaml` | Existing external Supabase database overlay |
| `compose.features.external-s3.yaml` | External S3 object storage feature overlay |
| `compose.prod.yaml` | Production override for restart policy and bounded Docker logs |
| `.env.example` | Non-secret complete env inventory |
| `.env.internal-db.example` | Full-stack env example |
| `.env.external-db-bootstrap.example` | External DB env example |
| `.env.external-db-existing.example` | External preconfigured DB env example |
| `.env.external-s3.example` | External S3 env example |
| `files/` | Supabase runtime config, init SQL, Edge Functions, Kong, Vector and pooler files |
| `dokploy/templates/*.json` | Generated Dokploy import templates |
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
- Local MinIO is retained for compatibility; its upstream project is archived. Prefer maintained external S3 for new production installations.
- Coolify can use the canonical Compose files from a Git repository; see the user guide for selecting overlays and keeping bind files available.

## Docs

- [User guide](docs/USER_GUIDE.md)
- [Upgrade and security changes](docs/UPGRADE.md)
- [Generic starter-kit AI rules](docs/STARTER_KIT_AI_RULES.md)
- [Supabase AI guide](docs/SUPABASE_AI_GUIDE.md)
- [Documentation structure](docs/DOCUMENTATION_STRUCTURE.md)
