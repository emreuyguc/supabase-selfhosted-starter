import { describe, expect, test } from 'vitest'
import { config, requireAnonKey, requireServiceRoleKey } from '../src/env.js'
import { apiRequest, expectOk, expectStatus } from '../src/http.js'

describe('auth', () => {
  test('health accepts anon and publishable keys', async () => {
    const anon = requireAnonKey()
    expectOk(await apiRequest('/auth/v1/health', { key: anon }), 'auth health anon')

    if (config.publishableKey) {
      expectOk(await apiRequest('/auth/v1/health', { key: config.publishableKey }), 'auth health publishable')
    }
  })

  test('public signup is disabled or rejected by default', async () => {
    const anon = requireAnonKey()
    const result = await apiRequest('/auth/v1/signup', {
      method: 'POST',
      key: anon,
      json: {
        email: 'supabase-starter-disabled@example.test',
        password: 'Password123456!',
      },
    })

    expectStatus(result, [400, 401, 403, 422], 'public signup disabled')
  })

  test('service role can create and delete an admin user', async () => {
    const service = requireServiceRoleKey()
    const email = `codex-auth-${config.runId}@example.test`

    const created = await apiRequest<{ id?: string }>('/auth/v1/admin/users', {
      method: 'POST',
      key: service,
      json: {
        email,
        password: 'Password123456!',
        email_confirm: true,
      },
    })
    expectOk(created, 'auth admin create user')
    expect(created.json?.id, `create user response: ${created.text}`).toBeTruthy()

    const deleted = await apiRequest(`/auth/v1/admin/users/${created.json?.id}`, {
      method: 'DELETE',
      key: service,
    })
    expectOk(deleted, 'auth admin delete user')
  })

  test('modern secret key can access auth admin when configured', async () => {
    if (!config.secretKey) return
    expectOk(
      await apiRequest('/auth/v1/admin/users?page=1&per_page=1', { key: config.secretKey }),
      'auth admin modern secret',
    )
  })
})
