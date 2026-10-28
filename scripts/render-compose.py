#!/usr/bin/env python3
"""Export one secret-free, merged production Compose definition at repo root."""
import argparse
from pathlib import Path
import yaml
from compose_model import VARIANTS, STORAGES, compose_model, normalize_variant, normalize_storage

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--variant', type=normalize_variant, choices=VARIANTS, default='internal-db')
parser.add_argument('--storage', type=normalize_storage, choices=STORAGES, default='external-s3')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
model = compose_model(root, args.variant, args.storage)
model['services'] = {k: v for k, v in model['services'].items() if not v.get('profiles')}
used = {m['source'] for s in model['services'].values() for m in s.get('volumes', []) if m['type'] == 'volume'}
model['volumes'] = {k: v for k, v in model.get('volumes', {}).items() if k in used}
target = root / 'compose.deploy.yaml'
target.write_text(yaml.safe_dump(model, sort_keys=False))
print(f'Rendered {target.name} for {args.variant}/{args.storage}; copy runtime env separately')
