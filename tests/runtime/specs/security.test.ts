import { describe, test } from 'vitest'
import { config, requireAnonKey, requireServiceRoleKey } from '../src/env.js'
import { apiRequest, expectOk, expectStatus } from '../src/http.js'

describe('security', () => {
  test('pg-meta rejects public keys and accepts admin keys', async () => {
    const anon = requireAnonKey()
    const service = requireServiceRoleKey()

    expectStatus(await apiRequest('/pg/health', { key: anon }), [401, 403], 'pg-meta rejects anon')

    if (config.publishableKey) {
      expectStatus(await apiRequest('/pg/health', { key: config.publishableKey }), [401, 403], 'pg-meta rejects publishable')
    }

    expectOk(await apiRequest('/pg/health', { key: service }), 'pg-meta accepts service')

    if (config.secretKey) {
      expectOk(await apiRequest('/pg/health', { key: config.secretKey }), 'pg-meta accepts secret')
    }
  })

  test('MCP direct access is blocked', async () => {
    expectStatus(await apiRequest('/api/mcp'), [401, 403], 'mcp direct access blocked')
  })
})
