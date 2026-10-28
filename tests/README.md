# Tests

Runtime smoke tests live in:

```text
tests/runtime/
```

Use the layer README for details:

```text
tests/runtime/README.md
```

Quick commands:

```sh
cp tests/runtime/.env.example tests/runtime/.env
npm --prefix tests/runtime install
npm --prefix tests/runtime test
```

Static check:

```sh
npm --prefix tests/runtime run typecheck
```

## Verified snapshot: 2026-10-28

Supabase `self-hosted/v0.8.3`, starter 0.2.0. Local Docker Engine 29.8.2,
Compose 5.5.0, Linux containers on arm64. Registry manifest inspection confirmed
both linux/amd64 and linux/arm64 images for every pinned service and RustFS 1.0.4.
Runtime execution was on arm64.

Scenario IDs below use the current names. They were renamed after the live run;
all six merged production Compose models were compared with the saved models
from before the rename and remained identical. Naming validation also checks
legacy CLI aliases and Compose/env compatibility paths.

| Scenario | Runtime tests | Supavisor 5432 / 6543 |
|---|---|---|
| `internal-db-minio` | 20 passed | Both ports passed |
| `internal-db-external-s3` | 20 passed | Both ports passed |
| `external-db-bootstrap-minio` | 20 passed | Both ports passed |
| `external-db-bootstrap-external-s3` | 20 passed | Both ports passed |
| `external-db-existing-minio` | 20 passed | Both ports passed |
| `external-db-existing-external-s3` | 20 passed | Both ports passed |

Total: **120 scenario tests + 2 JWT-enabled Edge tests + 20 tests on the recovered
stack = 142 runtime test executions**, plus **14 real pooler SQL probes** (12 in
the matrix, two after recovery). Coverage includes Auth/admin operations, REST CRUD/OpenAPI ACLs,
GraphQL, cron, Studio basic auth, Realtime WebSocket join and actual PostgreSQL
INSERT/UPDATE/DELETE delivery with an RLS-hidden insert, Storage object/signed
URL/image operations, two-user RLS, a 7 MiB two-part TUS upload with matching
bytes, and real S3 SigV4 upload/download with invalid-signature rejection.
Prebuilt Realtime startup was checked for absence of image-entrypoint migrations.
All six use HTTPS with an explicitly trusted test CA and certificate verification
enabled, plus Storage `NODE_ENV=production`. An untrusted-CA request was rejected.

Additional checks passed:

- All six Dokploy JSON/TOML artifacts match canonical Compose overlays, env
  references, production restart/log policy and source mount bytes.
- All six portable Compose exports parse and match the selected active services.
- Additional recovered regression checks pass: ES256 local/remote JWKS, HS256,
  user-function header stripping and function-local import discovery.
- Dokploy validation also performs an independent canonical CLI comparison,
  checks shell-command interpolation after a second Compose parse, rejects
  duplicate/unexpected mounts and isolates a deliberately poisoned fixture `.env`.
- TypeScript type checking, shell syntax and `git diff --check` pass.
- `npm audit`: zero reported vulnerabilities in the locked test dependency tree.
- Prebuilt env generation preserves 13 durable key/tenant values, rejects missing
  credentials and writes mode 0600 files.
- MinIO cold backup restored an object to a separate empty volume with matching
  bytes. Live archives, missing confirmation, traversal archives and nonempty
  restore targets were rejected.
- A fully migrated deployment was quiesced and backed up with the actual SQL and
  MinIO helpers. Recovery into fresh volumes preserved application and `_supabase`
  markers, roles/RLS, PostgreSQL config, a decryptable Vault secret, an Auth user
  and its password, and object bytes. The restored prebuilt stack passed all 20
  runtime tests, including Studio DDL, GraphQL and CDC, and both pooler SQL modes.
  The disposable target enables email login for the password check while keeping
  public registration disabled. Replaying into the populated target was rejected.
- Postgres backup files have mode 0600; failed dumps are removed and restore
  propagates SQL errors. The manual upgrade SQL ran twice without errors on a
  disposable Postgres 17 instance.

The external DB fixture starts with an empty initdb and Supabase extension
binaries; it does not use the image's preinstalled Supabase schemas. The prebuilt
scenarios preserve the migrated database and keys from the external-db-bootstrap scenarios.
RustFS 1.0.4 provides the independent external-S3 fixture. All test Docker
containers, networks and volumes were removed; private logs and credentials are
ignored under `.scratch/`.

Verification scope is local functional compatibility, production Storage behind
a test TLS proxy, logical/object recovery into the documented fresh target and
generated artifact consistency. Public domain/certificate issuance,
Dokploy/Coolify UI deployment, provider-specific TLS/IAM restrictions and load/HA
behavior require separate validation.
Container security decisions use the official tested snapshot and published
advisories; a full image CVE scan was not performed. See the [upgrade guide](../docs/UPGRADE.md)
for one-way migrations, the archived MinIO backend and production requirements.
