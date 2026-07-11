import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const runtimeDir = dirname(dirname(fileURLToPath(import.meta.url)))
const testsDir = dirname(runtimeDir)
export const rootDir = dirname(testsDir)

function parseEnvFile(path: string): Record<string, string> {
  const out: Record<string, string> = {}
  const content = readFileSync(path, 'utf8')

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith('#')) continue
    const idx = line.indexOf('=')
    if (idx === -1) continue

    const key = line.slice(0, idx).trim()
    let value = line.slice(idx + 1).trim()
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1)
    }
    out[key] = value
  }

  return out
}

function loadEnv(): string | undefined {
  const candidates = [
    process.env.TEST_ENV_FILE,
    resolve(runtimeDir, '.env'),
    resolve(testsDir, '.env'),
    resolve(rootDir, '.env'),
  ].filter(Boolean) as string[]

  for (const file of candidates) {
    if (!existsSync(file)) continue
    const values = parseEnvFile(file)
    for (const [key, value] of Object.entries(values)) {
      process.env[key] ??= value
    }
    return file
  }

  return undefined
}

export const loadedEnvFile = loadEnv()

if ((process.env.TEST_TLS_INSECURE ?? 'true') !== 'false') {
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'
}

function firstValue(...values: Array<string | undefined>): string | undefined {
  return values.find((value) => value !== undefined && value !== '')
}

export const config = {
  baseUrl: firstValue(process.env.TEST_SUPABASE_URL, process.env.SUPABASE_PUBLIC_URL)?.replace(/\/+$/, ''),
  anonKey: firstValue(process.env.TEST_ANON_KEY, process.env.SERVICE_SUPABASEANON_KEY, process.env.ANON_KEY),
  serviceRoleKey: firstValue(
    process.env.TEST_SERVICE_ROLE_KEY,
    process.env.SERVICE_SUPABASESERVICE_KEY,
    process.env.SERVICE_ROLE_KEY,
  ),
  publishableKey: firstValue(process.env.TEST_PUBLISHABLE_KEY, process.env.SUPABASE_PUBLISHABLE_KEY),
  secretKey: firstValue(process.env.TEST_SECRET_KEY, process.env.SUPABASE_SECRET_KEY),
  dashboardUsername: firstValue(process.env.TEST_DASHBOARD_USERNAME, process.env.SERVICE_USER_ADMIN, process.env.DASHBOARD_USERNAME),
  dashboardPassword: firstValue(process.env.TEST_DASHBOARD_PASSWORD, process.env.SERVICE_PASSWORD_ADMIN, process.env.DASHBOARD_PASSWORD),
  runId: firstValue(process.env.TEST_RUN_ID, `${Date.now()}-${Math.random().toString(16).slice(2)}`)!,
}

export function requireBaseUrl(): string {
  if (!config.baseUrl) {
    throw new Error('Missing TEST_SUPABASE_URL or SUPABASE_PUBLIC_URL')
  }
  return config.baseUrl
}

export function requireAnonKey(): string {
  if (!config.anonKey) {
    throw new Error('Missing TEST_ANON_KEY, SERVICE_SUPABASEANON_KEY or ANON_KEY')
  }
  return config.anonKey
}

export function requireServiceRoleKey(): string {
  if (!config.serviceRoleKey) {
    throw new Error('Missing TEST_SERVICE_ROLE_KEY, SERVICE_SUPABASESERVICE_KEY or SERVICE_ROLE_KEY')
  }
  return config.serviceRoleKey
}

export function adminKey(): string {
  return config.secretKey || requireServiceRoleKey()
}
