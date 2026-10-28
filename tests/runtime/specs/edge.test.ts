import { describe, test } from 'vitest'
import { config, requireAnonKey } from '../src/env.js'
import { apiRequest, expectOk, expectStatus } from '../src/http.js'

describe('edge functions', () => {
  test('hello function accepts anon and publishable keys', async () => {
    const anon = requireAnonKey()
    expectOk(await apiRequest('/functions/v1/hello', { key: anon }), 'edge hello anon')

    if (config.publishableKey) {
      expectOk(await apiRequest('/functions/v1/hello', { key: config.publishableKey }), 'edge hello publishable')
    }
  })

  test('opaque apikey-only requests work and JWT verification follows configuration', async () => {
    if (config.publishableKey) {
      expectOk(await apiRequest('/functions/v1/hello', { headers: { apikey: config.publishableKey } }), 'edge apikey only')
    }
    const verify = process.env.FUNCTIONS_VERIFY_JWT === 'true'
    expectStatus(await apiRequest('/functions/v1/hello'), [verify ? 401 : 200], 'edge missing credentials')
    expectStatus(await apiRequest('/functions/v1/hello', {
      headers: { apikey: config.publishableKey || '', Authorization: 'Bearer invalid.user.jwt' },
    }), [verify ? 401 : 200], 'a bad user JWT is never replaced by the public API key')
    expectStatus(await apiRequest('/functions/v1/hello', {
      headers: { 'sb-api-key': config.serviceRoleKey || '' },
    }), [verify ? 401 : 200], 'client cannot spoof the internal compatibility header')
  })
})
