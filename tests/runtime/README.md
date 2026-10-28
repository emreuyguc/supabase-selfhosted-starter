# Runtime Tests

Runtime smoke tests are implemented with Vitest and TypeScript.

These tests require a live Supabase deployment. CI type-checks this package but does not run live runtime tests.

## Files

| Path | Purpose |
|---|---|
| `package.json` | Runtime test package scripts and dependencies |
| `vitest.config.ts` | Vitest config |
| `.env.example` | Runtime test env example |
| `src/env.ts` | Env loading and test config |
| `src/http.ts` | HTTP helpers and assertions |
| `src/realtime.ts` | Low-level Realtime WebSocket helper |
| `specs/*.test.ts` | Runtime smoke specs |

## Install

Use Node 20.19+ or 22.12+ to match the locked Vite/Vitest dependencies.

```sh
npm --prefix tests/runtime install
```

CI should use:

```sh
npm --prefix tests/runtime ci
```

## Configure

Copy the example:

```sh
cp tests/runtime/.env.example tests/runtime/.env
```

Or point the runner at another env file:

```sh
TEST_ENV_FILE=.env npm --prefix tests/runtime test
```

Required values:

- `TEST_SUPABASE_URL` or `SUPABASE_PUBLIC_URL`;
- `TEST_ANON_KEY` or `SERVICE_SUPABASEANON_KEY` or `ANON_KEY`;
- `TEST_SERVICE_ROLE_KEY` or `SERVICE_SUPABASESERVICE_KEY` or `SERVICE_ROLE_KEY`.

Optional values:

- `TEST_PUBLISHABLE_KEY`;
- `TEST_SECRET_KEY`;
- `TEST_DASHBOARD_USERNAME`;
- `TEST_DASHBOARD_PASSWORD`;
- `TEST_TLS_INSECURE`.

## Run

All runtime tests:

```sh
npm --prefix tests/runtime test
```

Single spec:

```sh
npm --prefix tests/runtime test -- specs/storage.test.ts
```

Type-check only:

```sh
npm --prefix tests/runtime run typecheck
```

## Coverage

The suite covers:

- Auth health and signup defaults;
- Auth admin create/delete;
- REST OpenAPI and CRUD;
- GraphQL introspection;
- Storage bucket/object/signed URL/image transform;
- Edge Function hello route;
- Realtime WebSocket upgrade, channel join and actual PostgreSQL INSERT/UPDATE/DELETE delivery with an RLS-hidden insert;
- pg-meta public/admin ACL;
- MCP direct access block;
- `pg_cron` schedule/list/unschedule.

It also verifies Studio basic auth, restricted REST schemas/OpenAPI, blocked
Realtime management endpoints, a two-part 7 MiB TUS upload with a byte hash,
and two-user Storage RLS with public and secret API keys alongside user JWTs.
Real S3 SigV4 upload/download and invalid-signature rejection use
`S3_PROTOCOL_ACCESS_KEY_ID` / `S3_PROTOCOL_ACCESS_KEY_SECRET`; this test skips only
when those optional protocol credentials were not supplied. Matrix runs supply
all credentials, so these tests run for every scenario.
The isolation test needs `JWT_SECRET` or `SERVICE_PASSWORD_JWT`; it skips when
the target's signing secret was not supplied. Matrix fixtures supply it.

TLS certificates are verified by default in HTTP and WebSocket tests.
Set `TEST_TLS_INSECURE=true` only for an intentional self-signed test endpoint.

## Disposable scenario matrix

```sh
make test-matrix
```

This starts all three DB variants with both local MinIO and external S3
(RustFS 1.0.4), sequentially. It checks real session/transaction pooler SQL
connections too. The external Postgres fixture starts with an empty `initdb`:
the image supplies extension binaries, but its Supabase init SQL is bypassed.
The prebuilt scenarios reuse the database migrated by the external-db-bootstrap scenario,
preserving keys and tenant identity. No existing `.env` or remote provider is used.
Every scenario uses the production overlay, including Storage
`NODE_ENV=production`, behind a disposable TLS terminator. The generated test CA
is explicitly trusted by the clients; certificate verification stays enabled.
An additional negative check rejects the endpoint without that trusted CA.
The `internal-db-minio` scenario additionally enables `FUNCTIONS_VERIFY_JWT=true` and
checks opaque-key translation, bad user JWTs and compatibility-header spoofing.
It also captures a quiesced deployment with the real backup helpers. After the
six scenarios, `recovery.py` restores its SQL roles/databases, PostgreSQL config
and MinIO objects into fresh volumes, checks Vault decryption and RLS, then
starts the prebuilt stack and verifies the saved Auth user/object over HTTPS
and runs the runtime suite again. An initialized target must reject replay.

Private credentials, boot/test logs and `results.json` stay in
`.scratch/runtime-matrix/<run>/`. Only this run's Docker projects/volumes are
removed automatically. These tests exercise local Linux containers and a test
TLS proxy; public certificate issuance, provider-specific infrastructure and a
deployment-platform UI need their own validation.

## Focused gateway and JWKS regression checks

```sh
make test-gateway-edge
```

This recovered and adapted check starts disposable Kong/Edge images using the
canonical image tags. It tests ES256 with local and remote JWKS, HS256,
compatibility-header stripping before user-function dispatch, opaque-key
translation, discovery routes, per-function `deno.jsonc` imports and the TCP
health probe. It never loads the deployment `.env` or starts a database.
Fixtures stay in project-local `.scratch/tmp/`; failure logs stay in `.scratch/`.
Docker, Node, PyYAML and network access to fetch the pinned JOSE package are needed.
The echo Storage upstream checks headers only; the six-scenario matrix tests
actual Storage RLS, S3 signatures and TUS behavior.

Tests create temporary resources and must clean them up.
