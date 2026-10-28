#!/usr/bin/env python3
"""Archive or restore the stopped local MinIO named volume, never a live tree."""
import gzip
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]
os.umask(0o077)
envfile = Path(os.environ.get('ENV_FILE', ROOT / '.env')).resolve()
if not envfile.is_file():
    raise SystemExit('Missing ENV_FILE')
if os.environ.get('STORAGE', 'minio') not in ('minio', 'local'):
    raise SystemExit('Use your external S3 provider backup procedure')


def command(args):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise SystemExit('Docker operation failed: ' + result.stderr.strip())
    return result.stdout.strip()


compose = ['docker', 'compose', '--env-file', str(envfile), '-f', str(ROOT / 'compose.yaml')]
container = command(compose + ['ps', '--all', '--quiet', 'supabase-minio'])
if not container or '\n' in container:
    raise SystemExit('Create exactly one local MinIO container first; leave it stopped for restore')
info = json.loads(command(['docker', 'inspect', container]))[0]
mount = next(m for m in info['Mounts'] if m['Destination'] == '/data')
if mount['Type'] != 'volume':
    raise SystemExit('Only the canonical local MinIO named volume is supported')
volume = mount['Name']


def stopped():
    if command(['docker', 'ps', '-q', '--filter', 'volume=' + volume]):
        raise SystemExit('Stop all containers using the MinIO volume before backup/restore')


stopped()
action = sys.argv[1]
if action == 'backup':
    directory = Path(os.environ.get('BACKUP_DIR', ROOT / 'backups')).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / ('minio-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '.tar.gz')
    created = False
    try:
        with target.open('xb') as raw:
            created = True
            with gzip.GzipFile(fileobj=raw, mode='wb') as zipped:
                process = subprocess.Popen(['docker', 'cp', container + ':/data/.', '-'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                shutil.copyfileobj(process.stdout, zipped)
                error = process.stderr.read()
                if process.wait():
                    raise RuntimeError(error.decode())
        stopped()
        print('Wrote', target)
    except BaseException:
        if created:
            target.unlink(missing_ok=True)
        raise
elif action == 'restore':
    if os.environ.get('CONFIRM_RESTORE') != '1':
        raise SystemExit('Refusing restore without CONFIRM_RESTORE=1')
    source = Path(sys.argv[2] if len(sys.argv) > 2 else os.environ.get('BACKUP_FILE', ''))
    if not source.is_file():
        raise SystemExit('Supply a MinIO tar.gz backup')
    with tarfile.open(source, 'r|gz') as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
                raise SystemExit('Unsafe archive entry; restore rejected')
    check = subprocess.run(['docker', 'run', '--rm', '--user', '0', '--volumes-from', container + ':ro', '--entrypoint', '/bin/sh', info['Config']['Image'], '-ec', 'test -z "$(ls -A /data)"'], capture_output=True)
    if check.returncode:
        raise SystemExit('Restore requires an empty MinIO volume; existing data is never overwritten')
    stopped()
    with gzip.open(source, 'rb') as archive:
        process = subprocess.Popen(['docker', 'cp', '-', container + ':/data'], stdin=subprocess.PIPE, stderr=subprocess.PIPE)
        shutil.copyfileobj(archive, process.stdin)
        process.stdin.close()
        error = process.stderr.read()
        if process.wait():
            raise SystemExit('Restore failed: ' + error.decode())
    print('Restored stopped MinIO volume from', source)
else:
    raise SystemExit('Expected backup or restore')
