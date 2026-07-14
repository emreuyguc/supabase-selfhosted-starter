#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_ENV="${OUTPUT_ENV:-$ROOT_DIR/.env}"
FORCE="${FORCE:-0}"
VARIANT="${VARIANT:-full}"
STORAGE="${STORAGE:-local}"

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
  full|external-db|external-prebuilt) ;;
  *)
    echo "Unsupported variant: $VARIANT" >&2
    echo "Supported variants: full, external-db, external-prebuilt" >&2
    exit 1
    ;;
esac

case "$STORAGE" in
  local|external-s3) ;;
  *)
    echo "Unsupported storage: $STORAGE" >&2
    echo "Supported storage: local, external-s3" >&2
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
from urllib.parse import urlparse

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
container_prefix = os.environ.get("CONTAINER_PREFIX", "supabase")
dashboard_user = os.environ.get("DASHBOARD_USERNAME", "supabase")
minio_user = os.environ.get("MINIO_ROOT_USER", "supabase")
bucket = os.environ.get("GLOBAL_S3_BUCKET", "stub")
storage_tenant = os.environ.get("STORAGE_TENANT_ID", "stub")
region = os.environ.get("REGION", "stub")

if variant == "full":
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
if variant == "external-db" and not postgres_bootstrap_password:
    raise SystemExit("POSTGRES_BOOTSTRAP_PASSWORD is required for the external-db variant")

if storage_variant == "external-s3":
    external_s3_endpoint = required_env("STORAGE_S3_ENDPOINT")
    external_s3_access_key = required_env("STORAGE_S3_ACCESS_KEY_ID")
    external_s3_secret_key = required_env("STORAGE_S3_SECRET_ACCESS_KEY")
    external_s3_bucket = required_env("GLOBAL_S3_BUCKET")
    external_s3_region = os.environ.get("STORAGE_S3_REGION", os.environ.get("REGION", "us-east-1"))
    external_s3_force_path_style = os.environ.get("STORAGE_S3_FORCE_PATH_STYLE", "true")
    external_s3_protocol = os.environ.get("STORAGE_S3_PROTOCOL") or urlparse(external_s3_endpoint).scheme or "https"
else:
    external_s3_endpoint = ""
    external_s3_access_key = ""
    external_s3_secret_key = ""
    external_s3_bucket = bucket
    external_s3_region = region
    external_s3_force_path_style = "true"
    external_s3_protocol = "http"
jwt_secret = token(48)
anon_key = jwt("anon", jwt_secret)
service_role_key = jwt("service_role", jwt_secret)
dashboard_password = token(40)
logflare_public = token(32)
logflare_private = token(32)
secret_key_base = token(64)
vault_enc_key = token(32)
pg_meta_crypto_key = token(32)
realtime_db_enc_key = token(16)
s3_access_key = token(32)
s3_secret_key = token(64)
minio_password = token(40)
publishable_key = "sb_publishable_" + token(48)
secret_key = "sb_secret_" + token(72)
pooler_tenant = token(12)

postgres_values = [
    ("POSTGRES_PASSWORD", postgres_password),
    ("SERVICE_PASSWORD_POSTGRES", postgres_password),
    ("POSTGRES_HOST", postgres_host),
    ("POSTGRES_HOSTNAME", postgres_hostname),
    ("POSTGRES_DB", postgres_db),
    ("POSTGRES_PORT", postgres_port),
]
if variant == "external-db":
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
if storage_variant == "local":
    storage_group_title = "Storage and MinIO"
    storage_values.extend(
        [
            ("MINIO_ROOT_USER", minio_user),
            ("MINIO_ROOT_PASSWORD", minio_password),
            ("SERVICE_USER_MINIO", minio_user),
            ("SERVICE_PASSWORD_MINIO", minio_password),
        ]
    )
storage_values.extend(
    [
        ("IMGPROXY_ENABLE_WEBP_DETECTION", "true"),
        ("IMGPROXY_AUTO_WEBP", "true"),
        ("GLOBAL_S3_BUCKET", external_s3_bucket),
        ("STORAGE_TENANT_ID", storage_tenant),
        ("REGION", external_s3_region),
    ]
)
if storage_variant == "external-s3":
    storage_values.extend(
        [
            ("GLOBAL_S3_ENDPOINT", external_s3_endpoint),
            ("GLOBAL_S3_PROTOCOL", external_s3_protocol),
            ("GLOBAL_S3_FORCE_PATH_STYLE", external_s3_force_path_style),
            ("STORAGE_S3_ENDPOINT", external_s3_endpoint),
            ("STORAGE_S3_PROTOCOL", external_s3_protocol),
            ("STORAGE_S3_ACCESS_KEY_ID", external_s3_access_key),
            ("STORAGE_S3_SECRET_ACCESS_KEY", external_s3_secret_key),
            ("STORAGE_S3_REGION", external_s3_region),
            ("STORAGE_S3_FORCE_PATH_STYLE", external_s3_force_path_style),
        ]
    )

groups = [
    (
        "Core public URLs",
        [
            ("CONTAINER_PREFIX", container_prefix),
            ("SUPABASE_PUBLIC_URL", public_url),
            ("ADDITIONAL_REDIRECT_URLS", f"{public_url}/*,http://localhost:3000/*"),
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
            ("LOGFLARE_API_KEY", logflare_public),
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
            ("PGRST_DB_SCHEMAS", "public,storage,graphql_public"),
            ("PGRST_DB_MAX_ROWS", "1000"),
            ("PGRST_DB_EXTRA_SEARCH_PATH", "public"),
        ],
    ),
    (
        "Auth signup and mail",
        [
            ("DISABLE_SIGNUP", "false"),
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
        ],
    ),
    (
        "Kong tuning",
        [
            ("KONG_STORAGE_CONNECT_TIMEOUT", "60"),
            ("KONG_STORAGE_WRITE_TIMEOUT", "3600"),
            ("KONG_STORAGE_READ_TIMEOUT", "3600"),
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
print(f"Wrote {out} for variant {variant} with {storage_variant} storage")
PY
