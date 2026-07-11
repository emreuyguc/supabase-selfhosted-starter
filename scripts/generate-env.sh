#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_ENV="${OUTPUT_ENV:-$ROOT_DIR/.env}"
FORCE="${FORCE:-0}"

if [ -e "$OUTPUT_ENV" ] && [ "$FORCE" != "1" ]; then
  echo "$OUTPUT_ENV already exists. Set FORCE=1 to overwrite." >&2
  exit 1
fi

python3 - "$OUTPUT_ENV" <<'PY'
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


public_url = os.environ.get("SUPABASE_PUBLIC_URL", "http://localhost:8000").rstrip("/")
container_prefix = os.environ.get("CONTAINER_PREFIX", "supabase")
dashboard_user = os.environ.get("DASHBOARD_USERNAME", "supabase")
minio_user = os.environ.get("MINIO_ROOT_USER", "supabase")
bucket = os.environ.get("GLOBAL_S3_BUCKET", "stub")
storage_tenant = os.environ.get("STORAGE_TENANT_ID", "stub")
region = os.environ.get("REGION", "stub")

postgres_password = token(40)
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
        [
            ("POSTGRES_PASSWORD", postgres_password),
            ("SERVICE_PASSWORD_POSTGRES", postgres_password),
            ("POSTGRES_HOST", "supabase-db"),
            ("POSTGRES_HOSTNAME", "supabase-db"),
            ("POSTGRES_DB", "postgres"),
            ("POSTGRES_PORT", "5432"),
            ("POOLER_DEFAULT_POOL_SIZE", "20"),
            ("POOLER_MAX_CLIENT_CONN", "100"),
            ("POOLER_TENANT_ID", pooler_tenant),
            ("POOLER_POOL_MODE", "transaction"),
            ("POOLER_DB_POOL_SIZE", "5"),
        ],
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
        "Storage and MinIO",
        [
            ("S3_PROTOCOL_ACCESS_KEY_ID", s3_access_key),
            ("S3_PROTOCOL_ACCESS_KEY_SECRET", s3_secret_key),
            ("MINIO_ROOT_USER", minio_user),
            ("MINIO_ROOT_PASSWORD", minio_password),
            ("SERVICE_USER_MINIO", minio_user),
            ("SERVICE_PASSWORD_MINIO", minio_password),
            ("IMGPROXY_ENABLE_WEBP_DETECTION", "true"),
            ("IMGPROXY_AUTO_WEBP", "true"),
            ("GLOBAL_S3_BUCKET", bucket),
            ("STORAGE_TENANT_ID", storage_tenant),
            ("REGION", region),
        ],
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
    "# Do not commit this file.",
    "",
]
for title, values in groups:
    lines.append(f"# {title}")
    for key, value in values:
        lines.append(f"{key}={value}")
    lines.append("")

out.write_text("\n".join(lines).rstrip() + "\n")
print(f"Wrote {out}")
PY
