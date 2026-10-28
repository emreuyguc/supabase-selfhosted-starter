#!/usr/bin/env python3
"""Disposable real-image gateway/Edge checks; never loads the project's .env or DB.
Run: python3 tests/runtime/gateway-edge-check.py
Requires Docker and network access for the pinned images and jose module.
"""
import base64
import hashlib
import hmac
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
import yaml

ROOT = Path(__file__).resolve().parents[2]
RUN = 'supabase-security-' + uuid.uuid4().hex[:10]
SCRATCH = ROOT / '.scratch' / 'tmp'
SCRATCH.mkdir(parents=True, exist_ok=True)
MODEL = yaml.safe_load((ROOT / 'compose.yaml').read_text())['services']
EDGE_IMAGE = MODEL['supabase-edge-functions']['image']
KONG_IMAGE = MODEL['supabase-kong']['image']
SECRET = 'disposable-signing-secret-at-least-32-characters'
containers = []

def docker(*args):
    return subprocess.check_output(['docker', *args], text=True).strip()

def jwt(role):
    encode = lambda data: base64.urlsafe_b64encode(data).rstrip(b'=').decode()
    msg = encode(b'{"alg":"HS256","typ":"JWT"}') + '.' + encode(json.dumps({'role': role, 'exp': int(time.time()) + 3600}).encode())
    return msg + '.' + encode(hmac.new(SECRET.encode(), msg.encode(), hashlib.sha256).digest())

def run(name, image, args=(), env=None, mounts=(), aliases=(), port=None, entrypoint=None):
    fullname = RUN + '-' + name
    cmd = ['run', '-d', '--name', fullname, '--network', RUN]
    for alias in aliases: cmd += ['--network-alias', alias]
    for key, value in (env or {}).items(): cmd += ['-e', key + '=' + value]
    for src, dst in mounts: cmd += ['-v', str(src) + ':' + dst + ':ro']
    if port: cmd += ['-p', '127.0.0.1::' + str(port)]
    if entrypoint: cmd += ['--entrypoint', entrypoint]
    containers.append(fullname)
    docker(*cmd, image, *args)
    if port:
        address = docker('port', fullname, str(port) + '/tcp').split(':')[-1]
        return 'http://127.0.0.1:' + address

def request(base, path, headers=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(base + path, headers=headers or {}), timeout=10) as res:
            return res.status, dict(res.headers), res.read().decode()
    except urllib.error.HTTPError as res:
        return res.code, dict(res.headers), res.read().decode()

def wait(base, path='/'):
    for _ in range(90):
        try:
            request(base, path)
            return
        except (OSError, TimeoutError): time.sleep(1)
    raise AssertionError('Runtime did not become ready')

try:
    docker('network', 'create', RUN)
    with tempfile.TemporaryDirectory(prefix=RUN + '-', dir=SCRATCH) as temp:
        temp = Path(temp)
        functions = temp / 'functions'
        shutil.copytree(ROOT / 'files/volumes/functions', functions)
        (functions / 'probe').mkdir()
        (functions / 'probe/index.ts').write_text("Deno.serve(req => Response.json({headers:Object.fromEntries(req.headers),slug:Deno.env.get('SUPABASE_FUNCTION_SLUG')}))")
        key_fixture = json.loads(subprocess.check_output(['node', '-e', """
const c=require('node:crypto'); const {privateKey,publicKey}=c.generateKeyPairSync('ec',{namedCurve:'P-256'});
const jwk=publicKey.export({format:'jwk'}); jwk.kid='fixture'; jwk.alg='ES256';
const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const msg=enc({alg:'ES256',kid:'fixture'})+'.'+enc({exp:Math.floor(Date.now()/1000)+3600,role:'authenticated'});
const token=msg+'.'+c.sign('sha256',Buffer.from(msg),{key:privateKey,dsaEncoding:'ieee-p1363'}).toString('base64url');
console.log(JSON.stringify({jwks:{keys:[jwk]},token}));
"""], text=True))
        jwks_file = temp / 'jwks.json'
        jwks_file.write_text(json.dumps(key_fixture['jwks']))
        echo = temp / 'echo.py'
        echo.write_text('''from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import threading,json
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path.endswith('/.well-known/jwks.json'):
   self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(open('/jwks.json','rb').read());return
  self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(json.dumps({'headers':dict(self.headers),'path':self.path}).encode())
 def log_message(self,*args): pass
for port in [3000,4000,5000,8080,9999]:
 threading.Thread(target=ThreadingHTTPServer(('0.0.0.0',port),Handler).serve_forever,daemon=True).start()
threading.Event().wait()
''')
        run('echo','python:3.12-slim', ['python','/echo.py'], mounts=[(echo,'/echo.py'),(jwks_file,'/jwks.json')], aliases=['supabase-rest','supabase-auth','supabase-storage','realtime-dev','supabase-meta','supabase-studio'])
        anon, service = jwt('anon'), jwt('service_role')
        edge_env = {'JWT_SECRET':SECRET,'VERIFY_JWT':'true'}
        edge = run('edge',EDGE_IMAGE,['start','--user-worker-request-idle-timeout','150000','--main-service','/home/deno/functions/main'],env=edge_env,mounts=[(functions,'/home/deno/functions')],aliases=['supabase-edge-functions'],port=9000)
        env = {'SUPABASE_ANON_KEY':anon,'SUPABASE_SERVICE_KEY':service,'SUPABASE_PUBLISHABLE_KEY':'sb_publishable_test','SUPABASE_SECRET_KEY':'sb_secret_test','DASHBOARD_USERNAME':'test','DASHBOARD_PASSWORD':'test','KONG_DATABASE':'off','KONG_ROUTER_FLAVOR':'expressions','KONG_DECLARATIVE_CONFIG':'/tmp/kong.yml','KONG_PLUGINS':'request-transformer,cors,key-auth,acl,basic-auth,request-termination,ip-restriction,post-function','KONG_STORAGE_CONNECT_TIMEOUT':'60000','KONG_STORAGE_READ_TIMEOUT':'3600000','KONG_STORAGE_WRITE_TIMEOUT':'3600000','KONG_STORAGE_REQUEST_BUFFERING':'false','KONG_STORAGE_RESPONSE_BUFFERING':'false'}
        gateway = run('kong',KONG_IMAGE,['/home/kong/kong-entrypoint.sh'],env=env,mounts=[(ROOT/'files/volumes/api/kong.yml','/home/kong/temp.yml'),(ROOT/'files/volumes/api/kong-entrypoint.sh','/home/kong/kong-entrypoint.sh')],port=8000,entrypoint='/bin/bash')
        wait(gateway,'/storage/v1/status'); wait(edge,'/probe')
        # Inspect values observed by a real upstream, through the real Kong plugin stack.
        for auth in ['Bearer ' + jwt('user-a'),'Bearer ' + jwt('user-b'),'AWS4-HMAC-SHA256 Credential=fixture, SignedHeaders=host, Signature=fixture']:
            status, _, body = request(gateway,'/storage/v1/status',{'apikey':'sb_publishable_test','Authorization':auth})
            observed = {k.lower():v for k,v in json.loads(body)['headers'].items()}
            assert status == 200 and observed['authorization'] == auth, 'Storage overwrote caller identity'
        for path in ['/storage/v1/s3/bucket/key?X-Amz-Signature=fixture','/storage/v1/status']:
            status, _, body = request(gateway,path)
            assert 'authorization' not in {k.lower():v for k,v in json.loads(body)['headers'].items()}
        for key, token in [('sb_publishable_test',anon),('sb_secret_test',service), (anon,anon)]:
            _, _, body = request(gateway,'/storage/v1/status',{'apikey':key})
            assert {k.lower():v for k,v in json.loads(body)['headers'].items()}['authorization'] == 'Bearer ' + token
        for path in ['/rest/v1/','/pg/health']:
            for key, allowed in [(None,False),(anon,False),('sb_publishable_test',False),(service,True),('sb_secret_test',True)]:
                status,_,_ = request(gateway,path, {'apikey':key} if key else {})
                assert (status == 200) == allowed, (path,status,allowed)
        for path in ['/realtime/v1/api/tenants','/realtime/v1/api/tenants/a','/realtime/v1/api/openapi','/api/mcp','/mcp']:
            assert request(gateway,path,{'apikey':service})[0] == 403, path
        for path in ['/auth/v1/.well-known/openid-configuration','/auth/v1/.well-known/oauth-authorization-server','/.well-known/oauth-authorization-server/auth/v1']:
            assert request(gateway,path)[0] == 200, path
        for headers, expected in [({},401),({'sb-api-key':service},401),({'apikey':'invalid','sb-api-key':service},401),({'apikey':'sb_publishable_test'},200),({'Authorization':'Bearer sb_secret_test'},200),({'Authorization':'Bearer '+anon},200),({'apikey':'sb_publishable_test','Authorization':'Bearer broken'},401)]:
            status,_,body=request(gateway,'/functions/v1/probe',headers)
            assert status == expected, ('edge-auth', status, body)
            if status == 200: assert 'sb-api-key' not in json.loads(body)['headers']
        assert request(gateway,'/functions/v1/no-such-function',{'Authorization':'Bearer '+anon})[0] == 404
        for mode in ['local', 'remote']:
            env = {'JWT_SECRET':SECRET,'VERIFY_JWT':'true'}
            env.update({'SUPABASE_JWKS':json.dumps(key_fixture['jwks'])} if mode == 'local' else {'SUPABASE_URL':'http://supabase-auth:9999'})
            jwks_edge = run(mode,EDGE_IMAGE,['start','--main-service','/home/deno/functions/main'],env=env,mounts=[(functions,'/home/deno/functions')],port=9000)
            wait(jwks_edge,'/probe')
            assert request(jwks_edge,'/probe',{'Authorization':'Bearer '+key_fixture['token']})[0] == 200, mode
            assert request(jwks_edge,'/probe',{'Authorization':'Bearer '+anon})[0] == 200, mode + '-HS256'
        # Test runtime config discovery rather than passing unsupported importMapPath.
        (functions / 'mapped').mkdir()
        (functions / 'mapped/dep.ts').write_text("export const value='config-resolved'")
        (functions / 'mapped/deno.jsonc').write_text('{"imports":{"fixture-alias":"./dep.ts"}}')
        (functions / 'mapped/index.ts').write_text("import {value} from 'fixture-alias'; Deno.serve(()=>new Response(value))")
        mapped_status,_,mapped_body = request(edge,'/mapped',{'Authorization':'Bearer '+anon})
        assert mapped_status == 200 and mapped_body == 'config-resolved', 'per-function deno.jsonc resolution'
        print('PASS: per-function deno.jsonc alias discovery without importMapPath')
        # Separate verify=false instance proves public access without relaxing the true worker.
        public = run('public',EDGE_IMAGE,['start','--main-service','/home/deno/functions/main'],env={'JWT_SECRET':SECRET,'VERIFY_JWT':'false'},mounts=[(functions,'/home/deno/functions')],port=9000)
        wait(public,'/probe')
        assert request(public,'/probe')[0] == 200
        status,_,body=request(public,'/probe',{'sb-api-key':service})
        assert status == 200 and 'sb-api-key' not in json.loads(body)['headers']
        docker('exec',RUN+'-edge','bash','-c',"timeout 1 bash -c '</dev/tcp/127.0.0.1/9000'")
        print('PASS: real Kong route/key matrix, Storage identity/SigV4 header preservation, Edge verify true/false, local/remote JWKS plus HS256 and spoof rejection, TCP health probe')
        print('Scope: echo Storage upstream; actual RLS, signed S3 verification, and long TUS require the full disposable stack.')
except Exception:
    logdir = ROOT / '.scratch' / RUN
    logdir.mkdir(mode=0o700, exist_ok=True)
    for name in containers:
        result = subprocess.run(['docker','logs','--tail','30',name], capture_output=True, text=True)
        path = logdir / (name + '.log')
        path.write_text(result.stdout + result.stderr)
        path.chmod(0o600)
    print('Failure logs saved in', logdir)
    raise
finally:
    for name in reversed(containers):
        subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    subprocess.run(['docker','network','rm',RUN],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
