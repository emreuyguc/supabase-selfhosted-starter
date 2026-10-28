import { createHash } from 'node:crypto'
import { describe, expect, test } from 'vitest'
import { config, requireBaseUrl, requireServiceRoleKey } from '../src/env.js'
import { apiRequest, expectOk, expectStatus, authHeaders } from '../src/http.js'

describe('resumable uploads', () => {
  test('a two-part 7 MiB TUS upload downloads with matching bytes', async () => {
    const service = requireServiceRoleKey()
    const bucket = `tus-${config.runId}`
    const object = 'payload.bin'
    const payload = Buffer.alloc(7 * 1024 * 1024, 0x5a)
    const hash = (value: Buffer) => createHash('sha256').update(value).digest('hex')
    try {
      expectOk(await apiRequest('/storage/v1/bucket', { method: 'POST', key: service, json: { id: bucket, name: bucket, public: true } }), 'TUS bucket')
      const metadata = Object.entries({ bucketName: bucket, objectName: object, contentType: 'application/octet-stream' })
        .map(([k, v]) => `${k} ${Buffer.from(v).toString('base64')}`).join(',')
      const create = await apiRequest('/storage/v1/upload/resumable', {
        method: 'POST', key: service,
        headers: { 'Tus-Resumable': '1.0.0', 'Upload-Length': String(payload.length), 'Upload-Metadata': metadata },
      })
      expectStatus(create, [201], 'TUS create')
      const location = new URL(create.response.headers.get('Location')!, requireBaseUrl())
      expect(location.origin).toBe(new URL(requireBaseUrl()).origin)
      expect(location.pathname).toMatch(/^\/storage\/v1\/upload\/resumable\//)
      for (const [start, end] of [[0, 4 * 1024 * 1024], [4 * 1024 * 1024, payload.length]]) {
        const response = await fetch(location, {
          method: 'PATCH', headers: { ...authHeaders(service), 'Tus-Resumable': '1.0.0', 'Upload-Offset': String(start), 'Content-Type': 'application/offset+octet-stream' },
          body: payload.subarray(start, end),
        })
        expect(response.status, await response.text()).toBe(204)
        expect(Number(response.headers.get('Upload-Offset'))).toBe(end)
      }
      const download = await fetch(`${requireBaseUrl()}/storage/v1/object/public/${bucket}/${object}`)
      expect(download.status).toBe(200)
      const bytes = Buffer.from(await download.arrayBuffer())
      expect(bytes.length).toBe(payload.length)
      expect(hash(bytes)).toBe(hash(payload))
    } finally {
      await apiRequest(`/storage/v1/object/${bucket}/${object}`, { method: 'DELETE', key: service })
      await apiRequest(`/storage/v1/bucket/${bucket}`, { method: 'DELETE', key: service })
    }
  })
})
