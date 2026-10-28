# Upgrade to the v0.8.3 self-hosted snapshot

This starter pins Supabase `self-hosted/v0.8.3` (2026-10-16), commit
`bc27d2661edd09a5d0b8d76ce33da6d4071a756e`. It is a customized Compose project;
the stock Supabase `update.sh` is not an updater for this repository.

Sources: [release notes](https://github.com/supabase/supabase/blob/bc27d2661edd09a5d0b8d76ce33da6d4071a756e/docker/CHANGELOG.md),
[tested image set](https://github.com/supabase/supabase/blob/bc27d2661edd09a5d0b8d76ce33da6d4071a756e/docker/docker-compose.yml),
[installation and security guide](https://supabase.com/docs/guides/self-hosting/docker).
Independently choosing every image's `latest` tag does not preserve Supabase's
tested service combination. Logflare 1.50.15 is intentional: upstream reports
broken Studio Postgres log queries with 1.52.0 and later.

## Configuration changes

| Setting | Previous value | Current value / action |
|---|---|---|
| `API_EXTERNAL_URL` | Gateway origin, implicit | Explicit Auth URL ending in `/auth/v1` |
| `SITE_URL` | Gateway origin | Application frontend, e.g. `https://app.example.com` |
| `PGRST_DB_SCHEMAS` | `public,storage,graphql_public` | `public,graphql_public`; use the Storage API for storage data |
| `KONG_STORAGE_CONNECT_TIMEOUT` | `60` | `60000` milliseconds |
| `KONG_STORAGE_WRITE_TIMEOUT` | `3600` | `3600000` milliseconds |
| `KONG_STORAGE_READ_TIMEOUT` | `3600` | `3600000` milliseconds |
| `DISABLE_SIGNUP` | `false` | `true` until signup is deliberately enabled |
| `ENABLE_EMAIL_SIGNUP` | `false` | Still `false`; this switches the entire email provider, including password login. Enable it when email authentication is needed; `DISABLE_SIGNUP` independently controls public registration. |
| `PG_META_DB_USER` | `supabase_admin` | `postgres`, as recommended upstream |
| `PGRST_APP_SETTINGS_JWT_SECRET` | Present | Removed; do not expose the signing secret as an app setting |
| `SUPABASE_JWKS` | Not available | Optional public JWKS for Edge; empty retains Auth JWKS discovery |
| Studio legacy `LOGFLARE_API_KEY`, `NEXT_PUBLIC_*` settings | Present | Replaced by the current upstream settings |
| `POOLER_POOL_MODE` | Ignored / hardcoded | Used by the pooler tenant configuration |
| Realtime `REGION` | Unset | `us-east-1`, upstream workaround for the reconnect gap |

The env generator produces these defaults for new installations. It creates new
secrets and **must not overwrite an existing production environment**. Merge new
settings into the existing secret file; preserve database passwords, JWT/API
keys, Realtime encryption keys, Supavisor keys and object-storage credentials.
The separate `POSTGRES_BOOTSTRAP_PASSWORD` is not a replacement for runtime role
passwords. Studio/pg-meta require the configured runtime password to work for
the `postgres` role too.

Storage's `STORAGE_S3_*`, `SERVER_REGION` and `UPLOAD_*` settings are supported
by the [1.81.0 configuration parser](https://github.com/supabase/storage/blob/v1.81.0/src/config.ts).
They are the current names for the old `GLOBAL_S3_*`, `REGION` and upload-size
aliases; duplicate JWT settings have been removed.

## Scenario name migration

Names now identify database preparation and the actual object store. These are
the same six topologies; service configuration and credentials are unchanged.

| Previous scenario | Current scenario |
|---|---|
| `full-local` | `internal-db-minio` |
| `full-external-s3` | `internal-db-external-s3` |
| `external-db-local` | `external-db-bootstrap-minio` |
| `external-db-external-s3` | `external-db-bootstrap-external-s3` |
| `external-prebuilt-local` | `external-db-existing-minio` |
| `external-prebuilt-external-s3` | `external-db-existing-external-s3` |

The env generator, Dokploy renderer and portable Compose renderer still accept
the old CLI values: `full` → `internal-db`, `external-db` →
`external-db-bootstrap`, `external-prebuilt` → `external-db-existing`, and
storage `local` → `minio`. The MinIO archive helper accepts both storage names.
New commands and generated artifact filenames use the current names.

Old `compose.full.yaml`, `compose.external-db.yaml`,
`compose.external-prebuilt.yaml` and their `.env.<variant>.example` paths remain
compatibility symlinks to the new files. Existing Docker commands therefore keep
working from a normal Git checkout. Generated Dokploy JSON files have moved to
the current scenario names in the table; update import paths and automation.
Installed deployments keep their existing containers, volumes and secrets:
changing a scenario name is not a data migration and requires no key generation.

## Existing database procedure

1. Preserve the old Compose/configuration, env, image versions, a restorable
   database backup and consistent object-storage backups. Schedule maintenance.
2. Merge the new env settings without regenerating credentials. Keep intentional
   timeout overrides, converting units where necessary.
3. Apply [the manual SQL migration](../files/migrations/20261028-v0.8.3.sql) to the
   application database with an authorized database owner/admin connection.
   Review the [dependency and verification notes](../files/migrations/README.md)
   first, particularly custom functions reading the old JWT database setting.
   Container init scripts run only on a new volume. Updating those files does
   not migrate an existing database.
   Existing databases created by this starter's `external-db-bootstrap` bootstrap also
   need the updated bootstrap contract: it prepares the restricted Realtime
   tenant role, schema and parameter permission before tenant CDC initialization.
   During maintenance, with preserved runtime passwords and an authorized
   bootstrap login, run:

   ```sh
   docker compose --env-file .env -f compose.yaml -f compose.external-db-bootstrap.yaml \
     -f compose.prod.yaml run --rm --no-deps supabase-db-bootstrap
   ```

   Review these scripts for custom/provider-managed databases first. This step
   does not replace component migrations for a prepared/prebuilt database.
4. Pull and recreate the selected stack. Storage, Auth and other services may
   migrate their schemas at startup. `external-db-existing` skips the explicit
   Realtime and Supavisor migration/seed startup paths; prepare these schemas with
   matching component migrations before using that topology.
5. Run the runtime suite before restoring traffic. After a Storage migration,
   rollback requires the matching database backup, old images/configuration and
   consistent object data. An image downgrade alone is insufficient.

**Storage 1.81.0 includes one-way database migrations.** If Storage
1.72.0–1.72.3 was ever used, follow the remediation linked in the release notes
before upgrading. Postgres remains 17.6.1.136 in this repository: never start
Postgres 17 on an old Postgres 15 data directory.

## Gateway and Edge changes

The gateway restricts the REST OpenAPI root to admin credentials, blocks
Realtime management APIs, and follows the new OAuth/OIDC and SAML discovery
paths. `/mcp` and `/api/mcp` remain blocked. Ordinary table requests still work
with public keys; Storage preserves real user JWTs and AWS SigV4 Authorization.

Edge uses upstream structured errors, retired-worker retries and a 150-second
request idle timeout with a 160-second gateway read timeout. The main worker's
wall-clock limit is 400 seconds. The health check tests the real TCP listener.
The unsupported `importMapPath` option is omitted; function-local import
configuration should live beside the function. JOSE is pinned to 6.2.13.

`FUNCTIONS_VERIFY_JWT=false` follows upstream. Public functions must implement
their own application authorization, or enable JWT verification. With verification
enabled, Kong removes client-supplied `sb-api-key` headers and injects a signed
compatibility JWT only for recognized opaque keys. The worker verifies it and
removes the header before dispatching to user code. A real user bearer takes
precedence. Keep the Edge container private behind Kong.

## Object storage and production

The [MinIO project](https://github.com/minio/minio) was archived on 2026-04-25.
Its last public release is 2025-10-15. The pinned [Coollabs rebuild](https://github.com/coollabsio/minio)
restores registry availability and includes `mc`, but it does not establish
ongoing MinIO security maintenance. Local MinIO is retained for compatibility
and development. **For new production deployments, choose external S3 backed by
a maintained service.**

RustFS is a supported Supabase S3 backend. The snapshot's RustFS 1.0.1 has a
later [policy-bypass advisory](https://github.com/rustfs/rustfs/security/advisories/GHSA-rhg6-jrf2-29c4).
Our external-S3 fixture instead uses stable [RustFS 1.0.4](https://github.com/rustfs/rustfs/releases/tag/1.0.4).
Changing the backend does not migrate existing objects: copy through S3 APIs and
validate object counts/bytes before switching. Never reuse a MinIO data volume
as a RustFS data directory.

Use HTTPS at the reverse proxy and set all public/Auth/frontend URLs accordingly.
Production Storage intentionally generates HTTPS TUS URLs. The loopback matrix
uses a disposable TLS terminator and a trusted test CA, verifies certificates,
and keeps Storage in `NODE_ENV=production`. Internal database and S3 traffic must stay on
a trusted private network/VPN; this starter does not provision external-provider
TLS certificates. Configure client TLS for providers outside that boundary.
The production overlay does not supply HA, monitoring or off-host backup storage.
Kong is retained for compatibility, but upstream has announced its future removal
in favor of Envoy. Vector's read-only socket mount still exposes the Docker API:
read-only mounting is not Docker API authorization.

## Deployment verification

`make validate` checks all six generated Dokploy artifacts against the canonical
overlays, including production policy, env coverage, TOML decoding and exact
mount contents. Templates use Docker Compose's merge implementation and never
load the deployment `.env` during rendering. Rendering requires Compose 2.24.4+
and validation requires Python 3.11+ (or an available `python3.11`) and PyYAML.

`python3 tests/runtime/matrix.py` creates isolated local projects and fresh
secrets under `.scratch/runtime-matrix/`. It tests all six combinations against
an empty, extension-capable external Postgres fixture and RustFS, then removes
its containers and volumes. `external-db-existing` reuses the already migrated
external database and preserved secrets. This is not a certification of every
managed database/S3 provider, a public TLS ingress or a Dokploy UI installation.

The Realtime image's `/app/run.sh` unconditionally runs migrations. Merely
setting `SEED_SELF_HOST=false` or replacing its command does not disable that.
The prebuilt overlay explicitly uses `tini` and `/app/bin/server`, preserving
file-descriptor limits without running that script. The other variants use the
image's standard migration/seed entrypoint once, without a duplicate command.
