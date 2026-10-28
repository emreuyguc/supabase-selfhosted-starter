# Scripts

This folder contains repeatable operator and generation scripts.

Keep script-specific behavior documented here instead of spreading detailed script usage across root docs.

## Commands

| Script | Make target | Purpose |
|---|---|---|
| `validate.sh` | `make validate` | Static validation for variant Compose, README summary, Dokploy JSON and required files |
| `render-readme.sh` | `make render-readme` | Regenerate README system/service summary from `manifest.yaml` |
| `render-dokploy.sh` | `make render-dokploy`, `make -C dokploy render-all` | Regenerate `dokploy/templates/*.json` from canonical sources |
| `generate-env.sh` | `make generate-env` | Generate `.env` with strong local secrets |
| `backup-postgres.sh` | `make backup-postgres` | Create a Postgres dump under `backups/` |
| `restore-postgres.sh` | none | Restore a Postgres dump; requires `CONFIRM_RESTORE=1` |
| `backup-minio.sh` | `make backup-minio` | Create a MinIO data archive under `backups/` |
| `restore-minio.sh` | none | Restore a MinIO archive; requires `CONFIRM_RESTORE=1` |

## Env generation

```sh
SUPABASE_PUBLIC_URL=http://example.com ./scripts/generate-env.sh --variant internal-db
```

The generator refuses to overwrite `.env` unless `FORCE=1` is set:

```sh
FORCE=1 SUPABASE_PUBLIC_URL=http://example.com ./scripts/generate-env.sh --variant internal-db
```

Supported variants:

Scenario names combine the database variant with `minio` or `external-s3`; see
the [scenario table](../README.md#deployment-scenarios). Legacy CLI values
`full`, `external-db`, `external-prebuilt` and storage `local` remain accepted
as aliases. Generated output uses the current names.

| Variant | Behavior |
|---|---|
| `internal-db` | Generates local-stack secrets and local Postgres/MinIO values |
| `external-db-bootstrap` | Generates Supabase secrets but requires external Postgres connection values from the shell |
| `external-db-existing` | Requires existing JWT/API/encryption keys and pooler tenant identity from the restored deployment |

External DB variants require either `SERVICE_PASSWORD_POSTGRES` or `POSTGRES_PASSWORD`, and require `POSTGRES_HOSTNAME` unless `POSTGRES_HOST` is set. The `external-db-bootstrap` variant also requires `POSTGRES_BOOTSTRAP_PASSWORD` because it runs DB bootstrap SQL before runtime services start.

Generated output is concrete for the selected topology. Bootstrap variables are written only for `--variant external-db-bootstrap`, and external S3 backend variables are written only for `--storage external-s3`.

External S3 env generation:

```sh
SUPABASE_PUBLIC_URL=http://example.com \
POSTGRES_HOST=db.example.com \
POSTGRES_PASSWORD=runtime_db_password \
POSTGRES_BOOTSTRAP_PASSWORD=admin_db_password \
STORAGE_S3_ENDPOINT=http://s3.example.com \
STORAGE_S3_ACCESS_KEY_ID=s3_access_key \
STORAGE_S3_SECRET_ACCESS_KEY=s3_secret_key \
STORAGE_S3_BUCKET=supabase-storage \
./scripts/generate-env.sh --variant external-db-bootstrap --storage external-s3
```

Optional generator inputs:

| Variable | Default |
|---|---|
| `VARIANT` | `internal-db` |
| `STORAGE` | `minio` |
| `OUTPUT_ENV` | `.env` |
| `SUPABASE_PUBLIC_URL` | `http://localhost:8000` |
| `CONTAINER_PREFIX` | `supabase` |
| `DASHBOARD_USERNAME` | `supabase` |
| `MINIO_ROOT_USER` | `supabase` |
| `STORAGE_S3_BUCKET` | `stub` |
| `STORAGE_TENANT_ID` | `stub` |
| `STORAGE_S3_REGION` | `us-east-1` |
| `POSTGRES_HOST` | `supabase-db` for `internal-db`; required for external variants when `POSTGRES_HOSTNAME` is unset |
| `POSTGRES_HOSTNAME` | same as `POSTGRES_HOST` |
| `POSTGRES_DB` | `postgres` |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_DB_OWNER` | `supabase_admin`, only written for `external-db-bootstrap` |
| `POSTGRES_BOOTSTRAP_DB` | `postgres`, only written for `external-db-bootstrap` |
| `POSTGRES_BOOTSTRAP_USER` | `postgres`, only written for `external-db-bootstrap` |
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

The Postgres helper writes a logical `pg_dumpall` using the local privileged
`supabase_admin` role, with permissions 0600. `backup-postgres.py` appends recovery
metadata for database ownership (including the built-in `postgres` database)
and the extension-owned Supabase GraphQL wrapper/schema grants. PostgreSQL's
ordinary dump omits these pieces; restoring only rows is insufficient to verify
Studio DDL and GraphQL. Older plain dumps need manual recovery of that metadata.
The built-in database behavior is documented in [PostgreSQL's pg_dumpall notes](https://www.postgresql.org/docs/17/app-pg-dumpall.html#APP-PG-DUMPALL-NOTES).
Failed dumps are removed. Restore
uses `ON_ERROR_STOP=1` and does not report success after SQL errors. A whole-cluster
dump contains roles/databases. The target must be an empty cluster initialized
with `initdb -U supabase_admin`, using matching PostgreSQL/extension binaries;
the normal Supabase initialization creates roles/schemas and is unsuitable for
this restore target. Preflight rejects existing application roles, databases and
relations. The redundant bootstrap-role creation is omitted only within the
dump's global roles preamble; PostgreSQL 17 grantor identities are preserved.
Keep the original environment secrets and `/etc/postgresql-custom` volume too,
including any encryption configuration needed by Vault. Restore the matching
object backup before reopening write traffic. See `tests/runtime/recovery.py`
for the disposable recovery fixture and service-level verification. External DB
providers require their own consistent backup/restore procedure.

MinIO archives are now **cold backups**. Stop Storage write traffic and every
container using the MinIO volume, leaving the MinIO container present. Then run
`backup-minio.sh`; it refuses live volumes. For restore, create a stopped MinIO
container with an empty named volume, using the matching image, then run
`CONFIRM_RESTORE=1 restore-minio.sh <archive>`. It rejects path traversal, links,
special files and nonempty targets. Restart the services after verifying the
restored objects. `STORAGE=external-s3` is rejected by the archive helper; use the
provider's object backup tools instead. Keep the database and object backup at
a mutually consistent point in time.

## Heavy script rule

When a script becomes non-trivial, document:

- required inputs;
- outputs;
- generated files;
- destructive behavior;
- validation command;
- whether it can be safely run in CI.

Prefer keeping complex logic in scripts over duplicating it manually in documentation.

## Snapshot upgrade and template verification

See [the upgrade guide](../docs/UPGRADE.md) before updating an existing deployment.
`generate-env.sh` is a fresh-install generator, not a secret-preserving updater.
It writes files with permissions 0600. `API_EXTERNAL_URL`, `SITE_URL` and
`ADDITIONAL_REDIRECT_URLS` can be supplied from the shell.

`compose_model.py` delegates overlay merging to Compose 2.24.4+ and isolates the
calling environment. Dokploy templates include `compose.prod.yaml` policy.
`validate-models.py` checks all six models, env references and decoded TOML mount
bytes; it needs Python 3.11+ (or a separate `python3.11`) and PyYAML.

`render-compose.py --variant <variant> --storage <storage>` exports one merged
production scenario to root `compose.deploy.yaml`, without deployment secrets.
It uses the same canonical model as the Dokploy renderer. Regenerate it after
changing Compose sources and keep `files/` beside it when deploying.
