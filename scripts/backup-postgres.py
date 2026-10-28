#!/usr/bin/env python3
"""Dump the cluster and preserve built-in DB owners and the Supabase GraphQL wrapper."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
compose = ['docker', 'compose', '--env-file', sys.argv[1], '-f', str(ROOT / 'compose.yaml'), 'exec', '-T', 'supabase-db']


def conninfo(database):
    return "dbname='" + database.replace('\\', '\\\\').replace("'", "\\'") + "'"


def query(database, sql):
    result = subprocess.run(compose + ['psql', '-X', '-U', 'supabase_admin', '-d', conninfo(database), '-At', '-v', 'ON_ERROR_STOP=1'], input=sql, text=True, capture_output=True, cwd=ROOT)
    if result.returncode:
        raise RuntimeError('Backup recovery-metadata query failed')
    return json.loads(result.stdout)


def ident(value):
    return '"' + value.replace('"', '""') + '"'


def grants(kind, name, acl):
    yield f'REVOKE ALL ON {kind} {name} FROM PUBLIC;'
    for entry in acl:
        role = 'PUBLIC' if entry['role'] is None else ident(entry['role'])
        yield f"GRANT {entry['privilege_type']} ON {kind} {name} TO {role}" + (' WITH GRANT OPTION' if entry['is_grantable'] else '') + ';'


databases = query('postgres', "SELECT json_agg(json_build_object('name', datname, 'owner', pg_get_userbyid(datdba)) ORDER BY datname) FROM pg_database WHERE datallowconn AND NOT datistemplate;")
postlude = ['-- Starter recovery metadata v1: database owners and extension-owned GraphQL API']
for database in databases:
    name = database['name']
    # Quote libpq conninfo and then psql's meta-command argument independently;
    # database names containing '=' must never become connection options.
    postlude += ['\\connect -reuse-previous=on ' + ident(conninfo(name)), f"ALTER DATABASE {ident(name)} OWNER TO {ident(database['owner'])};"]
    metadata = query(name, """
SELECT json_build_object(
 'schemas', (SELECT coalesce(json_agg(json_build_object('name', n.nspname, 'acl',
   (SELECT json_agg(json_build_object('role', CASE WHEN a.grantee=0 THEN NULL ELSE pg_get_userbyid(a.grantee) END, 'privilege_type', a.privilege_type, 'is_grantable', a.is_grantable)) FROM aclexplode(coalesce(n.nspacl, acldefault('n',n.nspowner))) a))), '[]')
   FROM pg_namespace n WHERE n.nspname IN ('graphql','graphql_public')),
 'functions', (SELECT coalesce(json_agg(json_build_object('definition', pg_get_functiondef(p.oid),
   'signature', format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),
   'owner', pg_get_userbyid(p.proowner), 'acl',
   (SELECT json_agg(json_build_object('role', CASE WHEN a.grantee=0 THEN NULL ELSE pg_get_userbyid(a.grantee) END, 'privilege_type', a.privilege_type, 'is_grantable', a.is_grantable)) FROM aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) a))), '[]')
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   JOIN pg_depend d ON d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e'
   JOIN pg_extension e ON d.refclassid='pg_extension'::regclass AND d.refobjid=e.oid
   WHERE n.nspname='graphql_public' AND p.proname='graphql' AND e.extname='pg_graphql')
);
""")
    for schema in metadata['schemas']:
        postlude.extend(grants('SCHEMA', ident(schema['name']), schema['acl'] or []))
    for function in metadata['functions']:
        signature = function['signature']
        postlude += [function['definition'].rstrip().rstrip(';') + ';', f"ALTER FUNCTION {signature} OWNER TO {ident(function['owner'])};", f'ALTER EXTENSION pg_graphql ADD FUNCTION {signature};']
        postlude.extend(grants('FUNCTION', signature, function['acl'] or []))

sys.stdout.flush()
result = subprocess.run(compose + ['pg_dumpall', '-U', 'supabase_admin'], cwd=ROOT)
if result.returncode:
    raise SystemExit(result.returncode)
print('\n' + '\n'.join(postlude))
