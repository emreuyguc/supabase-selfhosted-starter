# Scripts

This folder contains repeatable operator and generation scripts.

Keep script-specific behavior documented here instead of spreading detailed script usage across root docs.

## Commands

| Script | Make target | Purpose |
|---|---|---|
| `validate.sh` | `make validate` | Static validation for variant Compose, README summary, Dokploy JSON and required files |
| `render-readme.sh` | `make render-readme` | Regenerate README system/service summary from `manifest.yaml` |
| `render-dokploy.sh` | `make render-dokploy`, `make -C dokploy render-all` | Regenerate `dokploy/template.json` and `dokploy/templates/*.json` from canonical sources |
| `generate-env.sh` | `make generate-env` | Generate `.env` with strong local secrets |
| `backup-postgres.sh` | `make backup-postgres` | Create a Postgres dump under `backups/` |
| `restore-postgres.sh` | none | Restore a Postgres dump; requires `CONFIRM_RESTORE=1` |
| `backup-minio.sh` | `make backup-minio` | Create a MinIO data archive under `backups/` |
| `restore-minio.sh` | none | Restore a MinIO archive; requires `CONFIRM_RESTORE=1` |

## Env generation

```sh
SUPABASE_PUBLIC_URL=http://example.com ./scripts/generate-env.sh --variant full
```

The generator refuses to overwrite `.env` unless `FORCE=1` is set:

```sh
FORCE=1 SUPABASE_PUBLIC_URL=http://example.com ./scripts/generate-env.sh --variant full
```

Supported variants:

| Variant | Behavior |
|---|---|
| `full` | Generates local-stack secrets and local Postgres/MinIO values |
| `external-db` | Generates Supabase secrets but requires external Postgres connection values from the shell |
| `external-prebuilt` | Same as external DB, intended for an already configured/restored Supabase database |

External DB variants require either `SERVICE_PASSWORD_POSTGRES` or `POSTGRES_PASSWORD`, and require `POSTGRES_HOSTNAME` unless `POSTGRES_HOST` is set. The `external-db` variant also requires `POSTGRES_BOOTSTRAP_PASSWORD` because it runs DB bootstrap SQL before runtime services start.

Generated output is concrete for the selected topology. Bootstrap variables are written only for `--variant external-db`, and external S3 backend variables are written only for `--storage external-s3`.

External S3 env generation:

```sh
SUPABASE_PUBLIC_URL=http://example.com \
POSTGRES_HOST=db.example.com \
POSTGRES_PASSWORD=runtime_db_password \
POSTGRES_BOOTSTRAP_PASSWORD=admin_db_password \
STORAGE_S3_ENDPOINT=http://s3.example.com \
STORAGE_S3_ACCESS_KEY_ID=s3_access_key \
STORAGE_S3_SECRET_ACCESS_KEY=s3_secret_key \
GLOBAL_S3_BUCKET=supabase-storage \
./scripts/generate-env.sh --variant external-db --storage external-s3
```

Optional generator inputs:

| Variable | Default |
|---|---|
| `VARIANT` | `full` |
| `STORAGE` | `local` |
| `OUTPUT_ENV` | `.env` |
| `SUPABASE_PUBLIC_URL` | `http://localhost:8000` |
| `CONTAINER_PREFIX` | `supabase` |
| `DASHBOARD_USERNAME` | `supabase` |
| `MINIO_ROOT_USER` | `supabase` |
| `GLOBAL_S3_BUCKET` | `stub` |
| `STORAGE_TENANT_ID` | `stub` |
| `REGION` | `stub` |
| `POSTGRES_HOST` | `supabase-db` for `full`; required for external variants when `POSTGRES_HOSTNAME` is unset |
| `POSTGRES_HOSTNAME` | same as `POSTGRES_HOST` |
| `POSTGRES_DB` | `postgres` |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_DB_OWNER` | `supabase_admin`, only written for `external-db` |
| `POSTGRES_BOOTSTRAP_DB` | `postgres`, only written for `external-db` |
| `POSTGRES_BOOTSTRAP_USER` | `postgres`, only written for `external-db` |
| `STORAGE_S3_REGION` | `REGION` or `us-east-1`, only written for `external-s3` |
| `STORAGE_S3_FORCE_PATH_STYLE` | `true`, only written for `external-s3` |

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
