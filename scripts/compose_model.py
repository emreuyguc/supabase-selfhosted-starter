"""Let Docker Compose merge the canonical overlays; adapt only platform paths."""
import copy
import json
import os
from pathlib import Path
import subprocess

VARIANTS = ('internal-db', 'external-db-bootstrap', 'external-db-existing')
STORAGES = ('minio', 'external-s3')
VARIANT_ALIASES = {'full': 'internal-db', 'external-db': 'external-db-bootstrap', 'external-prebuilt': 'external-db-existing'}
STORAGE_ALIASES = {'local': 'minio'}


def normalize_variant(value):
    value = VARIANT_ALIASES.get(value, value)
    if value not in VARIANTS:
        raise ValueError('Unsupported database variant: ' + value)
    return value


def normalize_storage(value):
    value = STORAGE_ALIASES.get(value, value)
    if value not in STORAGES:
        raise ValueError('Unsupported storage: ' + value)
    return value


def compose_model(root, variant, storage, production=True):
    root = Path(root).resolve()
    variant, storage = normalize_variant(variant), normalize_storage(storage)
    env = {k: os.environ[k] for k in ('PATH', 'HOME', 'LANG', 'LC_ALL', 'TMPDIR') if k in os.environ}
    env['COMPOSE_DISABLE_ENV_FILE'] = '1'
    cmd = ['docker', 'compose', '--project-directory', str(root), '--env-file', str(root / f'.env.{variant}.example')]
    if storage == 'external-s3':
        cmd += ['--env-file', str(root / '.env.external-s3.example')]
    cmd += ['-f', str(root / 'compose.yaml'), '-f', str(root / f'compose.{variant}.yaml')]
    if storage == 'external-s3':
        cmd += ['-f', str(root / 'compose.features.external-s3.yaml')]
    if production:
        cmd += ['-f', str(root / 'compose.prod.yaml')]
    cmd += ['config', '--no-interpolate', '--no-normalize', '--no-path-resolution', '--format', 'json']
    result = subprocess.run(cmd, cwd=root, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError('Compose 2.24.4+ required:\n' + result.stderr)
    return json.loads(result.stdout)


def dokploy_model(model):
    data = copy.deepcopy(model)
    data['name'] = '${CONTAINER_PREFIX:-supabase}'
    data['services'] = {k: v for k, v in data['services'].items() if not v.get('profiles')}
    used_volumes = set()
    for service in data['services'].values():
        if 'container_name' in service:
            service['container_name'] = service['container_name'].replace('${CONTAINER_PREFIX}', '${CONTAINER_PREFIX:-supabase}')
        for mount in service.get('volumes', []):
            if mount['type'] == 'bind' and mount['source'].startswith('./files/'):
                mount['source'] = '../files/' + mount['source'][len('./files/'):]
            elif mount['type'] == 'volume':
                used_volumes.add(mount['source'])
    data['volumes'] = {k: v for k, v in data.get('volumes', {}).items() if k in used_volumes}
    return data
