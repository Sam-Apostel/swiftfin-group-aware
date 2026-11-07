// JSON-file persistence. A household library (tens of thousands of items at most)
// fits comfortably in memory; writes go to a temp file and are renamed into place.

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const EMPTY_STATE = () => ({
  schema: 1,
  // Jellyfin items by id (movies, series, videos, YouTube episodes).
  library: { items: {}, scannedAt: null },
  // Wikidata lookups, cached between scans: { key: { at, value } }.
  cache: {},
  // The graph the API serves, rebuilt on every scan.
  universes: {},
  // Jellyfin item id -> universe ids.
  itemIndex: {},
  // Suggestions waiting for a yes/no: { id: Review }.
  reviews: {},
  // People's answers, kept across scans: { "universeId|entryId": "accept" | "reject" }.
  decisions: {},
  // YouTube playlists pulled with the Data API: { playlistId: { title, channel, videos, fetchedAt } }.
  playlists: {},
  // Results of LLM calls by input hash, so a rescan doesn't pay twice.
  llm: {},
  lastScan: null,
})

export class Store {
  constructor(dir) {
    this.dir = dir
    this.file = join(dir, 'state.json')
    this.state = EMPTY_STATE()
    this.saveTimer = null
  }

  load() {
    mkdirSync(this.dir, { recursive: true })
    if (existsSync(this.file)) {
      try {
        this.state = { ...EMPTY_STATE(), ...JSON.parse(readFileSync(this.file, 'utf8')) }
      } catch (error) {
        console.error('[store] state.json is unreadable, starting fresh: ' + error.message)
        renameSync(this.file, this.file + '.broken-' + Date.now())
      }
    }
    return this
  }

  saveNow() {
    clearTimeout(this.saveTimer)
    this.saveTimer = null
    const tmp = this.file + '.tmp'
    writeFileSync(tmp, JSON.stringify(this.state))
    renameSync(tmp, this.file)
  }

  /** Coalesces bursts of changes (review answers) into one write. */
  save() {
    if (this.saveTimer) return
    this.saveTimer = setTimeout(() => this.saveNow(), 500)
  }

  cached(key, maxAgeMs) {
    const hit = this.state.cache[key]
    if (!hit) return undefined
    if (maxAgeMs && Date.now() - hit.at > maxAgeMs) return undefined
    return hit.value
  }

  setCached(key, value) {
    this.state.cache[key] = { at: Date.now(), value }
  }

  /** Drops cache entries older than `maxAgeMs` so the file doesn't grow forever. */
  pruneCache(maxAgeMs) {
    const cutoff = Date.now() - maxAgeMs
    for (const [key, hit] of Object.entries(this.state.cache)) {
      if (hit.at < cutoff) delete this.state.cache[key]
    }
  }
}
