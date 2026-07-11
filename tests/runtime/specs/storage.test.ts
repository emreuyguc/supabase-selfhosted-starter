import { afterAll, describe, expect, test } from 'vitest'
import { adminKey, config, requireServiceRoleKey } from '../src/env.js'
import { apiRequest, expectOk } from '../src/http.js'

describe('storage', () => {
  const bucket = `codex-storage-${config.runId}`.replaceAll('_', '-')
  const txtObject = 'hello.txt'
  const pngObject = 'pixel.png'

  afterAll(async () => {
    const service = requireServiceRoleKey()
    await apiRequest(`/storage/v1/object/${bucket}/${txtObject}`, { method: 'DELETE', key: service })
    await apiRequest(`/storage/v1/object/${bucket}/${pngObject}`, { method: 'DELETE', key: service })
    await apiRequest(`/storage/v1/bucket/${bucket}`, { method: 'DELETE', key: service })
  })

  test('bucket, object, signed URL and image transformation work', async () => {
    const key = adminKey()

    expectOk(await apiRequest('/storage/v1/status'), 'storage status')

    expectOk(
      await apiRequest('/storage/v1/bucket', {
        method: 'POST',
        key,
        json: { id: bucket, name: bucket, public: true },
      }),
      'storage create bucket',
    )

    expectOk(
      await apiRequest(`/storage/v1/object/${bucket}/${txtObject}`, {
        method: 'POST',
        key,
        headers: { 'Content-Type': 'text/plain' },
        body: 'hello from tests',
      }),
      'storage upload text',
    )

    expectOk(await apiRequest(`/storage/v1/object/public/${bucket}/${txtObject}`), 'storage public download')

    const pixel = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lU6sLwAAAABJRU5ErkJggg==',
      'base64',
    )
    expectOk(
      await apiRequest(`/storage/v1/object/${bucket}/${pngObject}`, {
        method: 'POST',
        key,
        headers: { 'Content-Type': 'image/png' },
        body: pixel,
      }),
      'storage upload png',
    )

    expectOk(
      await apiRequest(`/storage/v1/render/image/public/${bucket}/${pngObject}?width=16&height=16`),
      'storage imgproxy public png',
    )

    const signed = await apiRequest<{ signedURL?: string }>(`/storage/v1/object/sign/${bucket}/${txtObject}`, {
      method: 'POST',
      key,
      json: { expiresIn: 120 },
    })
    expectOk(signed, 'storage signed url create')
    expect(signed.json?.signedURL, `signed URL response: ${signed.text}`).toBeTruthy()

    const signedUrl = signed.json!.signedURL!
    const publicSignedUrl = signedUrl.startsWith('/storage/v1/')
      ? signedUrl
      : signedUrl.startsWith('/object/')
        ? `/storage/v1${signedUrl}`
        : signedUrl
    expectOk(await apiRequest(publicSignedUrl), 'storage signed url download')
  })
})
