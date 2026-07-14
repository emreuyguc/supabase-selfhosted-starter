# Supabase Self-Hosted Starter User Guide

This guide is the human-facing operating document for this repository.

It covers local validation, Docker Compose usage and where to find layer-specific operating details.

## What this repository provides

This is a production-oriented Supabase self-hosting starter for one Supabase stack.

Primary artifacts:

| Path | Purpose |
|---|---|
| `compose.yaml` | Canonical Docker Compose stack |
| `compose.full.yaml` | Explicit full-stack variant overlay |
| `compose.external-db.yaml` | External Postgres variant overlay |
| `compose.external-prebuilt.yaml` | External preconfigured database variant overlay |
| `compose.features.external-s3.yaml` | External S3 object storage feature overlay |
| `compose.prod.yaml` | Production override for restart policy and bounded logs |
| `.env.example` | Complete non-secret env inventory |
| `.env.<variant>.example` | Variant-specific env examples |
| `files/` | Supabase config, SQL init files, Edge Functions, Kong, Vector and pooler files |
| `dokploy/template.json` | Generated Dokploy import template |
| `dokploy/templates/*.json` | Generated Dokploy variant import templates |
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
SUPABASE_PUBLIC_URL=http://example.com ./scripts/generate-env.sh --variant full
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
- Dokploy template JSON;
- embedded Dokploy Compose syntax;
- required bind-mounted files.

## Run with Docker Compose

Local/basic:

```sh
docker compose --env-file .env -f compose.yaml -f compose.full.yaml up -d
```

Production-style override:

```sh
docker compose --env-file .env -f compose.yaml -f compose.full.yaml -f compose.prod.yaml up -d
```

Validate production-style config without starting containers:

```sh
docker compose --env-file .env -f compose.yaml -f compose.full.yaml -f compose.prod.yaml config --quiet
```

External Postgres variant:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db.yaml up -d
```

This variant runs the external DB bootstrap job first. Use it when the external Postgres host is reachable but Supabase roles, databases, schemas and extensions still need to be prepared.

The external Postgres provider must be Supabase-compatible enough to expose `pg_net`, `pg_graphql` and `pg_cron` in `pg_available_extensions`. `pg_cron` may also require provider-side preload/configuration before `CREATE EXTENSION pg_cron` succeeds. If the provider cannot support these extensions, use `external-prebuilt` only with a database that was already restored/configured with the required Supabase state.

`supabase-db-bootstrap` is a one-shot Compose job. If bootstrap SQL changes, the bootstrap failed halfway, or the external database target changes, rerun that job explicitly before starting the runtime services again:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db.yaml up --force-recreate supabase-db-bootstrap
```

External preconfigured/restored database variant:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-prebuilt.yaml up -d
```

This variant does not run DB bootstrap SQL and disables Realtime/Supavisor migration commands. Supavisor/pooler still runs inside this stack; only its DB-side schema/state is assumed to already exist. Use this variant only for a restored or already configured Supabase database.

External S3 feature overlay:

```sh
docker compose --env-file .env -f compose.yaml -f compose.external-db.yaml -f compose.features.external-s3.yaml up -d
```

When using external S3, the local MinIO and bucket bootstrap services are not activated. The S3 provider must already expose the bucket and credentials declared in `.env`.

Only Kong should be exposed publicly by default. Keep Postgres, MinIO, Logflare, pg-meta and internal APIs private.

## Dokploy

Dokploy usage and generation details live in `dokploy/README.md`.

## Coolify

Support level:

- this repository does not keep a separate Coolify artifact;
- use root `compose.yaml` as the manual/user-defined Compose base;
- this is not a Coolify one-click catalog template;
- operators must ensure `files/` is available relative to the deployed bundle or adapt bind paths in the target platform.

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
