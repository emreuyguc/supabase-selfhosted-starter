#!/usr/bin/env sh
set -eu
umask 077

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_ENV="${OUTPUT_ENV:-$ROOT_DIR/.env}"
FORCE="${FORCE:-0}"
VARIANT="${VARIANT:-internal-db}"
STORAGE="${STORAGE:-minio}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --variant)
      if [ "$#" -lt 2 ]; then
        echo "--variant requires a value" >&2
        exit 1
      fi
      VARIANT="$2"
      shift 2
      ;;
    --variant=*)
      VARIANT="${1#--variant=}"
      shift
      ;;
    --storage)
      if [ "$#" -lt 2 ]; then
        echo "--storage requires a value" >&2
        exit 1
      fi
      STORAGE="$2"
      shift 2
      ;;
    --storage=*)
      STORAGE="${1#--storage=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$VARIANT" in
  full) VARIANT=internal-db ;;
  external-db) VARIANT=external-db-bootstrap ;;
  external-prebuilt) VARIANT=external-db-existing ;;
  internal-db|external-db-bootstrap|external-db-existing) ;;
  *)
    echo "Unsupported variant: $VARIANT" >&2
    echo "Supported variants: internal-db, external-db-bootstrap, external-db-existing" >&2
    exit 1
    ;;
esac

case "$STORAGE" in
  local) STORAGE=minio ;;
  minio|external-s3) ;;
  *)
    echo "Unsupported storage: $STORAGE" >&2
    echo "Supported storage: minio, external-s3" >&2
    exit 1
    ;;
esac

if [ -e "$OUTPUT_ENV" ] && [ "$FORCE" != "1" ]; then
  echo "$OUTPUT_ENV already exists. Set FORCE=1 to overwrite." >&2
  exit 1
fi

python3 - "$OUTPUT_ENV" "$VARIANT" "$STORAGE" <<'PY'
import base64
import hashlib
import hmac
import json
import os
import secrets
import string
import sys
import time
from pathlib import Path

out = Path(sys.argv[1])
variant = sys.argv[2]
storage_variant = sys.argv[3]
alphabet = string.ascii_lowercase + string.digits


def token(length: int) -> str:
    return "".join(secrets.choice(alphabet) for _ in range(length))


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def jwt(role: str, secret: str) -> str:
    now = int(time.time())
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "role": role,
        "iss": "supabase",
        "iat": now,
        "exp": 1893456000,
    }
    signing_input = ".".join(
        [
            b64url(json.dumps(header, separators=(",", ":")).encode()),
            b64url(json.dumps(payload, separators=(",", ":")).encode()),
        ]
    )
    sig = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()
    return f"{signing_input}.{b64url(sig)}"


def required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"{name} is required for the {variant} variant")
    return value


public_url = os.environ.get("SUPABASE_PUBLIC_URL", "http://localhost:8000").rstrip("/")
api_external_url = os.environ.get("API_EXTERNAL_URL", f"{public_url}/auth/v1").rstrip("/")
site_url = os.environ.get("SITE_URL", "http://localhost:3000").rstrip("/")
container_prefix = os.environ.get("CONTAINER_PREFIX", "supabase")
dashboard_user = os.environ.get("DASHBOARD_USERNAME", "supabase")
minio_user = os.environ.get("MINIO_ROOT_USER", "supabase")
bucket = os.environ.get("STORAGE_S3_BUCKET", "supabase-storage")
storage_tenant = os.environ.get("STORAGE_TENANT_ID", "stub")
storage_s3_region = os.environ.get("STORAGE_S3_REGION", "us-east-1")

if variant == "internal-db":
    postgres_password = token(40)
    postgres_host = os.environ.get("POSTGRES_HOST", "supabase-db")
    postgres_hostname = os.environ.get("POSTGRES_HOSTNAME", postgres_host)
else:
    postgres_password = os.environ.get("SERVICE_PASSWORD_POSTGRES") or os.environ.get("POSTGRES_PASSWORD")
    if not postgres_password:
        raise SystemExit(f"SERVICE_PASSWORD_POSTGRES or POSTGRES_PASSWORD is required for the {variant} variant")
    postgres_host = os.environ.get("POSTGRES_HOST") or required_env("POSTGRES_HOSTNAME")
    postgres_hostname = os.environ.get("POSTGRES_HOSTNAME", postgres_host)

postgres_db = os.environ.get("POSTGRES_DB", "postgres")
postgres_port = os.environ.get("POSTGRES_PORT", "5432")
postgres_db_owner = os.environ.get("POSTGRES_DB_OWNER", "supabase_admin")
postgres_bootstrap_db = os.environ.get("POSTGRES_BOOTSTRAP_DB", "postgres")
postgres_bootstrap_user = os.environ.get("POSTGRES_BOOTSTRAP_USER", "postgres")
postgres_bootstrap_password = os.environ.get("POSTGRES_BOOTSTRAP_PASSWORD")
if variant == "external-db-bootstrap" and not postgres_bootstrap_password:
    raise SystemExit("POSTGRES_BOOTSTRAP_PASSWORD is required for the external-db-bootstrap variant")

if storage_variant == "external-s3":
    external_s3_endpoint = required_env("STORAGE_S3_ENDPOINT")
    external_s3_access_key = required_env("STORAGE_S3_ACCESS_KEY_ID")
    external_s3_secret_key = required_env("STORAGE_S3_SECRET_ACCESS_KEY")
    external_s3_bucket = required_env("STORAGE_S3_BUCKET")
    external_s3_region = storage_s3_region
    external_s3_force_path_style = os.environ.get("STORAGE_S3_FORCE_PATH_STYLE", "true")
else:
    external_s3_endpoint = ""
    external_s3_access_key = ""
    external_s3_secret_key = ""
    external_s3_bucket = bucket
    external_s3_region = storage_s3_region
    external_s3_force_path_style = "true"
def existing(name: str, alias: str = "") -> str:
    value = os.environ.get(name) or (os.environ.get(alias) if alias else None)
    if not value:
        raise SystemExit(f"{name} is required for external-db-existing; preserve the restored deployment's credentials")
    return value


jwt_secret = existing("JWT_SECRET", "SERVICE_PASSWORD_JWT") if variant == "external-db-existing" else token(48)
anon_key = existing("ANON_KEY", "SERVICE_SUPABASEANON_KEY") if variant == "external-db-existing" else jwt("anon", jwt_secret)
service_role_key = existing("SERVICE_ROLE_KEY", "SERVICE_SUPABASESERVICE_KEY") if variant == "external-db-existing" else jwt("service_role", jwt_secret)
dashboard_password = token(40)
logflare_public = token(32)
logflare_private = token(32)
secret_key_base = existing("SECRET_KEY_BASE", "SERVICE_PASSWORD_SUPAVISORSECRET") if variant == "external-db-existing" else token(64)
vault_enc_key = existing("VAULT_ENC_KEY", "SERVICE_PASSWORD_VAULTENC") if variant == "external-db-existing" else token(32)
pg_meta_crypto_key = existing("PG_META_CRYPTO_KEY", "SERVICE_PASSWORD_PGMETACRYPTO") if variant == "external-db-existing" else token(32)
realtime_db_enc_key = existing("REALTIME_DB_ENC_KEY") if variant == "external-db-existing" else token(16)
s3_access_key = existing("S3_PROTOCOL_ACCESS_KEY_ID") if variant == "external-db-existing" else token(32)
s3_secret_key = existing("S3_PROTOCOL_ACCESS_KEY_SECRET") if variant == "external-db-existing" else token(64)
minio_password = existing("MINIO_ROOT_PASSWORD") if variant == "external-db-existing" and storage_variant == "minio" else token(40)
publishable_key = existing("SUPABASE_PUBLISHABLE_KEY") if variant == "external-db-existing" else "sb_publishable_" + token(48)
secret_key = existing("SUPABASE_SECRET_KEY") if variant == "external-db-existing" else "sb_secret_" + token(72)
pooler_tenant = existing("POOLER_TENANT_ID") if variant == "external-db-existing" else token(12)

postgres_values = [
    ("POSTGRES_PASSWORD", postgres_password),
    ("SERVICE_PASSWORD_POSTGRES", postgres_password),
    ("POSTGRES_HOST", postgres_host),
    ("POSTGRES_HOSTNAME", postgres_hostname),
    ("POSTGRES_DB", postgres_db),
    ("POSTGRES_PORT", postgres_port),
]
if variant == "external-db-bootstrap":
    postgres_values.extend(
        [
            ("POSTGRES_DB_OWNER", postgres_db_owner),
            ("POSTGRES_BOOTSTRAP_DB", postgres_bootstrap_db),
            ("POSTGRES_BOOTSTRAP_USER", postgres_bootstrap_user),
            ("POSTGRES_BOOTSTRAP_PASSWORD", postgres_bootstrap_password or ""),
        ]
    )
postgres_values.extend(
    [
        ("POOLER_DEFAULT_POOL_SIZE", "20"),
        ("POOLER_MAX_CLIENT_CONN", "100"),
        ("POOLER_TENANT_ID", pooler_tenant),
        ("POOLER_POOL_MODE", "transaction"),
        ("POOLER_DB_POOL_SIZE", "5"),
    ]
)

storage_values = [
    ("S3_PROTOCOL_ACCESS_KEY_ID", s3_access_key),
    ("S3_PROTOCOL_ACCESS_KEY_SECRET", s3_secret_key),
]
storage_group_title = "Storage and external S3"
if storage_variant == "minio":
    storage_group_title = "Storage and MinIO"
    storage_values.extend(
        [
            ("MINIO_ROOT_USER", minio_user),
            ("MINIO_ROOT_PASSWORD", minio_password),
        ]
    )
storage_values.extend(
    [
        ("IMGPROXY_ENABLE_WEBP_DETECTION", "true"),
        ("IMGPROXY_AUTO_WEBP", "true"),
        ("STORAGE_S3_BUCKET", external_s3_bucket),
        ("STORAGE_S3_REGION", external_s3_region),
        ("STORAGE_TENANT_ID", storage_tenant),
    ]
)
if storage_variant == "external-s3":
    storage_values.extend(
        [
            ("STORAGE_S3_ENDPOINT", external_s3_endpoint),
            ("STORAGE_S3_ACCESS_KEY_ID", external_s3_access_key),
            ("STORAGE_S3_SECRET_ACCESS_KEY", external_s3_secret_key),
            ("STORAGE_S3_FORCE_PATH_STYLE", external_s3_force_path_style),
        ]
    )

groups = [
    (
        "Core public URLs",
        [
            ("CONTAINER_PREFIX", container_prefix),
            ("SUPABASE_PUBLIC_URL", public_url),
            ("API_EXTERNAL_URL", api_external_url),
            ("SITE_URL", site_url),
            ("ADDITIONAL_REDIRECT_URLS", os.environ.get("ADDITIONAL_REDIRECT_URLS", f"{public_url}/*,{site_url}/*")),
        ],
    ),
    (
        "Postgres and pooling",
        postgres_values,
    ),
    (
        "JWT and API keys",
        [
            ("JWT_SECRET", jwt_secret),
            ("SERVICE_PASSWORD_JWT", jwt_secret),
            ("ANON_KEY", anon_key),
            ("SERVICE_SUPABASEANON_KEY", anon_key),
            ("SERVICE_ROLE_KEY", service_role_key),
            ("SERVICE_SUPABASESERVICE_KEY", service_role_key),
            ("SUPABASE_PUBLISHABLE_KEY", publishable_key),
            ("SUPABASE_SECRET_KEY", secret_key),
            ("JWT_EXPIRY", "3600"),
        ],
    ),
    (
        "Dashboard and Studio",
        [
            ("DASHBOARD_USERNAME", dashboard_user),
            ("SERVICE_USER_ADMIN", dashboard_user),
            ("DASHBOARD_PASSWORD", dashboard_password),
            ("SERVICE_PASSWORD_ADMIN", dashboard_password),
            ("STUDIO_DEFAULT_ORGANIZATION", "Default Organization"),
            ("STUDIO_DEFAULT_PROJECT", "Default Project"),
            ("OPENAI_API_KEY", ""),
        ],
    ),
    (
        "Analytics and logging",
        [
            ("LOGFLARE_PUBLIC_ACCESS_TOKEN", logflare_public),
            ("LOGFLARE_PRIVATE_ACCESS_TOKEN", logflare_private),
            ("SERVICE_PASSWORD_LOGFLARE", logflare_public),
            ("SERVICE_PASSWORD_LOGFLAREPRIVATE", logflare_private),
            ("DOCKER_SOCKET_LOCATION", "/var/run/docker.sock"),
        ],
    ),
    (
        "Internal encryption secrets",
        [
            ("SECRET_KEY_BASE", secret_key_base),
            ("VAULT_ENC_KEY", vault_enc_key),
            ("PG_META_CRYPTO_KEY", pg_meta_crypto_key),
            ("SERVICE_PASSWORD_PGMETACRYPTO", pg_meta_crypto_key),
            ("REALTIME_DB_ENC_KEY", realtime_db_enc_key),
            ("SERVICE_PASSWORD_SUPAVISORSECRET", secret_key_base),
            ("SERVICE_PASSWORD_VAULTENC", vault_enc_key),
        ],
    ),
    (
        storage_group_title,
        storage_values,
    ),
    (
        "PostgREST",
        [
            ("PGRST_DB_SCHEMAS", "public,graphql_public"),
            ("PGRST_DB_MAX_ROWS", "1000"),
            ("PGRST_DB_EXTRA_SEARCH_PATH", "public"),
        ],
    ),
    (
        "Auth signup and mail",
        [
            ("DISABLE_SIGNUP", "true"),
            ("ENABLE_EMAIL_SIGNUP", "false"),
            ("ENABLE_EMAIL_AUTOCONFIRM", "false"),
            ("ENABLE_ANONYMOUS_USERS", "false"),
            ("ENABLE_PHONE_SIGNUP", "false"),
            ("ENABLE_PHONE_AUTOCONFIRM", "false"),
            ("MAILER_URLPATHS_CONFIRMATION", "/auth/v1/verify"),
            ("MAILER_URLPATHS_INVITE", "/auth/v1/verify"),
            ("MAILER_URLPATHS_RECOVERY", "/auth/v1/verify"),
            ("MAILER_URLPATHS_EMAIL_CHANGE", "/auth/v1/verify"),
            ("SMTP_ADMIN_EMAIL", "admin@example.com"),
            ("SMTP_HOST", "supabase-mail"),
            ("SMTP_PORT", "2500"),
            ("SMTP_USER", "fake_mail_user"),
            ("SMTP_PASS", "fake_mail_password"),
            ("SMTP_SENDER_NAME", "fake_sender"),
            ("MAILER_TEMPLATES_INVITE", ""),
            ("MAILER_TEMPLATES_CONFIRMATION", ""),
            ("MAILER_TEMPLATES_RECOVERY", ""),
            ("MAILER_TEMPLATES_MAGIC_LINK", ""),
            ("MAILER_TEMPLATES_EMAIL_CHANGE", ""),
            ("MAILER_SUBJECTS_INVITE", "You have been invited"),
            ("MAILER_SUBJECTS_CONFIRMATION", "Confirm your signup"),
            ("MAILER_SUBJECTS_RECOVERY", "Reset your password"),
            ("MAILER_SUBJECTS_MAGIC_LINK", "Your magic link"),
            ("MAILER_SUBJECTS_EMAIL_CHANGE", "Confirm email change"),
        ],
    ),
    (
        "Edge Functions",
        [
            ("FUNCTIONS_VERIFY_JWT", "false"),
            ("SUPABASE_JWKS", os.environ.get("SUPABASE_JWKS", "")),
        ],
    ),
    (
        "Kong tuning",
        [
            ("KONG_STORAGE_CONNECT_TIMEOUT", "60000"),
            ("KONG_STORAGE_WRITE_TIMEOUT", "3600000"),
            ("KONG_STORAGE_READ_TIMEOUT", "3600000"),
            ("KONG_STORAGE_REQUEST_BUFFERING", "false"),
            ("KONG_STORAGE_RESPONSE_BUFFERING", "false"),
        ],
    ),
]

lines = [
    "# Generated Supabase environment.",
    f"# Variant: {variant}",
    f"# Storage: {storage_variant}",
    "# Do not commit this file.",
    "",
]
for title, values in groups:
    lines.append(f"# {title}")
    for key, value in values:
        lines.append(f"{key}={value}")
    lines.append("")

out.write_text("\n".join(lines).rstrip() + "\n")
out.chmod(0o600)
print(f"Wrote {out} for variant {variant} with {storage_variant} storage")
PY
