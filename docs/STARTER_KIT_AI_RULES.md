# Starter Kit AI Rules

This is the reusable AI-facing rulebook for single-application self-hosted starter, boilerplate and deployment-kit repositories.

It is intentionally not Supabase-specific. Reuse this file as the baseline for other repositories such as Appwrite, PocketBase, NocoDB, Plausible, Directus, MinIO, Keycloak or similar self-hosted apps.

## Mission

Each repository must package one application stack so a developer or operator can deploy it locally or in production-like environments with predictable Docker, env, storage, security, template and validation behavior.

Do not turn a single-app repository into a multi-app catalog. Create a separate repository per app when the app has its own lifecycle, image versions, runtime files, templates and tests.

## Mandatory documentation shape

Keep docs small and role-based:

| File | Audience | Purpose |
|---|---|---|
| `README.md` | Humans and AI | Short repo overview, artifact map, quick commands |
| `docs/USER_GUIDE.md` | Human operators/developers | Complete usage, deployment, env, backup, testing and security guide |
| `docs/STARTER_KIT_AI_RULES.md` | AI agents and maintainers | Generic reusable starter-kit checklist and rules |
| `docs/<APP>_AI_GUIDE.md` | AI agents and maintainers | App-specific source-of-truth, edge cases and development workflow |
| `docs/DOCUMENTATION_STRUCTURE.md` | Humans and AI | Records why the documentation is structured this way |

Avoid many small docs unless the project becomes large enough that one user guide is genuinely hard to use.

## Repository shape

Create folders only when they have a real job.

| Path | Rule |
|---|---|
| `compose.yaml` | Canonical Docker Compose stack when Compose is supported |
| `compose.prod.yaml` | Optional production override for restart/logging/resource policy |
| `.env.example` | Non-secret complete env inventory |
| `files/` | Only when runtime configs, init scripts, migrations, functions or static bind-mounted files are needed |
| `scripts/` | Only for repeatable generation, validation, setup, backup or test commands |
| `tests/` | Only when runtime or static tests are useful and maintainable |
| `<platform>/` | Only for a real platform artifact such as Dokploy. Do not create a platform folder when the root Compose file is sufficient |
| `manifest.yaml` | Recommended machine-readable inventory of services, versions, features and validation commands |

Empty decorative folders are not allowed.

## Documentation locality rule

Use central docs for project-wide decisions and use folder-level READMEs for layer-specific operation.

Recommended pattern:

| File | Purpose |
|---|---|
| `README.md` | Fast overview and common commands |
| `docs/USER_GUIDE.md` | Human-facing project guide and links to layer docs |
| `docs/<APP>_AI_GUIDE.md` | App-specific AI/development rules |
| `docs/DOCUMENTATION_STRUCTURE.md` | Records documentation policy |
| `scripts/README.md` | Script inputs, outputs, safety and CI usage |
| `tests/README.md` | Test entrypoint |
| `tests/<runner>/README.md` | Test runner setup, env and coverage |
| `<platform>/README.md` | Platform-specific generation/import behavior |

When a layer changes, update its local README first. Update central docs only when the public workflow or project-wide rule changes.

## Source-of-truth rules

- Keep one canonical Compose file.
- Generate platform-specific artifacts from canonical sources when possible.
- Do not hand-edit generated artifacts unless the generator is changed in the same commit.
- Keep image tags explicit and versioned.
- Keep env keys explicit; avoid hidden defaults for production-critical values.
- If an alias is required by an upstream image or platform, document the canonical source value.
- Remove unused env keys instead of keeping future placeholders.
- If a feature is optional, prefer both:
  - an env feature flag for runtime behavior;
  - a Compose profile for optional containers.

## Docker and Compose checklist

Before changing Docker/Compose, verify:

- official upstream images are sufficient before adding Dockerfiles;
- no secrets are passed as build args or baked into images;
- service names are stable and descriptive;
- internal service ports stay unchanged unless upstream requires a change;
- public ingress is limited to the gateway/proxy by default;
- databases, object stores, queues, caches, admin APIs and internal APIs are not publicly exposed by default;
- persistent data uses named volumes or documented bind mounts;
- config/init files are read-only where possible;
- writeable mounts are limited to data, cache or generated runtime state;
- healthchecks exist for critical services where upstream images support them;
- production overrides include restart strategy and bounded logs;
- `privileged`, broad `cap_add`, host network and Docker socket mounts are absent unless explicitly justified;
- `container_name` is avoided unless a fixed hostname is required by the app or platform.

## Env checklist

Before changing env:

- `.env.example` contains every required variable and no real secret;
- generated or documented real env flow exists when secrets are complex;
- variable names are grouped consistently;
- source-of-truth values are not duplicated under different names unless required;
- required values are not silently hidden inside Compose fallbacks;
- comments explain operational decisions, not obvious syntax;
- changing an env key updates Compose, platform templates, tests and docs.

## Platform template checklist

For each supported platform:

- define whether support is import-template, generated Compose, one-click catalog, or manual guide;
- document platform-specific path/env behavior;
- generate artifacts from canonical files where possible;
- validate generated artifacts in CI;
- keep platform credentials and domains out of committed static files unless they are placeholders required by that platform;
- do not claim full production support if the artifact has only been statically validated.

## Security checklist

Before release:

- client/public credentials cannot access admin routes;
- service/admin credentials are never exposed to browser/client use;
- signup defaults are safe when email/SMS is not configured;
- dashboards are protected by auth or platform access control;
- internal APIs are private by default;
- secrets are rotated by env changes, not image rebuilds;
- backup and restore instructions exist for stateful services;
- dangerous restore scripts require an explicit confirmation flag;
- runtime tests include at least one negative authorization check when admin routes exist.

## Test checklist

Use tests only where they add signal.

Recommended layers:

1. Static validation:
   - Compose parse;
   - generated template parse;
   - required file existence;
   - shell/python syntax;
   - generated artifact drift check.
2. Runtime smoke tests when a live test deployment exists:
   - health endpoints;
   - auth defaults;
   - CRUD path;
   - storage path;
   - admin route ACL;
   - optional feature smoke tests.
3. Fresh deploy test before calling a release production-ready.

## AI workflow

When an AI agent edits one of these repositories:

1. Inspect `git status --short`.
2. Read `README.md`, this file and `docs/<APP>_AI_GUIDE.md`.
3. Identify source-of-truth files affected by the request.
4. Make the smallest coherent change across all synchronized artifacts.
5. Regenerate generated artifacts.
6. Run static validation.
7. Do not run destructive runtime operations unless the user explicitly authorized them.
8. Report:
   - files changed;
   - validation performed;
   - what still needs runtime or fresh-deploy testing.

## Release/version rule

Keep versioning simple:

- record image versions in `manifest.yaml`;
- use immutable git tags for stable states;
- use app-oriented tags such as `<app>-<upstream-version>-v1`;
- GitHub Releases are optional unless users need packaged artifacts.
