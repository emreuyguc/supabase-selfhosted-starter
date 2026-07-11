# Dokploy

This folder contains the Dokploy-specific source config and generated import artifact.

## Files

| Path | Purpose |
|---|---|
| `config.toml` | Dokploy variables, domains, env mappings and platform metadata |
| `template.json` | Generated Dokploy import template |

## Usage

Regenerate the Dokploy template after changing any of:

- `compose.yaml`;
- `files/`;
- `dokploy/config.toml`;
- `scripts/render-dokploy.sh`.

Command:

```sh
make render-dokploy
```

Then import:

```text
dokploy/template.json
```

## Source-of-truth

Do not edit `template.json` by hand.

The renderer:

- reads root `compose.yaml`;
- reads `dokploy/config.toml`;
- rewrites root `./files/...` bind paths to Dokploy `../files/...`;
- embeds `files/` content into Dokploy `[[config.mounts]]`;
- runs static validation.

## Validation

```sh
make validate
```

Validation checks that:

- `template.json` is valid JSON;
- the embedded Compose YAML parses;
- required bind-mounted files exist.
