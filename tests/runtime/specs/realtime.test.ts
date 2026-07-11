import { describe, expect, test } from 'vitest'
import { requireAnonKey, requireBaseUrl } from '../src/env.js'
import { realtimeJoin } from '../src/realtime.js'

describe('realtime', () => {
  test('websocket upgrade and channel join work', async () => {
    const result = await realtimeJoin(requireBaseUrl(), requireAnonKey())
    expect(result.statusLine).toContain('101')
    expect(result.message).toContain('phx_reply')
    expect(result.message.replace(/\s/g, '')).toContain('"status":"ok"')
  })
})
