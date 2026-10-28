import { createHmac } from 'node:crypto'
import { describe, expect, test } from 'vitest'
import { config, requireServiceRoleKey } from '../src/env.js'
import { apiRequest, expectOk, expectStatus, pgQuery } from '../src/http.js'

const jwtSecret = process.env.SERVICE_PASSWORD_JWT || process.env.JWT_SECRET

// The default starter disables email login. Mint short-lived test sessions for
// two real Auth users, using only the disposable deployment's signing secret.
function session(userId: string): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url')
  const now = Math.floor(Date.now() / 1000)
  const payload = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: userId, role: 'authenticated', aud: 'authenticated', iat: now, exp: now + 300 })}`
  return `${payload}.${createHmac('sha256', jwtSecret!).update(payload).digest('base64url')}`
}

describe('storage isolation', () => {
  test.skipIf(!jwtSecret)('a user JWT retains RLS restrictions alongside publishable and secret API keys', async () => {
    const service = requireServiceRoleKey()
    const users: string[] = []
    const bucket = `isolation-${config.runId}`
    const policy = `isolation_${config.runId.replace(/[^a-z0-9]/gi, '').slice(-24)}`
    let object = ''
    try {
      for (const suffix of ['a', 'b']) {
        const result = await apiRequest<{ id: string }>('/auth/v1/admin/users', {
          method: 'POST', key: service,
          json: { email: `isolation-${suffix}-${config.runId}@example.test`, password: 'DisposablePassword123!', email_confirm: true },
        })
        expectOk(result, 'create isolated user')
        users.push(result.json!.id)
      }
      expectOk(await apiRequest('/storage/v1/bucket', { method: 'POST', key: service, json: { id: bucket, name: bucket, public: false } }), 'create private bucket')
      expectOk(await pgQuery(`create policy ${policy} on storage.objects for all to authenticated using (bucket_id = '${bucket}' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = '${bucket}' and (storage.foldername(name))[1] = auth.uid()::text)`, service), 'create storage RLS policy')
      object = `${users[0]}/private.txt`
      expectOk(await apiRequest(`/storage/v1/object/${bucket}/${object}`, {
        method: 'POST', key: config.publishableKey || service,
        headers: { Authorization: `Bearer ${session(users[0])}`, 'Content-Type': 'text/plain' }, body: 'private-user-a',
      }), 'user A upload')
      const own = await apiRequest(`/storage/v1/object/authenticated/${bucket}/${object}`, {
        key: config.publishableKey || service, headers: { Authorization: `Bearer ${session(users[0])}` },
      })
      expectOk(own, 'user A read')
      expect(own.text).toBe('private-user-a')
      for (const key of [config.publishableKey, config.secretKey, service].filter(Boolean) as string[]) {
        const other = await apiRequest(`/storage/v1/object/authenticated/${bucket}/${object}`, {
          key, headers: { Authorization: `Bearer ${session(users[1])}` },
        })
        expectStatus(other, [400, 403, 404], 'user B cannot read user A object')
        expect(other.text).not.toContain('private-user-a')
      }
    } finally {
      if (object) expectOk(await apiRequest(`/storage/v1/object/${bucket}/${object}`, { method: 'DELETE', key: service }), 'delete isolation object')
      await apiRequest(`/storage/v1/bucket/${bucket}`, { method: 'DELETE', key: service })
      expectOk(await pgQuery(`drop policy if exists ${policy} on storage.objects`, service), 'drop isolation policy')
      for (const id of users) expectOk(await apiRequest(`/auth/v1/admin/users/${id}`, { method: 'DELETE', key: service }), 'delete isolated user')
    }
  })
})
