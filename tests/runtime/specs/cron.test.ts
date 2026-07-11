import { afterAll, describe, expect, test } from 'vitest'
import { config, requireServiceRoleKey } from '../src/env.js'
import { expectOk, pgQuery } from '../src/http.js'

describe('cron', () => {
  const job = `codex_cron_${config.runId.replaceAll('-', '_')}`

  afterAll(async () => {
    const service = requireServiceRoleKey()
    await pgQuery(`select cron.unschedule('${job}') where exists (select 1 from cron.job where jobname = '${job}');`, service)
  })

  test('pg_cron extension can schedule, list and unschedule jobs', async () => {
    const service = requireServiceRoleKey()

    const extension = await pgQuery("select extname, extversion from pg_extension where extname = 'pg_cron';", service)
    expectOk(extension, 'cron extension installed')
    expect(extension.text, extension.text.slice(0, 500)).toContain('pg_cron')

    expectOk(await pgQuery(`select cron.schedule('${job}', '* * * * *', 'select 1') as jobid;`, service), 'cron schedule')

    const listed = await pgQuery(`select jobid, jobname, active from cron.job where jobname = '${job}';`, service)
    expectOk(listed, 'cron job list')
    expect(listed.text, listed.text.slice(0, 500)).toContain(job)

    expectOk(await pgQuery(`select cron.unschedule('${job}') as unscheduled;`, service), 'cron unschedule')
  })
})
