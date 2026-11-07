// Settings: environment defaults (set by umbrelOS) overlaid with what the owner
// saved in the web UI (data/settings.json). Secrets never leave this file except
// to the service they belong to.

import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { trimSlash } from './util.mjs'

export const LLM_PROVIDERS = ['none', 'ollama', 'openai-compatible', 'anthropic']
export const DEFAULT_ANTHROPIC_MODEL = 'claude-opus-5-5'

export function defaultsFromEnv(env = process.env) {
  return {
    jellyfinUrl: trimSlash(env.JELLYFIN_URL || 'http://jellyfin_server_1:8096'),
    jellyfinApiKey: env.JELLYFIN_API_KEY || '',
    seerrUrl: trimSlash(env.SEERR_URL || ''),
    seerrApiKey: env.SEERR_API_KEY || '',
    llm: {
      provider: LLM_PROVIDERS.includes(env.LLM_PROVIDER) ? env.LLM_PROVIDER : 'none',
      baseUrl: trimSlash(env.LLM_BASE_URL || ''),
      model: env.LLM_MODEL || '',
      apiKey: env.LLM_API_KEY || '',
      // Upper bound per scan, so a big new library can't run up a bill (or keep a local GPU busy for a day).
      maxCallsPerScan: Number(env.LLM_MAX_CALLS || 150),
    },
    youtube: {
      apiKey: env.YOUTUBE_API_KEY || '',
      playlists: [],
    },
    wikidata: { enabled: env.WIKIDATA !== 'off' },
    scanIntervalHours: Number(env.SCAN_INTERVAL_HOURS || 12),
  }
}

export class Settings {
  constructor(dir, env = process.env) {
    this.file = join(dir, 'settings.json')
    this.env = env
    this.saved = {}
  }

  load() {
    if (existsSync(this.file)) {
      try {
        this.saved = JSON.parse(readFileSync(this.file, 'utf8'))
      } catch (error) {
        console.error('[settings] settings.json is unreadable: ' + error.message)
      }
    }
    return this
  }

  /** The effective settings: saved values win over the environment, empty strings don't. */
  get value() {
    const base = defaultsFromEnv(this.env)
    const saved = this.saved || {}
    const pick = (savedValue, fallback) => (savedValue === undefined || savedValue === '' ? fallback : savedValue)
    return {
      jellyfinUrl: trimSlash(pick(saved.jellyfinUrl, base.jellyfinUrl)),
      jellyfinApiKey: pick(saved.jellyfinApiKey, base.jellyfinApiKey),
      seerrUrl: trimSlash(pick(saved.seerrUrl, base.seerrUrl)),
      seerrApiKey: pick(saved.seerrApiKey, base.seerrApiKey),
      llm: {
        provider: pick(saved.llm?.provider, base.llm.provider),
        baseUrl: trimSlash(pick(saved.llm?.baseUrl, base.llm.baseUrl)),
        model: pick(saved.llm?.model, base.llm.model),
        apiKey: pick(saved.llm?.apiKey, base.llm.apiKey),
        maxCallsPerScan: Number(pick(saved.llm?.maxCallsPerScan, base.llm.maxCallsPerScan)),
      },
      youtube: {
        apiKey: pick(saved.youtube?.apiKey, base.youtube.apiKey),
        playlists: Array.isArray(saved.youtube?.playlists) ? saved.youtube.playlists : base.youtube.playlists,
      },
      wikidata: { enabled: saved.wikidata?.enabled ?? base.wikidata.enabled },
      scanIntervalHours: Number(pick(saved.scanIntervalHours, base.scanIntervalHours)),
    }
  }

  /**
   * Applies a partial update from the web UI. Secret fields left blank keep their
   * current value; the literal "-" clears them.
   */
  update(patch) {
    const next = structuredClone(this.saved || {})
    const secret = (current, value) => (value === undefined || value === '' ? current : value === '-' ? '' : value)
    if (patch.jellyfinUrl !== undefined) next.jellyfinUrl = trimSlash(patch.jellyfinUrl)
    if (patch.jellyfinApiKey !== undefined) next.jellyfinApiKey = secret(next.jellyfinApiKey, patch.jellyfinApiKey)
    if (patch.seerrUrl !== undefined) next.seerrUrl = trimSlash(patch.seerrUrl)
    if (patch.seerrApiKey !== undefined) next.seerrApiKey = secret(next.seerrApiKey, patch.seerrApiKey)
    if (patch.llm) {
      next.llm = { ...(next.llm || {}) }
      if (patch.llm.provider !== undefined && LLM_PROVIDERS.includes(patch.llm.provider)) next.llm.provider = patch.llm.provider
      if (patch.llm.baseUrl !== undefined) next.llm.baseUrl = trimSlash(patch.llm.baseUrl)
      if (patch.llm.model !== undefined) next.llm.model = patch.llm.model.trim()
      if (patch.llm.apiKey !== undefined) next.llm.apiKey = secret(next.llm.apiKey, patch.llm.apiKey)
      if (patch.llm.maxCallsPerScan !== undefined && Number.isFinite(Number(patch.llm.maxCallsPerScan))) {
        next.llm.maxCallsPerScan = Math.max(0, Math.min(5000, Number(patch.llm.maxCallsPerScan)))
      }
    }
    if (patch.youtube) {
      next.youtube = { ...(next.youtube || {}) }
      if (patch.youtube.apiKey !== undefined) next.youtube.apiKey = secret(next.youtube.apiKey, patch.youtube.apiKey)
      if (patch.youtube.playlists !== undefined) next.youtube.playlists = parsePlaylistIds(patch.youtube.playlists)
    }
    if (patch.wikidata?.enabled !== undefined) next.wikidata = { enabled: Boolean(patch.wikidata.enabled) }
    if (patch.scanIntervalHours !== undefined && Number.isFinite(Number(patch.scanIntervalHours))) {
      next.scanIntervalHours = Math.max(1, Math.min(168, Number(patch.scanIntervalHours)))
    }
    this.saved = next
    const tmp = this.file + '.tmp'
    writeFileSync(tmp, JSON.stringify(next, null, 2), { mode: 0o600 })
    renameSync(tmp, this.file)
  }

  /** Settings for display: secrets reduced to whether they're set. */
  get redacted() {
    const value = this.value
    return {
      ...value,
      jellyfinApiKey: Boolean(value.jellyfinApiKey),
      seerrApiKey: Boolean(value.seerrApiKey),
      llm: { ...value.llm, apiKey: Boolean(value.llm.apiKey) },
      youtube: { ...value.youtube, apiKey: Boolean(value.youtube.apiKey) },
    }
  }
}

/** Accepts playlist ids or URLs, one per line or comma separated. */
export function parsePlaylistIds(input) {
  const parts = Array.isArray(input) ? input : String(input || '').split(/[\s,]+/)
  const ids = []
  for (const part of parts) {
    const text = String(part).trim()
    if (!text) continue
    const fromUrl = /[?&]list=([A-Za-z0-9_-]+)/.exec(text)
    const id = fromUrl ? fromUrl[1] : /^[A-Za-z0-9_-]{10,64}$/.test(text) ? text : null
    if (id && !ids.includes(id)) ids.push(id)
  }
  return ids
}
