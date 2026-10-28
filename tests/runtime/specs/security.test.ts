import { describe, expect, test } from 'vitest'
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

  test('MCP and Realtime management endpoints are blocked', async () => {
    for (const path of ['/api/mcp', '/mcp', '/realtime/v1/api/tenants', '/realtime/v1/api/openapi']) {
      expectStatus(await apiRequest(path, { key: requireServiceRoleKey() }), [403], `${path} blocked`)
    }
  })

  test('the protected storage schema is not exposed through REST', async () => {
    expectStatus(await apiRequest('/rest/v1/objects', {
      key: requireServiceRoleKey(), headers: { 'Accept-Profile': 'storage' },
    }), [406], 'storage schema is private')
  })

  test('Studio requires basic authentication', async () => {
    expectStatus(await apiRequest('/api/platform/profile'), [401], 'Studio unauthenticated')
    expect(config.dashboardUsername).toBeTruthy()
    expect(config.dashboardPassword).toBeTruthy()
    const basic = Buffer.from(`${config.dashboardUsername}:${config.dashboardPassword}`).toString('base64')
    expectOk(await apiRequest('/api/platform/profile', { headers: { Authorization: `Basic ${basic}` } }), 'Studio authenticated')
  })
})
