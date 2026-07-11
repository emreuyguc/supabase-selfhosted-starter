#!/bin/sh
set -eu
/usr/bin/mc alias set supabase-minio http://supabase-minio:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
/usr/bin/mc mb --ignore-existing "supabase-minio/${GLOBAL_S3_BUCKET:-stub}"
