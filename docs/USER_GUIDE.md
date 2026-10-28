# Supabase Self-Hosted Starter User Guide

This guide is the human-facing operating document for this repository.

It covers local validation, Docker Compose usage and where to find layer-specific operating details.

## What this repository provides

This is a production-oriented Supabase self-hosting starter for one Supabase stack.

Primary artifacts:

| Path | Purpose |
|---|---|
| `compose.yaml` | Canonical Docker Compose stack |
| `compose.internal-db.yaml` | Internal PostgreSQL variant overlay |
| `compose.external-db-bootstrap.yaml` | External PostgreSQL with bootstrap overlay |
| `compose.external-db-existing.yaml` | Existing external Supabase database overlay |
| `compose.features.external-s3.yaml` | External S3 object storage feature overlay |
| `compose.prod.yaml` | Production override for restart policy and bounded logs |
| `.env.example` | Complete non-secret env inventory |
| `.env.<variant>.example` | Variant-specific env examples |
| `files/` | Supabase config, SQL init files, Edge Functions, Kong, Vector and pooler files |
| `dokploy/templates/*.json` | Generated Dokploy import templates |
| `scripts/README.md` | Env generation, render, validation, backup and restore helpers |
| `dokploy/README.md` | Dokploy template generation and import behavior |
| `tests/README.md` | Test layer entrypoint |
| `tests/runtime/README.md` | Vitest/TypeScript runtime smoke tests |
| `manifest.yaml` | Service/image/feature inventory |

## Services and images

The current service/image inventory is generated into `README.md` from `manifest.yaml`.

Use `manifest.yaml` as the source of truth for service names, roles, image tags, public access policy and starter metadata.

## Env and scripts

For real local or production-like usage, generate secrets with:

```sh
SUPABASE_PUBLIC_URL=https://supabase.example.com SITE_URL=https://app.example.com ./scripts/generate-env.sh --variant internal-db
```

Script inputs, outputs, backup/restore behavior and safety notes live in `scripts/README.md`.

## Validate static artifacts

Run:

```sh
./scripts/validate.sh
```

or:

```sh
make validate
```

Validation checks:

- root and variant Compose syntax;
- production override syntax for supported variants;
- Dokploy import JSON;
- embedded Dokploy Compose syntax;
- required bind-mounted files.

## Run with Docker Compose

Local/basic:

```sh
docker compose --env-file .env -f compose.yaml -f compose.internal-db.yaml -f compose.local.yaml up -d
```

Production-style override:

```sh
docker compose --env-file .env -f compose.yaml -f compose.internal-db.yaml -f compose.prod.yaml up -d
```

Validate production-style config without starting containers:

```sh
docker compose --env-file .env -f compose.yaml -f compose.internal-db.yaml -f compose.prod.yaml config --quiet
```

External Postgres variant:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db-bootstrap.yaml up -d
```

This variant runs the external DB bootstrap job first. Use it when the external Postgres host is reachable but Supabase roles, databases, schemas and extensions still need to be prepared.

The external provider must expose `pg_net`, `pg_graphql` and `pg_cron`, support logical replication, and allow the bootstrap administrator to create roles/event triggers and read `pg_authid` for the managed pooler. `pg_cron` needs provider-side preload/configuration. Restricted managed Postgres is not automatically compatible. `external-db-existing` also needs these runtime capabilities; it cannot compensate for missing extensions or pooler permissions.

`supabase-db-bootstrap` is a one-shot Compose job. If bootstrap SQL changes, the bootstrap failed halfway, or the external database target changes, rerun that job explicitly before starting the runtime services again:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db-bootstrap.yaml up --force-recreate supabase-db-bootstrap
```

External preconfigured/restored database variant:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db-existing.yaml up -d
```

This variant does not run DB bootstrap SQL and disables Realtime/Supavisor migration commands. Supavisor/pooler still runs inside this stack; only its DB-side schema/state is assumed to already exist. Use this variant only for a restored or already configured Supabase database.

External S3 feature overlay:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db-bootstrap.yaml -f compose.features.external-s3.yaml up -d
```

When using external S3, the local MinIO and bucket bootstrap services are not activated. The S3 provider must already expose the bucket and credentials declared in `.env`.

Only Kong should be exposed publicly by default. Keep Postgres, MinIO, Logflare, pg-meta and internal APIs private.

## Dokploy

Dokploy usage and generation details live in `dokploy/README.md`.

## Coolify

Export one selected scenario at the repository root:

```sh
python3 scripts/render-compose.py --variant internal-db --storage external-s3
```

Use any of the three DB variants and either `minio` or `external-s3`. The export
includes production policy, retains env placeholders and omits disabled services.
It never reads deployment secrets. `compose.deploy.yaml` is ignored by Git;
place this selected export in your deployment repository/branch for Git automation.
Keep it at the repository root beside `files/`.

In Coolify, create a Git-based Docker Compose application. Set Base Directory to
`/` and Docker Compose Location to `/compose.deploy.yaml`. Enable **Preserve
repository during deployment** so bind-mounted files remain available. Enter the
real generated env values in Coolify's environment settings; opaque keys and JWT
aliases must stay consistent. Add a domain only to `supabase-kong`, internal port
`8000`, with HTTPS enabled. Match the public/Auth/frontend URLs to that domain.
Exclude one-shot bootstrap services from Coolify's overall health calculation
with its `exclude_from_hc: true` setting. Manage Edge Functions in Git or back up
host edits before redeploying.

This is a Compose export, not a Coolify one-click catalog entry. The
[official Compose guide](https://coolify.io/docs/applications/builds/docker-compose)
describes repository preservation, domains and one-shot health settings. Actual
platform UI deployment remains a separate operator verification step.

## Runtime smoke tests

Runtime test usage lives in `tests/runtime/README.md`.

## Backup and restore

Backup and restore script usage lives in `scripts/README.md`.

## Security expectations

- Keep real secrets out of git.
- Keep public/client keys away from admin routes.
- Never expose service-role or secret keys to browser/client code.
- Keep admin routes behind service/admin credentials.
- Keep Studio behind auth.
- Enable RLS with appropriate policies on every application table exposed to clients.
- Keep signup disabled until SMTP/SMS is configured intentionally.
- Keep only Kong public by default.
- Retest Storage S3/SigV4 behavior if Kong Storage auth changes.
- `supabase-vector` reads Docker container logs through a read-only Docker socket mount. Treat that host socket access as privileged operational surface and keep the deployment host trusted.

## Versioning

Project-specific branch and versioning policy lives in `docs/SUPABASE_AI_GUIDE.md`.

Operationally:

- `manifest.yaml` owns starter version, update date and image tags;
- `README.md` displays generated version/service summary from `manifest.yaml`;
- stable states should use immutable git tags after validation.

## Updated snapshot and storage maintenance

Read [the upgrade guide](UPGRADE.md) for required new URL values, changed defaults
and the existing-database migration. `external-db-existing` env generation requires
the restored deployment's existing JWT/API/encryption keys and pooler tenant ID;
it no longer silently replaces them with random values.

Local MinIO reuses the pinned Coollabs image containing `mc`; an unversioned
`minio/mc` pull is no longer needed. MinIO's upstream repository is archived.
Prefer maintained external S3 for new production deployments. Local HTTP access
uses `compose.local.yaml`; production uses a TLS reverse proxy and
`compose.prod.yaml`. Production Storage intentionally returns HTTPS TUS URLs.

## Fresh production environment with external S3

Use an existing bucket and server-side credentials for a maintained S3 service.
For a **new installation** without an existing `.env`:

```sh
SUPABASE_PUBLIC_URL=https://supabase.example.com \
SITE_URL=https://app.example.com \
STORAGE_S3_ENDPOINT=https://s3.example.com \
STORAGE_S3_BUCKET=supabase-storage \
STORAGE_S3_ACCESS_KEY_ID=replace_with_access_key \
STORAGE_S3_SECRET_ACCESS_KEY=replace_with_secret_key \
./scripts/generate-env.sh --variant internal-db --storage external-s3

docker compose --env-file .env -f compose.yaml -f compose.internal-db.yaml -f compose.features.external-s3.yaml -f compose.prod.yaml up -d --wait
```

Use a secret manager or secure shell environment for the actual credentials.
Configure the reverse proxy to Kong port 8000 and issue the TLS certificate
before exposing the service. For existing deployments, merge values while
preserving keys; do not regenerate `.env`. Database passwords used in connection
URIs must be URL-safe; the generator creates alphanumeric passwords.
