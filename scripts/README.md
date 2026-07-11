# Scripts

This folder contains repeatable operator and generation scripts.

Keep script-specific behavior documented here instead of spreading detailed script usage across root docs.

## Commands

| Script | Make target | Purpose |
|---|---|---|
| `validate.sh` | `make validate` | Static validation for Compose, README summary, Dokploy JSON and required files |
| `render-readme.sh` | `make render-readme` | Regenerate README system/service summary from `manifest.yaml` |
| `render-dokploy.sh` | `make render-dokploy` | Regenerate `dokploy/template.json` from canonical sources |
| `generate-env.sh` | `make generate-env` | Generate `.env` with strong local secrets |
| `backup-postgres.sh` | `make backup-postgres` | Create a Postgres dump under `backups/` |
| `restore-postgres.sh` | none | Restore a Postgres dump; requires `CONFIRM_RESTORE=1` |
| `backup-minio.sh` | `make backup-minio` | Create a MinIO data archive under `backups/` |
| `restore-minio.sh` | none | Restore a MinIO archive; requires `CONFIRM_RESTORE=1` |

## Env generation

```sh
SUPABASE_PUBLIC_URL=https://example.com ./scripts/generate-env.sh
```

The generator refuses to overwrite `.env` unless `FORCE=1` is set:

```sh
FORCE=1 SUPABASE_PUBLIC_URL=https://example.com ./scripts/generate-env.sh
```

Optional generator inputs:

| Variable | Default |
|---|---|
| `OUTPUT_ENV` | `.env` |
| `SUPABASE_PUBLIC_URL` | `http://localhost:8000` |
| `CONTAINER_PREFIX` | `supabase` |
| `DASHBOARD_USERNAME` | `supabase` |
| `MINIO_ROOT_USER` | `supabase` |
| `GLOBAL_S3_BUCKET` | `stub` |
| `STORAGE_TENANT_ID` | `stub` |
| `REGION` | `stub` |

## Backup and restore

Backups are written to `backups/`, which is ignored by git.

Postgres:

```sh
./scripts/backup-postgres.sh
CONFIRM_RESTORE=1 ./scripts/restore-postgres.sh backups/postgres-YYYYMMDDTHHMMSSZ.sql
```

MinIO:

```sh
./scripts/backup-minio.sh
CONFIRM_RESTORE=1 ./scripts/restore-minio.sh backups/minio-YYYYMMDDTHHMMSSZ.tar.gz
```

Production backup strategy should add off-host storage, encryption, retention policy, restore drills and monitoring.

## Heavy script rule

When a script becomes non-trivial, document:

- required inputs;
- outputs;
- generated files;
- destructive behavior;
- validation command;
- whether it can be safely run in CI.

Prefer keeping complex logic in scripts over duplicating it manually in documentation.
