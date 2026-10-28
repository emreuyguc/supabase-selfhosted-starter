#!/usr/bin/env python3
"""Restore this starter's pg_dumpall into an empty, matching-bootstrap cluster."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
envfile, backup = map(Path, sys.argv[1:3])
cmd = ['docker', 'compose', '--env-file', str(envfile), '-f', str(ROOT / 'compose.yaml'), 'exec', '-T', 'supabase-db', 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'supabase_admin', '-d', 'postgres']
query = """
SELECT json_build_object(
  'bootstrap', (SELECT rolname FROM pg_roles WHERE oid = 10),
  'extra_roles', (SELECT count(*) FROM pg_roles WHERE rolname !~ '^pg_' AND rolname <> 'supabase_admin'),
  'extra_databases', (SELECT count(*) FROM pg_database WHERE datname NOT IN ('postgres','template0','template1')),
  'objects', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname !~ '^pg_toast' AND c.relkind IN ('r','p','v','m','f','S'))
)::text;
"""
result = subprocess.run(cmd + ['-Atc', query], capture_output=True, text=True, cwd=ROOT)
if result.returncode:
    raise SystemExit('Restore target preflight failed; prepare an empty cluster with bootstrap superuser supabase_admin')
state = json.loads(result.stdout)
if state['bootstrap'] != 'supabase_admin' or any(state[k] for k in ('extra_roles', 'extra_databases', 'objects')):
    raise SystemExit('Restore requires an empty cluster initialized with bootstrap superuser supabase_admin; initialized application data/roles are never overwritten')


def filtered_dump():
    # PostgreSQL 17 GRANTED BY preserves the bootstrap grantor. A different
    # bootstrap superuser breaks those grants. Keep the same bootstrap name and
    # omit ONLY its redundant CREATE ROLE, bounded to pg_dumpall's roles preamble.
    # COPY payloads and every other SQL statement remain byte-for-byte unchanged.
    roles = False
    with backup.open('rb') as source:
        for line in source:
            token = line.rstrip(b'\r\n')
            if token == b'-- Roles':
                roles = True
            elif token in (b'-- Role memberships', b'-- User Configurations') or token.startswith(b'\\connect '):
                roles = False
            if roles and token in (b'CREATE ROLE supabase_admin;', b'CREATE ROLE "supabase_admin";'):
                continue
            yield line


process = subprocess.Popen(cmd, stdin=subprocess.PIPE, cwd=ROOT)
try:
    for block in filtered_dump():
        process.stdin.write(block)
    process.stdin.close()
except BrokenPipeError:
    pass
status = process.wait()
if status:
    raise SystemExit(status)
