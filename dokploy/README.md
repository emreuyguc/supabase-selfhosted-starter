# Dokploy

This folder contains the Dokploy-specific source config and generated import artifacts.

## Files

| Path | Purpose |
|---|---|
| `config.toml` | Dokploy variables, domains, env mappings and platform metadata |
| `Makefile` | Dokploy-specific render and validation commands |
| `templates/internal-db-minio.json` | Generated full-stack variant with local Postgres and local MinIO |
| `templates/internal-db-external-s3.json` | Generated full-stack variant with external S3 |
| `templates/external-db-bootstrap-minio.json` | Generated external Postgres variant with local MinIO |
| `templates/external-db-bootstrap-external-s3.json` | Generated external Postgres variant with external S3 |
| `templates/external-db-existing-minio.json` | Generated external preconfigured database variant with local MinIO |
| `templates/external-db-existing-external-s3.json` | Generated external preconfigured database variant with external S3 |

## Usage

Regenerate the Dokploy template after changing any of:

- base Compose: `compose.yaml`;
- variant overlays: `compose.internal-db.yaml`, `compose.external-db-bootstrap.yaml`, `compose.external-db-existing.yaml`;
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
make -C dokploy render-template VARIANT=external-db-bootstrap STORAGE=external-s3
```

Render to a custom file under `dokploy/`:

```sh
make -C dokploy render VARIANT=external-db-existing STORAGE=minio OUTPUT=dokploy/templates/external-db-existing-minio.json
```

Then import the template matching the target topology:

| Import file | Base Compose | Variant overlay | Storage overlay |
|---|---|---|---|
| `dokploy/templates/internal-db-minio.json` | `compose.yaml` | `compose.internal-db.yaml` | local MinIO |
| `dokploy/templates/internal-db-external-s3.json` | `compose.yaml` | `compose.internal-db.yaml` | `compose.features.external-s3.yaml` |
| `dokploy/templates/external-db-bootstrap-minio.json` | `compose.yaml` | `compose.external-db-bootstrap.yaml` | local MinIO |
| `dokploy/templates/external-db-bootstrap-external-s3.json` | `compose.yaml` | `compose.external-db-bootstrap.yaml` | `compose.features.external-s3.yaml` |
| `dokploy/templates/external-db-existing-minio.json` | `compose.yaml` | `compose.external-db-existing.yaml` | local MinIO |
| `dokploy/templates/external-db-existing-external-s3.json` | `compose.yaml` | `compose.external-db-existing.yaml` | `compose.features.external-s3.yaml` |

For `external-db-bootstrap` templates, the external Postgres provider must support `pg_net`, `pg_graphql` and `pg_cron`, and the bootstrap job is expected to run once before runtime services are considered ready. For `external-db-existing` templates, the database must already contain the restored/configured Supabase DB-side state.

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

## Updated deployment contract

Templates now include `compose.prod.yaml` restart and bounded-log policy. They
are generated from the actual canonical overlays using Docker Compose, rather
than a separate Python topology implementation. Inline file contents are escaped
TOML strings and validated byte-for-byte against `files/`.

For new production installations, prefer the external-S3 template. Local MinIO
is a compatibility option; its upstream project is archived. Read the
[upgrade guide](../docs/UPGRADE.md) for the snapshot and migration requirements.

After importing, configure a real domain and HTTPS in Dokploy. Set
`SUPABASE_PUBLIC_URL=https://<domain>`, `API_EXTERNAL_URL=https://<domain>/auth/v1`,
`SITE_URL` to the application frontend, and explicit redirect URLs. Generated
HTTP preview domains are not a production TLS setup. Do not regenerate keys
when upgrading an existing installation. `external-db-existing` imports must retain
the database's existing JWT/encryption keys and pooler tenant ID.
