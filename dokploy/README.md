# Dokploy

This folder contains the Dokploy-specific source config and generated import artifacts.

## Files

| Path | Purpose |
|---|---|
| `config.toml` | Dokploy variables, domains, env mappings and platform metadata |
| `Makefile` | Dokploy-specific render and validation commands |
| `templates/full-local.json` | Generated full-stack variant with local Postgres and local MinIO |
| `templates/full-external-s3.json` | Generated full-stack variant with external S3 |
| `templates/external-db-local.json` | Generated external Postgres variant with local MinIO |
| `templates/external-db-external-s3.json` | Generated external Postgres variant with external S3 |
| `templates/external-prebuilt-local.json` | Generated external preconfigured database variant with local MinIO |
| `templates/external-prebuilt-external-s3.json` | Generated external preconfigured database variant with external S3 |

## Usage

Regenerate the Dokploy template after changing any of:

- base Compose: `compose.yaml`;
- variant overlays: `compose.full.yaml`, `compose.external-db.yaml`, `compose.external-prebuilt.yaml`;
- feature overlays: `compose.features.external-s3.yaml`;
- mounted runtime files: `files/`;
- `dokploy/config.toml`;
- `scripts/render-dokploy.sh`.

Command:

```sh
make -C dokploy render-all
```

Render one selected template:

```sh
make -C dokploy render-template VARIANT=external-db STORAGE=external-s3
```

Render to a custom file under `dokploy/`:

```sh
make -C dokploy render VARIANT=external-prebuilt STORAGE=local OUTPUT=dokploy/templates/external-prebuilt-local.json
```

Then import the template matching the target topology:

| Import file | Base Compose | Variant overlay | Storage overlay |
|---|---|---|---|
| `dokploy/templates/full-local.json` | `compose.yaml` | `compose.full.yaml` | local MinIO |
| `dokploy/templates/full-external-s3.json` | `compose.yaml` | `compose.full.yaml` | `compose.features.external-s3.yaml` |
| `dokploy/templates/external-db-local.json` | `compose.yaml` | `compose.external-db.yaml` | local MinIO |
| `dokploy/templates/external-db-external-s3.json` | `compose.yaml` | `compose.external-db.yaml` | `compose.features.external-s3.yaml` |
| `dokploy/templates/external-prebuilt-local.json` | `compose.yaml` | `compose.external-prebuilt.yaml` | local MinIO |
| `dokploy/templates/external-prebuilt-external-s3.json` | `compose.yaml` | `compose.external-prebuilt.yaml` | `compose.features.external-s3.yaml` |

For `external-db` templates, the external Postgres provider must support `pg_net`, `pg_graphql` and `pg_cron`, and the bootstrap job is expected to run once before runtime services are considered ready. For `external-prebuilt` templates, the database must already contain the restored/configured Supabase DB-side state.

## Source-of-truth

Do not edit generated JSON templates by hand.

Generated templates are committed for import convenience, but the source of truth is the canonical base Compose file `compose.yaml`, Compose overlays, `files/`, `dokploy/config.toml` and `scripts/render-dokploy.sh`. If the repository later stops committing generated JSON, the same Makefile commands can still produce the import artifact locally.

The renderer:

- reads root `compose.yaml`;
- applies supported variant topology transforms;
- reads `dokploy/config.toml`;
- rewrites root `./files/...` bind paths to Dokploy `../files/...`;
- embeds `files/` content into Dokploy `[[config.mounts]]`;
- runs static validation.

## Validation

```sh
make validate
```

Validation checks that:

- generated Dokploy templates are valid JSON;
- embedded Compose YAML parses;
- required bind-mounted files exist.
