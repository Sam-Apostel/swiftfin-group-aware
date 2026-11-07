// Small helpers shared by every module. No dependencies.

import { createHash } from 'node:crypto'

export const VERSION = '1.0.0'
export const USER_AGENT =
  'CouchfinUniverses/' + VERSION + ' (self-hosted; https://github.com/Sam-Apostel/swiftfin-group-aware)'

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

export const trimSlash = (url) => String(url || '').replace(/\/+$/, '')

export function hash(value) {
  return createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex').slice(0, 16)
}

export function slug(text) {
  return String(text || '')
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60)
}

export function chunk(array, size) {
  const out = []
  for (let i = 0; i < array.length; i += size) out.push(array.slice(i, i + size))
  return out
}

export function unique(array) {
  return [...new Set(array.filter((value) => value !== undefined && value !== null && value !== ''))]
}

/** Year from "2019-05-03", "+2019-05-03T00:00:00Z", "-0500-01-01T00:00:00Z" (BCE) or a number. */
export function yearOf(value) {
  if (value === undefined || value === null || value === '') return null
  if (typeof value === 'number') return Number.isFinite(value) ? Math.trunc(value) : null
  const match = /^([+-]?)(\d{1,6})/.exec(String(value).trim())
  if (!match) return null
  const year = Number(match[2])
  return match[1] === '-' ? -year : year
}

/** ISO date (YYYY-MM-DD) for positive years, null for anything unparsable or BCE. */
export function isoDate(value) {
  if (!value) return null
  const match = /^\+?(\d{4})-(\d{2})-(\d{2})/.exec(String(value).trim())
  if (!match) {
    const year = yearOf(value)
    return year && year > 0 ? String(year).padStart(4, '0') + '-01-01' : null
  }
  return match[1] + '-' + match[2] + '-' + match[3]
}

/** Sortable number for a release date: YYYYMMDD, or null. */
export function releaseKey(date) {
  const iso = isoDate(date)
  return iso ? Number(iso.replace(/-/g, '')) : null
}

export class HttpError extends Error {
  constructor(status, message, body) {
    super(message)
    this.status = status
    this.body = body
  }
}

/**
 * fetch + JSON with a timeout and a few retries on 429/5xx/network errors.
 * Returns parsed JSON (or text when the response isn't JSON).
 */
export async function fetchJson(url, options = {}) {
  const { retries = 2, timeoutMs = 60000, ...init } = options
  let lastError
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const response = await fetch(url, {
        ...init,
        headers: { 'User-Agent': USER_AGENT, Accept: 'application/json', ...(init.headers || {}) },
        signal: AbortSignal.timeout(timeoutMs),
      })
      const text = await response.text()
      let data = text
      try {
        data = text ? JSON.parse(text) : null
      } catch {
        // keep text
      }
      if (response.ok) return data
      const error = new HttpError(response.status, (init.method || 'GET') + ' ' + redact(url) + ' -> HTTP ' + response.status, data)
      if (response.status !== 429 && response.status < 500) throw error
      lastError = error
      const retryAfter = Number(response.headers.get('retry-after'))
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? Math.min(retryAfter, 60) * 1000 : 2000 * (attempt + 1))
    } catch (error) {
      if (error instanceof HttpError && error.status !== 429 && error.status < 500) throw error
      lastError = error
      if (attempt < retries) await sleep(2000 * (attempt + 1))
    }
  }
  throw lastError
}

/** Hides API keys in URLs before they end up in logs. */
export function redact(url) {
  return String(url).replace(/([?&](?:key|api_key|apikey|token)=)[^&]+/gi, '$1***')
}

/** Runs `worker` over `items` with at most `limit` in flight. */
export async function mapLimit(items, limit, worker) {
  const results = new Array(items.length)
  let next = 0
  async function run() {
    while (next < items.length) {
      const index = next++
      results[index] = await worker(items[index], index)
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, run))
  return results
}
