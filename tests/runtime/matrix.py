#!/usr/bin/env python3
"""Run all six topologies using disposable Docker projects and fresh local secrets.

The external DB fixture bypasses Supabase init SQL: only the image's extension
binaries are reused. external-db-existing reuses the database migrated by external-db-bootstrap.
No existing .env file, deployment, volume or remote endpoint is used.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / '.scratch' / 'runtime-matrix' / (time.strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:6])
RUN.mkdir(parents=True, mode=0o700)
os.umask(0o077)
ENV = {k: os.environ[k] for k in ('PATH', 'HOME', 'LANG', 'LC_ALL', 'DOCKER_HOST', 'DOCKER_CONTEXT') if k in os.environ}
ENV['COMPOSE_DISABLE_ENV_FILE'] = '1'
ENV['TMPDIR'] = str(ROOT / '.scratch' / 'tmp')
Path(ENV['TMPDIR']).mkdir(parents=True, exist_ok=True)
PREFIX = 'starter-matrix-' + uuid.uuid4().hex[:8]
RESULTS = []
STACKS = []


def run(args, log=None, env=None, input=None):
    result = subprocess.run(args, cwd=ROOT, env=env or ENV, text=True, input=input, capture_output=True)
    if log:
        (RUN / log).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'{args[0]} {args[1]} failed; inspect {RUN / log if log else RUN}')
    return result.stdout


def compose(project, envfile, files):
    cmd = ['docker', 'compose', '--project-directory', str(ROOT), '-p', project, '--env-file', str(envfile)]
    for file in files:
        cmd += ['-f', str(file)]
    return cmd


def save_env(path, values):
    # JSON string quoting preserves spaces and Compose's literal $ semantics
    # for these generated alphanumeric credentials and local test URLs.
    path.write_text('\n'.join(f'{k}={v}' for k, v in values.items()) + '\n')
    path.chmod(0o600)


with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0))
    PORT = sock.getsockname()[1]
seed = RUN / 'seed.env'
tlsdir = RUN / 'tls'
tlsdir.mkdir(mode=0o700)
run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(tlsdir / 'ca.key'), '-out', str(tlsdir / 'ca.crt'), '-days', '2', '-subj', '/CN=Starter matrix test CA', '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign'], 'tls-ca.log')
run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(tlsdir / 'server.key'), '-out', str(tlsdir / 'server.csr'), '-subj', '/CN=localhost'], 'tls-request.log')
(tlsdir / 'server.ext').write_text('subjectAltName=IP:127.0.0.1,DNS:localhost\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\nbasicConstraints=CA:FALSE\n')
run(['openssl', 'x509', '-req', '-in', str(tlsdir / 'server.csr'), '-CA', str(tlsdir / 'ca.crt'), '-CAkey', str(tlsdir / 'ca.key'), '-CAcreateserial', '-out', str(tlsdir / 'server.crt'), '-days', '2', '-sha256', '-extfile', str(tlsdir / 'server.ext')], 'tls-sign.log')
ENV.update(NODE_EXTRA_CA_CERTS=str(tlsdir / 'ca.crt'), TEST_TLS_INSECURE='false', NODE_TLS_REJECT_UNAUTHORIZED='1')
run(['sh', str(ROOT / 'scripts/generate-env.sh'), '--variant', 'internal-db'], 'generate.log', env={**ENV, 'OUTPUT_ENV': str(seed), 'SUPABASE_PUBLIC_URL': f'https://127.0.0.1:{PORT}'})
values = dict(line.split('=', 1) for line in seed.read_text().splitlines() if line and not line.startswith('#'))
password = values['SERVICE_PASSWORD_POSTGRES']

dbscript = RUN / 'database.sh'
dbscript.write_text('''#!/bin/bash
set -eu
mkdir -p /fixture-db
chown postgres:postgres /fixture-db
if [ ! -f /fixture-db/PG_VERSION ]; then
  printf '%s' "$POSTGRES_PASSWORD" > /run/fixture-password
  chown postgres:postgres /run/fixture-password
  chmod 600 /run/fixture-password
  gosu postgres initdb -D /fixture-db -U postgres --pwfile=/run/fixture-password --auth-host=scram-sha-256 --auth-local=trust
  rm /run/fixture-password
  printf 'host all all all scram-sha-256\\nhost replication all all scram-sha-256\\n' >> /fixture-db/pg_hba.conf
fi
exec gosu postgres postgres -D /fixture-db -c listen_addresses='*' -c wal_level=logical -c max_replication_slots=20 -c max_wal_senders=20 -c shared_preload_libraries=pg_cron,pg_net -c cron.database_name=postgres
''')
fixture = {
    'services': {
        'external-db-bootstrap': {
            'image': 'supabase/postgres:17.6.1.136',
            'entrypoint': ['/bin/bash', '/fixture-entrypoint.sh'],
            'environment': {'POSTGRES_PASSWORD': password},
            'volumes': ['fixture-db:/fixture-db', f'{dbscript}:/fixture-entrypoint.sh:ro'],
            'healthcheck': {'test': ['CMD', 'pg_isready', '-U', 'postgres', '-h', '127.0.0.1'], 'interval': '2s', 'timeout': '5s', 'retries': 30},
        },
        'external-s3': {
            'image': 'rustfs/rustfs:1.0.4',
            'environment': {'RUSTFS_ACCESS_KEY': values['MINIO_ROOT_USER'], 'RUSTFS_SECRET_KEY': values['MINIO_ROOT_PASSWORD'], 'RUSTFS_VOLUMES': '/data'},
            'volumes': ['fixture-s3:/data'],
            'security_opt': ['no-new-privileges:true'],
            'healthcheck': {'test': ['CMD', 'curl', '-fsS', 'http://127.0.0.1:9000/health'], 'interval': '2s', 'timeout': '5s', 'retries': 30},
        },
        'bucket-init': {
            'image': 'ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z',
            'environment': {'ACCESS': values['MINIO_ROOT_USER'], 'SECRET': values['MINIO_ROOT_PASSWORD'], 'BUCKET': values['STORAGE_S3_BUCKET']},
            'entrypoint': ['/bin/sh', '-ec', 'mc alias set fixture http://external-s3:9000 "$$ACCESS" "$$SECRET" && mc mb --ignore-existing "fixture/$$BUCKET"'],
            'depends_on': {'external-s3': {'condition': 'service_healthy'}},
        },
    },
    'volumes': {'fixture-db': {}, 'fixture-s3': {}},
}
fixturefile = RUN / 'fixtures.json'
fixturefile.write_text(json.dumps(fixture))
deps = compose(PREFIX + '-deps', seed, [fixturefile])
STACKS.append(deps)

try:
    print('Artifacts:', RUN, flush=True)
    run(deps + ['up', '-d', '--wait', '--wait-timeout', '180', 'external-db-bootstrap', 'external-s3'], 'fixtures-boot.log')
    run(deps + ['run', '--rm', '--no-deps', 'bucket-init'], 'fixtures-bucket.log')
    for variant in ('internal-db', 'external-db-bootstrap', 'external-db-existing'):
        project = PREFIX + '-' + variant
        for storage in ('minio', 'external-s3'):
            name = variant + '-' + storage
            envfile = RUN / (name + '.env')
            current = dict(values, CONTAINER_PREFIX=project)
            if variant != 'internal-db':
                current.update(POSTGRES_HOST='external-db-bootstrap', POSTGRES_HOSTNAME='external-db-bootstrap', POSTGRES_BOOTSTRAP_DB='postgres', POSTGRES_BOOTSTRAP_USER='postgres', POSTGRES_BOOTSTRAP_PASSWORD=password, POSTGRES_DB_OWNER='supabase_admin')
            if storage == 'external-s3':
                current.update(STORAGE_S3_ENDPOINT='http://external-s3:9000', STORAGE_S3_ACCESS_KEY_ID=values['MINIO_ROOT_USER'], STORAGE_S3_SECRET_ACCESS_KEY=values['MINIO_ROOT_PASSWORD'], STORAGE_S3_FORCE_PATH_STYLE='true')
            save_env(envfile, current)
            overlay = RUN / (name + '.json')
            overlay.write_text(json.dumps({'services': {'test-tls': {
                'image': 'python:3.12-slim',
                'command': ['python', '/tls-proxy.py'],
                'volumes': [f'{ROOT / "tests/runtime/tls-proxy.py"}:/tls-proxy.py:ro', f'{tlsdir}:/tls:ro'],
                'ports': [f'127.0.0.1:{PORT}:8443'],
                'depends_on': {'supabase-kong': {'condition': 'service_healthy'}},
                'healthcheck': {'test': ['CMD', 'python', '-c', "import socket,ssl; s=ssl.create_default_context(cafile='/tls/ca.crt').wrap_socket(socket.create_connection(('127.0.0.1',8443)),server_hostname='localhost'); s.close()"], 'interval': '2s', 'timeout': '5s', 'retries': 20},
            }}, 'networks': {'default': {'external': True, 'name': PREFIX + '-deps_default'}}}))
            files = [ROOT / 'compose.yaml', ROOT / f'compose.{variant}.yaml']
            if storage == 'external-s3':
                files.append(ROOT / 'compose.features.external-s3.yaml')
            files += [ROOT / 'compose.prod.yaml', overlay]
            cmd = compose(project, envfile, files)
            STACKS.append(cmd)
            print('Starting', name, flush=True)
            started = time.monotonic()
            run(cmd + ['up', '-d', '--wait', '--wait-timeout', '240'], name + '-boot.log')
            assert run(cmd + ['exec', '-T', 'supabase-storage', 'node', '-p', 'process.env.NODE_ENV'], name + '-storage-mode.log').strip() == 'production'
            if variant == 'internal-db' and storage == 'minio':
                untrusted = {k: v for k, v in ENV.items() if k != 'NODE_EXTRA_CA_CERTS'}
                run(['node', '-e', "require('node:https').get(process.argv[1],{rejectUnauthorized:true},()=>process.exit(1)).on('error',e=>process.exit(['UNABLE_TO_VERIFY_LEAF_SIGNATURE','SELF_SIGNED_CERT_IN_CHAIN','UNABLE_TO_GET_ISSUER_CERT_LOCALLY'].includes(e.code)?0:2))", current['SUPABASE_PUBLIC_URL']], 'tls-untrusted-ca-rejected.log', env=untrusted)
            if variant == 'external-db-existing':
                realtime_logs = run(cmd + ['logs', '--no-color', 'realtime-dev'], name + '-realtime-boot.log')
                assert 'Running migrations' not in realtime_logs, 'Prebuilt Realtime unexpectedly ran image-entrypoint migrations'
            run(['npm', '--prefix', str(ROOT / 'tests/runtime'), 'test'], name + '-tests.log', env={**ENV, 'TEST_ENV_FILE': str(envfile)})
            # Test both supported pooler connection modes with real SQL, not just /health.
            for port in ('5432', '6543'):
                output = run(deps + ['exec', '-T', '-e', 'PGPASSWORD=' + password, 'external-db-bootstrap', 'psql', '-h', 'supabase-supavisor', '-p', port, '-U', 'postgres.' + values['POOLER_TENANT_ID'], '-d', 'postgres', '-Atc', 'SELECT 1'], name + '-pool-' + port + '.log')
                assert output.strip() == '1', 'Pooler query failed'
            if variant == 'internal-db' and storage == 'minio':
                current['FUNCTIONS_VERIFY_JWT'] = 'true'
                save_env(envfile, current)
                run(cmd + ['up', '-d', '--no-deps', '--wait', '--wait-timeout', '60', 'supabase-edge-functions'], name + '-verified-edge-boot.log')
                run(['npm', '--prefix', str(ROOT / 'tests/runtime'), 'test', '--', 'specs/edge.test.ts'], name + '-verified-edge-tests.log', env={**ENV, 'TEST_ENV_FILE': str(envfile)})
                run(['python3', str(ROOT / 'tests/runtime/recovery.py'), 'capture', str(envfile), str(overlay)], 'recovery-capture.log')
            RESULTS.append({'scenario': name, 'status': 'pass', 'transport': 'https', 'tls_verification': True, 'storage_mode': 'production', 'seconds': round(time.monotonic() - started, 1)})
            (RUN / 'results.json').write_text(json.dumps(RESULTS, indent=2))
            print('PASS', name, flush=True)
            # Retain only the external fixture's database between external-db-bootstrap and prebuilt.
            run(cmd + ['down', '-v', '--remove-orphans'], name + '-cleanup.log')
    run(['python3', str(ROOT / 'tests/runtime/recovery.py'), 'restore', str(RUN / 'internal-db-minio.env')], 'recovery-restore.log')
finally:
    for index, cmd in enumerate(reversed(STACKS)):
        with (RUN / f'container-logs-{index}.log').open('w') as output:
            subprocess.run(cmd + ['logs', '--no-color', '--tail', '100'], cwd=ROOT, env=ENV, text=True, stdout=output, stderr=subprocess.STDOUT)
        subprocess.run(cmd + ['down', '-v', '--remove-orphans'], cwd=ROOT, env=ENV, text=True, stdout=(RUN / f'cleanup-{index}.log').open('w'), stderr=subprocess.STDOUT)
    print('Disposable projects removed; results and private logs:', RUN, flush=True)
