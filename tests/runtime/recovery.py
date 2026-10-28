#!/usr/bin/env python3
"""Capture a quiesced matrix deployment and prove logical/object recovery."""
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
os.umask(0o077)
action = sys.argv[1]
source_env = Path(sys.argv[2]).resolve()
source = dict(line.split('=', 1) for line in source_env.read_text().splitlines() if line and not line.startswith('#'))
case = source_env.parent / 'recovery'
case.mkdir(exist_ok=True, mode=0o700)
ENV = {k: os.environ[k] for k in ('PATH', 'HOME', 'LANG', 'DOCKER_HOST', 'DOCKER_CONTEXT') if k in os.environ}
ENV.update(COMPOSE_DISABLE_ENV_FILE='1', NODE_EXTRA_CA_CERTS=str(source_env.parent / 'tls/ca.crt'), TEST_TLS_INSECURE='false', NODE_TLS_REJECT_UNAUTHORIZED='1')


def run(args, label, env=None, input=None, ok=True):
    result = subprocess.run(args, cwd=ROOT, env=env or ENV, input=input, text=True, capture_output=True)
    (case / (label + '.log')).write_text(result.stdout + result.stderr)
    if (result.returncode == 0) != ok:
        raise RuntimeError(f'Recovery check failed: {label}; see private log under {case}')
    return result.stdout.strip()


def compose(project, envfile, files):
    result = ['docker', 'compose', '--project-directory', str(ROOT), '-p', project, '--env-file', str(envfile)]
    for file in files:
        result += ['-f', str(file)]
    return result


def api(values, path, method='GET', payload=None, body=None):
    headers = {'apikey': values['SERVICE_SUPABASESERVICE_KEY'], 'Authorization': 'Bearer ' + values['SERVICE_SUPABASESERVICE_KEY']}
    if payload is not None:
        body = json.dumps(payload).encode()
        headers['Content-Type'] = 'application/json'
    elif body is not None:
        headers['Content-Type'] = 'text/plain'
    request = urllib.request.Request(values['SUPABASE_PUBLIC_URL'] + path, headers=headers, method=method, data=body)
    context = ssl.create_default_context(cafile=ENV['NODE_EXTRA_CA_CERTS'])
    with urllib.request.urlopen(request, context=context, timeout=30) as response:
        return response.read()


if action == 'capture':
    cmd = compose(source['CONTAINER_PREFIX'], source_env, [ROOT / 'compose.yaml', ROOT / 'compose.internal-db.yaml', ROOT / 'compose.prod.yaml', Path(sys.argv[3])])
    marker = uuid.uuid4().hex
    bucket = 'recovery-' + marker[:16]
    email = 'recovery-' + marker + '@example.test'
    user = json.loads(api(source, '/auth/v1/admin/users', 'POST', {'email': email, 'password': 'Recovery-only-password-123!', 'email_confirm': True}))
    api(source, '/storage/v1/bucket', 'POST', {'id': bucket, 'name': bucket, 'public': False})
    api(source, f'/storage/v1/object/{bucket}/proof.txt', 'POST', body=marker.encode())
    run(cmd + ['exec', '-T', 'supabase-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', f"CREATE ROLE recovery_reader NOLOGIN; CREATE TABLE public.recovery_marker(id int PRIMARY KEY, value text); INSERT INTO public.recovery_marker VALUES (1,'{marker}'); ALTER TABLE public.recovery_marker ENABLE ROW LEVEL SECURITY; GRANT SELECT ON public.recovery_marker TO recovery_reader, service_role; CREATE POLICY recovery_read ON public.recovery_marker FOR SELECT TO recovery_reader USING(id=1); SELECT vault.create_secret('{marker}', 'recovery-secret');"], 'source-markers')
    run(cmd + ['exec', '-T', 'supabase-db', 'psql', '-U', 'supabase_admin', '-d', '_supabase', '-v', 'ON_ERROR_STOP=1', '-c', f"CREATE TABLE public.recovery_marker(value text); INSERT INTO public.recovery_marker VALUES ('{marker}');"], 'source-internal-marker')
    names = run(cmd + ['config', '--services'], 'source-services').splitlines()
    run(cmd + ['stop', *[name for name in names if name != 'supabase-db']], 'source-quiesce')
    backup_env = {**ENV, 'ENV_FILE': str(source_env), 'BACKUP_DIR': str(case)}
    sql = run(['sh', str(ROOT / 'scripts/backup-postgres.sh')], 'source-sql-backup', env=backup_env).removeprefix('Wrote ')
    objects = run(['sh', str(ROOT / 'scripts/backup-minio.sh')], 'source-object-backup', env=backup_env).removeprefix('Wrote ')
    cid = run(cmd + ['ps', '-q', 'supabase-db'], 'source-db-id')
    config = case / 'postgres-config.tar'
    with config.open('wb') as output:
        subprocess.run(['docker', 'cp', cid + ':/etc/postgresql-custom/.', '-'], stdout=output, stderr=subprocess.PIPE, check=True)
    (case / 'snapshot.json').write_text(json.dumps({'marker': marker, 'bucket': bucket, 'user_id': user['id'], 'email': email, 'sql': sql, 'objects': objects, 'config': str(config)}, indent=2))
    print('PASS captured quiesced full deployment: SQL roles/databases, Auth user, object, Vault secret and config')
elif action == 'restore':
    (case / 'results.json').unlink(missing_ok=True)
    proof = json.loads((case / 'snapshot.json').read_text())
    target = 'starter-recovery-' + uuid.uuid4().hex[:8]
    # Enable the email provider only in this disposable recovery target so the
    # saved password can be exercised. Global public signup stays disabled.
    values = dict(source, CONTAINER_PREFIX=target, ENABLE_EMAIL_SIGNUP='true')
    envfile = case / 'restored.env'
    envfile.write_text('\n'.join(k + '=' + v for k, v in values.items()) + '\n')
    init = case / 'restore-target.sh'
    init.write_text('''set -eu
mkdir -p /fixture-db /etc/postgresql-custom
chown postgres:postgres /fixture-db /etc/postgresql-custom
if [ ! -f /fixture-db/PG_VERSION ]; then
 printf '%s' "$POSTGRES_PASSWORD" > /run/restore-password
 chown postgres:postgres /run/restore-password
 chmod 600 /run/restore-password
 gosu postgres initdb -D /fixture-db -U supabase_admin --pwfile=/run/restore-password --auth-local=trust --auth-host=scram-sha-256 --locale-provider=icu --encoding=UTF-8 --icu-locale=en_US.UTF-8
 rm /run/restore-password
 printf 'host all all all scram-sha-256\\n' >> /fixture-db/pg_hba.conf
fi
exec gosu postgres postgres -D /fixture-db -c config_file=/etc/postgresql/postgresql.conf -c data_directory=/fixture-db -c hba_file=/fixture-db/pg_hba.conf -c ident_file=/fixture-db/pg_ident.conf -c listen_addresses='*'
''')
    # A fresh cluster is deliberate: the normal Supabase entrypoint would
    # pre-create roles and schemas that a whole-cluster SQL restore must supply.
    fixture = {'services': {
        'supabase-db': {'image': 'supabase/postgres:17.6.1.136', 'entrypoint': ['/bin/sh', '/restore-target.sh'], 'environment': {'POSTGRES_PASSWORD': values['POSTGRES_PASSWORD'], 'PGDATABASE': 'postgres'}, 'volumes': [f'{init}:/restore-target.sh:ro', 'supabase-db-data:/fixture-db', 'supabase-db-config:/etc/postgresql-custom'], 'healthcheck': {'test': ['CMD', 'pg_isready', '-U', 'supabase_admin', '-h', '127.0.0.1'], 'interval': '2s', 'timeout': '5s', 'retries': 30}},
        'supabase-minio': {'image': 'ghcr.io/coollabsio/minio:RELEASE.2025-10-15T17-29-55Z', 'command': ['server', '/data'], 'environment': {'MINIO_ROOT_USER': values['MINIO_ROOT_USER'], 'MINIO_ROOT_PASSWORD': values['MINIO_ROOT_PASSWORD']}, 'volumes': ['supabase-minio-data:/data']},
    }, 'volumes': {'supabase-db-data': {}, 'supabase-db-config': {}, 'supabase-minio-data': {}}}
    fixturefile = case / 'restore-fixture.json'
    fixturefile.write_text(json.dumps(fixture))
    cmd = compose(target, envfile, [fixturefile])
    overlay = json.loads((source_env.parent / 'internal-db-minio.json').read_text())
    overlay['networks'] = {'default': {'external': True, 'name': target + '_default'}}
    overlayfile = case / 'restored-ingress.json'
    overlayfile.write_text(json.dumps(overlay))
    runtime = compose(target, envfile, [ROOT / 'compose.yaml', ROOT / 'compose.external-db-existing.yaml', ROOT / 'compose.prod.yaml', overlayfile])
    try:
        run(cmd + ['create'], 'target-create')
        cid = run(cmd + ['ps', '-aq', 'supabase-db'], 'target-db-id')
        with Path(proof['config']).open('rb') as source_config:
            subprocess.run(['docker', 'cp', '-', cid + ':/etc/postgresql-custom'], stdin=source_config, stderr=subprocess.PIPE, check=True)
        restore_env = {**ENV, 'ENV_FILE': str(envfile), 'CONFIRM_RESTORE': '1'}
        run(['sh', str(ROOT / 'scripts/restore-minio.sh'), proof['objects']], 'target-object-restore', env=restore_env)
        run(cmd + ['up', '-d', '--wait', '--wait-timeout', '90', 'supabase-db'], 'target-db-start')
        run(['sh', str(ROOT / 'scripts/restore-postgres.sh'), proof['sql']], 'target-sql-restore', env=restore_env)
        run(['sh', str(ROOT / 'scripts/restore-postgres.sh'), proof['sql']], 'target-nonempty-restore-rejected', env=restore_env, ok=False)
        assert 'Restore requires an empty cluster' in (case / 'target-nonempty-restore-rejected.log').read_text()
        for database in ('postgres', '_supabase'):
            actual = run(cmd + ['exec', '-T', 'supabase-db', 'psql', '-U', 'supabase_admin', '-d', database, '-Atc', 'SELECT value FROM public.recovery_marker'], 'target-marker-' + database)
            assert actual == proof['marker']
        secret = run(cmd + ['exec', '-T', 'supabase-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-Atc', "SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='recovery-secret'"], 'target-vault')
        assert secret == proof['marker'], 'Restored Vault secret must decrypt with preserved config'
        rls = run(cmd + ['exec', '-T', 'supabase-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-Atc', 'SET ROLE recovery_reader; SELECT value FROM public.recovery_marker'], 'target-rls')
        assert rls.splitlines()[-1] == proof['marker']
        run(runtime + ['up', '-d', '--wait', '--wait-timeout', '240'], 'restored-runtime-start')
        actual_user = json.loads(api(values, '/auth/v1/admin/users/' + proof['user_id']))
        assert actual_user['email'] == proof['email']
        session = json.loads(api(values, '/auth/v1/token?grant_type=password', 'POST', {'email': proof['email'], 'password': 'Recovery-only-password-123!'}))
        assert session['user']['id'] == proof['user_id'] and session['access_token']
        assert api(values, f"/storage/v1/object/authenticated/{proof['bucket']}/proof.txt").decode() == proof['marker']
        for port in ('5432', '6543'):
            result = run(cmd + ['exec', '-T', '-e', 'PGPASSWORD=' + values['POSTGRES_PASSWORD'], 'supabase-db', 'psql', '-h', 'supabase-supavisor', '-p', port, '-U', 'postgres.' + values['POOLER_TENANT_ID'], '-d', 'postgres', '-Atc', 'SELECT 1'], 'restored-pooler-' + port)
            assert result == '1'
        run(['npm', '--prefix', str(ROOT / 'tests/runtime'), 'test'], 'restored-runtime-tests', env={**ENV, 'TEST_ENV_FILE': str(envfile)})
        (case / 'results.json').write_text(json.dumps({'status': 'pass', 'source': 'fully migrated internal-db/minio', 'target': 'fresh logical restore then external-db-existing/minio', 'checks': ['roles and RLS', 'application DB', '_supabase DB', 'decrypted Vault secret', 'Auth user and password login via HTTPS', 'Storage object via HTTPS', 'both pooler SQL modes', 'complete runtime suite', 'nonempty restore rejection']}, indent=2))
        print('PASS full SQL/object recovery, Vault decryption, Auth/Storage HTTPS and runtime suite on restored prebuilt stack')
    finally:
        for label, stack in [('runtime', runtime), ('fixture', cmd)]:
            result = subprocess.run(stack + ['logs', '--no-color', '--tail', '80'], cwd=ROOT, env=ENV, capture_output=True, text=True)
            (case / (label + '-container.log')).write_text(result.stdout + result.stderr)
            subprocess.run(stack + ['down', '-v', '--remove-orphans'], cwd=ROOT, env=ENV, capture_output=True)
else:
    raise SystemExit('Expected capture or restore')
