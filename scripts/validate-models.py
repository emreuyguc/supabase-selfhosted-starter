#!/usr/bin/env python3
"""Check every platform artifact against Compose, including embedded file bytes."""
import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

import yaml
from compose_model import VARIANTS, STORAGES, VARIANT_ALIASES, STORAGE_ALIASES, compose_model, dokploy_model

ROOT = Path(__file__).resolve().parents[1]


def canonical(variant, storage, artifact=None, interpolate=False):
    """Independent CLI parse: do not reuse the renderer's model adaptation."""
    env = {k: os.environ[k] for k in ('PATH', 'HOME', 'TMPDIR') if k in os.environ}
    env['COMPOSE_DISABLE_ENV_FILE'] = '1'
    cmd = ['docker', 'compose', '--project-directory', str(ROOT), '--env-file', str(ROOT / f'.env.{variant}.example')]
    if storage == 'external-s3':
        cmd += ['--env-file', str(ROOT / '.env.external-s3.example')]
    if artifact is None:
        cmd += ['-f', str(ROOT / 'compose.yaml'), '-f', str(ROOT / f'compose.{variant}.yaml')]
        if storage == 'external-s3':
            cmd += ['-f', str(ROOT / 'compose.features.external-s3.yaml')]
        cmd += ['-f', str(ROOT / 'compose.prod.yaml')]
    else:
        cmd += ['-f', '-']
    cmd += ['config', '--no-path-resolution', '--format', 'json']
    if not interpolate:
        cmd += ['--no-interpolate', '--no-normalize']
    result = subprocess.run(cmd, cwd=ROOT, env=env, input=artifact, text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def check_independent_source(actual, variant, storage):
    source = canonical(variant, storage)
    source['services'] = {k: v for k, v in source['services'].items() if not v.get('profiles')}
    used = {m['source'] for s in source['services'].values() for m in s.get('volumes', []) if m['type'] == 'volume'}
    source['volumes'] = {k: v for k, v in source.get('volumes', {}).items() if k in used}
    restored = copy.deepcopy(actual)
    restored['name'] = '${CONTAINER_PREFIX}'
    for service in restored['services'].values():
        if 'container_name' in service:
            service['container_name'] = service['container_name'].replace('${CONTAINER_PREFIX:-supabase}', '${CONTAINER_PREFIX}')
        for mount in service.get('volumes', []):
            if mount['type'] == 'bind' and mount['source'].startswith('../files/'):
                mount['source'] = './files/' + mount['source'][len('../files/'):]
                assert (ROOT / mount['source']).exists(), f'Missing bind source: {mount["source"]}'
    assert restored == source, f'{variant}/{storage}: independent source drift'


def parse_toml(text):
    try:
        import tomllib
        return tomllib.loads(text)
    except ImportError:
        python = shutil.which('python3.11')
        if not python:
            raise SystemExit('Python 3.11+ is required to validate Dokploy TOML')
        result = subprocess.run([python, '-c', 'import sys,json,tomllib; print(json.dumps(tomllib.loads(sys.stdin.read())))'], input=text, text=True, capture_output=True, check=True)
        return json.loads(result.stdout)


expected_templates = {f'{variant}-{storage}.json' for variant in VARIANTS for storage in STORAGES}
assert {path.name for path in (ROOT / 'dokploy/templates').glob('*.json')} == expected_templates, 'Unexpected or missing scenario artifacts'
manifest = yaml.safe_load((ROOT / 'manifest.yaml').read_text())
assert set(manifest['variants']) == set(VARIANTS), 'Manifest database variant names differ'
assert set(manifest['platform_templates']['dokploy_variants']) == {path[:-5] for path in expected_templates}, 'Manifest scenario names differ'
for old, current in VARIANT_ALIASES.items():
    for storage in STORAGES:
        assert compose_model(ROOT, old, storage) == compose_model(ROOT, current, storage), f'Legacy variant alias differs: {old}'
    for prefix, suffix in [('compose.', '.yaml'), ('.env.', '.example')]:
        alias = ROOT / (prefix + old + suffix)
        target = ROOT / (prefix + current + suffix)
        assert alias.is_symlink() and alias.resolve() == target.resolve(), f'Broken compatibility path: {alias.name}'
for old, current in STORAGE_ALIASES.items():
    for variant in VARIANTS:
        assert compose_model(ROOT, variant, old) == compose_model(ROOT, variant, current), f'Legacy storage alias differs: {old}'
print('PASS canonical scenario inventory, legacy CLI aliases and Compose/env compatibility paths')

for variant in VARIANTS:
    for storage in STORAGES:
        path = ROOT / 'dokploy/templates' / f'{variant}-{storage}.json'
        artifact = json.loads(path.read_text())
        actual = yaml.safe_load(artifact['compose'])
        expected = dokploy_model(compose_model(ROOT, variant, storage))
        assert actual == expected, f'{path.name}: differs from canonical Compose overlays'
        check_independent_source(actual, variant, storage)
        config = parse_toml(artifact['config'])['config']
        env = dict(item.split('=', 1) for item in config['env'])
        assert len(env) == len(config['env']), f'{path.name}: duplicate env key'
        references = set(re.findall(r'\$\{([A-Z][A-Z0-9_]*)', artifact['compose']))
        assert references <= env.keys(), f'{path.name}: missing env keys {references - env.keys()}'
        mounts = {m['filePath']: m['content'] for m in config['mounts']}
        assert len(mounts) == len(config['mounts']), f'{path.name}: duplicate file mount'
        expected_mounts = set()
        for source in (ROOT / 'files').rglob('*'):
            if not source.is_file() or source.name.startswith('.'):
                continue
            target = '/' + source.relative_to(ROOT / 'files').as_posix()
            expected_mounts.add(target)
            assert mounts.get(target, '').encode() == source.read_bytes(), f'{path.name}: mount content differs: {source}'
        assert mounts.keys() == expected_mounts, f'{path.name}: unexpected/missing mount'
        source_commands = canonical(variant, storage, interpolate=True)['services']
        artifact_commands = canonical(variant, storage, artifact=artifact['compose'], interpolate=True)['services']
        for name in actual['services']:
            assert artifact_commands[name].get('command') == source_commands[name].get('command'), f'{path.name}: command escaping/interpolation changed for {name}'
        for service in actual['services'].values():
            assert not service.get('ports'), f'{path.name}: unexpected public port'
            assert service.get('logging', {}).get('options', {}).get('max-size') == '10m', f'{path.name}: unbounded logs'
            assert service.get('restart') in ('unless-stopped', 'no'), f'{path.name}: missing restart policy'
        # Parse the embedded Compose, not merely the JSON/YAML wrapper.
        cmd = ['docker', 'compose', '--env-file', str(ROOT / f'.env.{variant}.example')]
        if storage == 'external-s3':
            cmd += ['--env-file', str(ROOT / '.env.external-s3.example')]
        subprocess.run(cmd + ['-f', '-', 'config', '--quiet'], input=artifact['compose'], text=True, check=True, cwd=ROOT)
        print(f'PASS {variant}-{storage}: Compose parity, env coverage, production policy and TOML mount bytes')

baseline = compose_model(ROOT, 'internal-db', 'minio')
os.environ.update(POSTGRES_DB='must-not-leak', COMPOSE_PROFILES='full-only', COMPOSE_FILE='/invalid')
assert compose_model(ROOT, 'internal-db', 'minio') == baseline, 'Caller environment contaminated template rendering'
print('PASS template rendering isolates deployment variables from the caller')

scratch = ROOT / '.scratch' / 'tmp'
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='dokploy-isolation-', dir=scratch) as directory:
    fixture = Path(directory)
    for pattern in ('compose*.yaml', '.env*.example'):
        for source in ROOT.glob(pattern):
            shutil.copy2(source, fixture / source.name)
    (fixture / '.env').write_text('CONTAINER_PREFIX=must-not-read-fixture\nSERVICE_PASSWORD_POSTGRES=must-not-read-fixture\nCOMPOSE_PROFILES=full-only\n')
    before = os.environ.copy()
    try:
        baseline = compose_model(fixture, 'external-db-bootstrap', 'external-s3')
        os.environ.update(COMPOSE_FILE='/invalid', COMPOSE_ENV_FILES='/invalid', COMPOSE_PROFILES='full-only,local-storage-only', CONTAINER_PREFIX='must-not-read-caller', SERVICE_PASSWORD_POSTGRES='must-not-read-caller')
        assert compose_model(fixture, 'external-db-bootstrap', 'external-s3') == baseline
        serialized = json.dumps(baseline)
        assert 'must-not-read-fixture' not in serialized and 'must-not-read-caller' not in serialized
    finally:
        os.environ.clear()
        os.environ.update(before)
print('PASS separate fixture .env and external-DB/S3 profile isolation')
