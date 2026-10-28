import { describe, expect, test } from 'vitest'
import { config, requireAnonKey, requireBaseUrl, requireServiceRoleKey } from '../src/env.js'
import { openRealtime, realtimeJoin } from '../src/realtime.js'
import { expectOk, pgQuery } from '../src/http.js'

describe('realtime', () => {
  test('websocket upgrade and channel join work', async () => {
    const result = await realtimeJoin(requireBaseUrl(), requireAnonKey())
    expect(result.statusLine).toContain('101')
    expect(result.message).toContain('phx_reply')
    expect(result.message.replace(/\s/g, '')).toContain('"status":"ok"')
  })

  test('Postgres INSERT/UPDATE/DELETE reach the subscriber and hidden rows retain RLS', async () => {
    const table = `cdc_${config.runId.replace(/[^a-z0-9]/gi, '').slice(-32)}`
    const admin = requireServiceRoleKey()
    const client = await openRealtime(requireBaseUrl(), requireAnonKey())
    const topic = `realtime:${table}`
    try {
      expectOk(await pgQuery(`
        CREATE TABLE public.${table} (id integer PRIMARY KEY, body text NOT NULL, visible boolean NOT NULL);
        ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY;
        CREATE POLICY ${table}_read ON public.${table} FOR SELECT TO anon USING (visible);
        GRANT SELECT ON public.${table} TO anon;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.${table};
      `, admin), 'prepare actual CDC publication and RLS')
      client.send(['1', '1', topic, 'phx_join', {
        config: { broadcast: { self: false }, presence: { enabled: false }, postgres_changes: [{ event: '*', schema: 'public', table, select: ['id', 'body', 'visible'] }] },
        access_token: requireAnonKey(),
      }])
      let joined = false
      let ready = false
      let bindingId: number | undefined
      const deadline = Date.now() + 35_000
      while (!joined || !ready) {
        const message = await client.receive(Math.max(1, deadline - Date.now()))
        const [,,, event, payload] = message
        if (event === 'phx_reply') {
          expect(payload.status, JSON.stringify(payload)).toBe('ok')
          bindingId = payload.response?.postgres_changes?.[0]?.id
          joined = true
        }
        if (event === 'system' && payload.extension === 'postgres_changes') {
          expect(payload.status, JSON.stringify(payload)).toBe('ok')
          ready = true
        }
      }
      expect(bindingId).toBeTypeOf('number')
      const expectChange = async (type: string, body?: string) => {
        const end = Date.now() + 15_000
        for (;;) {
          const [,,, event, payload] = await client.receive(Math.max(1, end - Date.now()))
          if (event === 'system' && payload.status === 'error') throw new Error(JSON.stringify(payload))
          if (event !== 'postgres_changes') continue
          expect(payload.ids).toContain(bindingId)
          expect(payload.data?.table).toBe(table)
          expect(payload.data?.record?.id, 'hidden row must not be delivered').not.toBe(2)
          expect(payload.data?.type).toBe(type)
          if (type === 'DELETE') expect(payload.data?.old_record?.id).toBe(1)
          else {
            expect(payload.data?.record?.id).toBe(1)
            expect(payload.data?.record?.body).toBe(body)
          }
          return
        }
      }
      expectOk(await pgQuery(`INSERT INTO public.${table} VALUES (2, 'hidden', false), (1, 'created', true)`, admin), 'write CDC source rows')
      await expectChange('INSERT', 'created')
      expectOk(await pgQuery(`UPDATE public.${table} SET body='updated' WHERE id=1`, admin), 'update CDC source row')
      await expectChange('UPDATE', 'updated')
      expectOk(await pgQuery(`DELETE FROM public.${table} WHERE id=1`, admin), 'delete CDC source row')
      await expectChange('DELETE')
    } finally {
      client.close()
      expectOk(await pgQuery(`DROP TABLE IF EXISTS public.${table}`, admin), 'remove CDC probe table')
    }
  }, 60_000)
})
