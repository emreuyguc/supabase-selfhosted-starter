import { createHash, createHmac } from 'node:crypto'
import { describe, expect, test } from 'vitest'
import { config, requireBaseUrl, requireServiceRoleKey } from '../src/env.js'
import { apiRequest, expectOk } from '../src/http.js'

const access = process.env.S3_PROTOCOL_ACCESS_KEY_ID
const secret = process.env.S3_PROTOCOL_ACCESS_KEY_SECRET
const region = process.env.STORAGE_S3_REGION || 'us-east-1'
const digest = (value: string) => createHash('sha256').update(value).digest('hex')
const mac = (key: string | Buffer, value: string) => createHmac('sha256', key).update(value).digest()

function signingKey(date: string, key = secret!) {
  return mac(mac(mac(mac(`AWS4${key}`, date), region), 's3'), 'aws4_request')
}

function signed(method: string, path: string, body = '', key = secret!) {
  const date = new Date().toISOString().replace(/[:-]|\.\d{3}/g, '')
  const scope = `${date.slice(0, 8)}/${region}/s3/aws4_request`
  const host = new URL(requireBaseUrl()).host
  const hash = digest(body)
  const names = 'host;x-amz-content-sha256;x-amz-date'
  const canonical = `${method}\n${path}\n\nhost:${host}\nx-amz-content-sha256:${hash}\nx-amz-date:${date}\n\n${names}\n${hash}`
  const sign = mac(signingKey(date.slice(0, 8), key), `AWS4-HMAC-SHA256\n${date}\n${scope}\n${digest(canonical)}`).toString('hex')
  return {
    Authorization: `AWS4-HMAC-SHA256 Credential=${access}/${scope}, SignedHeaders=${names}, Signature=${sign}`,
    'x-amz-date': date, 'x-amz-content-sha256': hash,
    // This deliberately accompanies SigV4; the gateway must preserve it.
    apikey: config.publishableKey || '',
  }
}

describe('S3 protocol', () => {
  test.skipIf(!access || !secret)('SigV4 upload/download works alongside an apikey, and bad signatures are rejected', async () => {
    const bucket = `sigv4-${config.runId}`
    const object = 'signed.txt'
    const path = `/storage/v1/s3/${bucket}/${object}`
    const body = 'sigv4-payload'
    const admin = requireServiceRoleKey()
    try {
      expectOk(await apiRequest('/storage/v1/bucket', { method: 'POST', key: admin, json: { id: bucket, name: bucket, public: false } }), 'S3 bucket')
      expectOk(await apiRequest(path, { method: 'PUT', headers: signed('PUT', path, body), body }), 'SigV4 upload')
      const download = await apiRequest(path, { headers: signed('GET', path) })
      expectOk(download, 'SigV4 download')
      expect(download.text).toBe(body)
      const invalid = await apiRequest(path, { headers: signed('GET', path, '', 'invalid-secret') })
      expect(invalid.response.ok).toBe(false)
      expect(invalid.text).not.toBe(body)
    } finally {
      await apiRequest(`/storage/v1/object/${bucket}/${object}`, { method: 'DELETE', key: admin })
      await apiRequest(`/storage/v1/bucket/${bucket}`, { method: 'DELETE', key: admin })
    }
  })
})
