import { describe, expect, test } from 'vitest'
import { config, requireAnonKey } from '../src/env.js'
import { apiRequest, expectOk } from '../src/http.js'

async function expectGraphqlIntrospection(key: string, label: string): Promise<void> {
  const result = await apiRequest('/graphql/v1', {
    method: 'POST',
    key,
    json: { query: 'query { __schema { queryType { name } } }' },
  })

  expectOk(result, label)
  expect(result.text.toLowerCase(), `${label}: ${result.text.slice(0, 500)}`).not.toMatch(
    /errors|pg_graphql extension is not enabled|could not find the function/,
  )
}

describe('graphql', () => {
  test('introspection works with anon and publishable keys', async () => {
    await expectGraphqlIntrospection(requireAnonKey(), 'graphql introspection anon')

    if (config.publishableKey) {
      await expectGraphqlIntrospection(config.publishableKey, 'graphql introspection publishable')
    }
  })
})
