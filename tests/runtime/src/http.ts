import { expect } from 'vitest'
import { requireBaseUrl } from './env.js'

export type ApiResponse<T = unknown> = {
  response: Response
  text: string
  json: T | null
}

export function authHeaders(key: string): Record<string, string> {
  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
  }
}

export async function apiRequest<T = unknown>(
  path: string,
  options: {
    method?: string
    key?: string
    headers?: Record<string, string>
    json?: unknown
    body?: BodyInit
  } = {},
): Promise<ApiResponse<T>> {
  const baseUrl = requireBaseUrl()
  const headers: Record<string, string> = {
    ...(options.key ? authHeaders(options.key) : {}),
    ...(options.headers ?? {}),
  }

  let body = options.body
  if (options.json !== undefined) {
    headers['Content-Type'] ??= 'application/json'
    body = JSON.stringify(options.json)
  }

  const response = await fetch(`${baseUrl}${path}`, {
    method: options.method ?? 'GET',
    headers,
    body,
  })

  const text = await response.text()
  let json: T | null = null
  if (text) {
    try {
      json = JSON.parse(text) as T
    } catch {
      json = null
    }
  }

  return { response, text, json }
}

export function expectOk(result: ApiResponse, label: string): void {
  expect(
    result.response.ok,
    `${label}: expected 2xx, got ${result.response.status}: ${result.text.slice(0, 500)}`,
  ).toBe(true)
}

export function expectStatus(result: ApiResponse, statuses: number[], label: string): void {
  expect(
    statuses,
    `${label}: expected one of ${statuses.join(', ')}, got ${result.response.status}: ${result.text.slice(0, 500)}`,
  ).toContain(result.response.status)
}

export async function pgQuery<T = unknown>(query: string, key: string): Promise<ApiResponse<T>> {
  return apiRequest<T>('/pg/query', {
    method: 'POST',
    key,
    json: { query },
  })
}
