# Dokploy

This folder contains the Dokploy-specific source config and generated import artifacts.

## Files

| Path | Purpose |
|---|---|
| `config.toml` | Dokploy variables, domains, env mappings and platform metadata |
| `Makefile` | Dokploy-specific render and validation commands |
| `template.json` | Generated full-stack Dokploy import template kept for compatibility |
| `templates/full.json` | Generated full-stack variant import template |
| `templates/full-external-s3.json` | Generated full-stack variant with external S3 |
| `templates/external-db.json` | Generated external Postgres variant import template |
| `templates/external-db-external-s3.json` | Generated external Postgres variant with external S3 |
| `templates/external-prebuilt.json` | Generated external preconfigured database variant import template |
| `templates/external-prebuilt-external-s3.json` | Generated external preconfigured database variant with external S3 |

## Usage

Regenerate the Dokploy template after changing any of:

- `compose.yaml`;
- `files/`;
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
make -C dokploy render VARIANT=external-prebuilt STORAGE=local OUTPUT=dokploy/template.json
```

Then import the template matching the target topology:

```text
dokploy/template.json
dokploy/templates/full.json
dokploy/templates/full-external-s3.json
dokploy/templates/external-db.json
dokploy/templates/external-db-external-s3.json
dokploy/templates/external-prebuilt.json
dokploy/templates/external-prebuilt-external-s3.json
```

For `external-db` templates, the external Postgres provider must support `pg_net`, `pg_graphql` and `pg_cron`, and the bootstrap job is expected to run once before runtime services are considered ready. For `external-prebuilt` templates, the database must already contain the restored/configured Supabase DB-side state.

## Source-of-truth

Do not edit generated JSON templates by hand.

Generated templates are committed for import convenience, but the source of truth is `compose.yaml`, Compose overlays, `files/`, `dokploy/config.toml` and `scripts/render-dokploy.sh`. If the repository later stops committing generated JSON, the same Makefile commands can still produce the import artifact locally.

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
