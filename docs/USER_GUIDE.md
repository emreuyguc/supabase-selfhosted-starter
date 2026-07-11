# Supabase Self-Hosted Starter User Guide

This guide is the human-facing operating document for this repository.

It covers local validation, Docker Compose usage and where to find layer-specific operating details.

## What this repository provides

This is a production-oriented Supabase self-hosting starter for one Supabase stack.

Primary artifacts:

| Path | Purpose |
|---|---|
| `compose.yaml` | Canonical Docker Compose stack |
| `compose.prod.yaml` | Production override for restart policy and bounded logs |
| `.env.example` | Complete non-secret env inventory |
| `files/` | Supabase config, SQL init files, Edge Functions, Kong, Vector and pooler files |
| `dokploy/template.json` | Generated Dokploy import template |
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
SUPABASE_PUBLIC_URL=https://example.com ./scripts/generate-env.sh
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

- root Compose syntax;
- production override syntax;
- Dokploy template JSON;
- embedded Dokploy Compose syntax;
- required bind-mounted files.

## Run with Docker Compose

Local/basic:

```sh
docker compose --env-file .env -f compose.yaml up -d
```

Production-style override:

```sh
docker compose --env-file .env -f compose.yaml -f compose.prod.yaml up -d
```

Validate production-style config without starting containers:

```sh
docker compose --env-file .env -f compose.yaml -f compose.prod.yaml config --quiet
```

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

## Versioning

Project-specific branch and versioning policy lives in `docs/SUPABASE_AI_GUIDE.md`.

Operationally:

- `manifest.yaml` owns starter version, update date and image tags;
- `README.md` displays generated version/service summary from `manifest.yaml`;
- stable states should use immutable git tags after validation.
