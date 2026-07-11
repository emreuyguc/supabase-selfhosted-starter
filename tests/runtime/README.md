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
- Realtime WebSocket upgrade and channel join;
- pg-meta public/admin ACL;
- MCP direct access block;
- `pg_cron` schedule/list/unschedule.

Tests create temporary resources and must clean them up.
