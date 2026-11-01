#!/usr/bin/env python3
"""Reproduce Supabase session-hook delegation on a disposable external DB."""
from pathlib import Path
import secrets
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
NAME = 'starter-bootstrap-' + uuid.uuid4().hex[:10]
PASSWORD = secrets.token_hex(24)
IMAGE = 'supabase/postgres:17.6.1.136'


def docker(*args, input=None, check=True):
    return subprocess.run(['docker', *args], input=input, text=True,
                          capture_output=True, check=check)


def sql(query, check=True, native=False):
    opts = ['-e', 'PGOPTIONS=-c session_preload_libraries='] if native else []
    return docker('exec', *opts, NAME, 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
                  '-U', 'postgres', '-d', 'postgres', '-Atc', query, check=check)


# Match the separate Supabase-image server: postgres is the initdb superuser,
# while the configured supautils delegation role is not a superuser.
entrypoint = r'''
set -eu
mkdir /fixture-db
chown postgres:postgres /fixture-db
gosu postgres initdb -D /fixture-db -U postgres --auth=trust >/dev/null
exec gosu postgres postgres -D /fixture-db \
  -c listen_addresses=127.0.0.1 -c wal_level=logical \
  -c shared_preload_libraries=pg_cron,pg_net \
  -c cron.database_name=postgres \
  -c session_preload_libraries=supautils \
  -c supautils.privileged_extensions=pg_net,pg_graphql,pg_cron \
  -c supautils.privileged_extensions_superuser=supabase_admin \
  -c supautils.superuser=supabase_admin \
  -c supautils.extension_custom_scripts_path=/etc/postgresql-custom/extension-custom-scripts \
  -c supautils.privileged_extensions_custom_scripts_path=/etc/postgresql-custom/extension-custom-scripts
'''
try:
    docker('run', '-d', '--name', NAME, '--entrypoint', '/bin/bash',
           '-v', f'{ROOT / "files/volumes/db-bootstrap"}:/db-bootstrap:ro',
           IMAGE, '-ec', entrypoint)
    for _ in range(60):
        if sql('SELECT 1', check=False).returncode == 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError('Disposable database did not become ready')
    sql('CREATE ROLE supabase_admin LOGIN; CREATE SCHEMA extensions;', native=True)
    broken = sql('BEGIN; CREATE EXTENSION pg_net SCHEMA extensions; ROLLBACK;', check=False)
    assert broken.returncode != 0 and 'pg_read_file' in broken.stderr, broken.stderr
    print('PASS original pg_read_file failure reproduced', flush=True)

    def bootstrap(user='postgres'):
        env = {
            'POSTGRES_HOSTNAME': '127.0.0.1', 'POSTGRES_PORT': '5432',
            'POSTGRES_BOOTSTRAP_DB': 'postgres', 'POSTGRES_BOOTSTRAP_USER': user,
            'POSTGRES_BOOTSTRAP_PASSWORD': PASSWORD, 'POSTGRES_DB': 'postgres',
            'POSTGRES_DB_OWNER': 'supabase_admin', 'SERVICE_PASSWORD_POSTGRES': PASSWORD,
            'JWT_EXPIRY': '3600',
            # Existing client options must survive the bootstrap override.
            'PGOPTIONS': '-c statement_timeout=60000',
        }
        args = ['exec']
        for key, value in env.items():
            args += ['-e', f'{key}={value}']
        return docker(*args, NAME, 'sh', '/db-bootstrap/bootstrap-external-db.sh', check=False)

    for attempt in range(2):
        result = bootstrap()
        assert result.returncode == 0, result.stderr
        assert 'External DB bootstrap complete.' in result.stdout
    print('PASS complete bootstrap and idempotent rerun', flush=True)
    assert sql("SELECT count(*) FROM pg_extension WHERE extname IN ('pg_net','pg_graphql','pg_cron')").stdout.strip() == '3'
    assert sql('SHOW session_preload_libraries').stdout.strip() == 'supautils'
    assert sql("SELECT rolsuper FROM pg_roles WHERE rolname='supabase_admin'").stdout.strip() == 'f'
    rejected = bootstrap('supabase_admin')
    assert rejected.returncode != 0, rejected.stdout
    assert ('requires a PostgreSQL superuser' in rejected.stderr
            or 'permission denied to set parameter "session_preload_libraries"' in rejected.stderr), rejected.stderr
    assert 'Running external DB bootstrap:' not in rejected.stdout
    print('PASS runtime role unchanged, server preload unchanged, restricted bootstrap rejected', flush=True)
finally:
    docker('rm', '-f', '-v', NAME, check=False)
