import { describe, test } from 'vitest'
import { config, requireAnonKey } from '../src/env.js'
import { apiRequest, expectOk } from '../src/http.js'

describe('edge functions', () => {
  test('hello function accepts anon and publishable keys', async () => {
    const anon = requireAnonKey()
    expectOk(await apiRequest('/functions/v1/hello', { key: anon }), 'edge hello anon')

    if (config.publishableKey) {
      expectOk(await apiRequest('/functions/v1/hello', { key: config.publishableKey }), 'edge hello publishable')
    }
  })
})
