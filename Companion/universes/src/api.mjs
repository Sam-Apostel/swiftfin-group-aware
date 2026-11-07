// HTTP: the JSON API Couchfin uses (/api/v1, Jellyfin token required) and the
// settings page (everything else; umbrelOS puts its own login in front of it).

import { Jellyfin, tokenFromHeaders } from './jellyfin.mjs'
import { exportCurated } from './curated.mjs'
import { summaryEntry, summaryUniverse } from './graph.mjs'
import { renderPage } from './ui.mjs'
import { VERSION } from './util.mjs'

const TOKEN_TTL = 10 * 60 * 1000
const MAX_BODY = 256 * 1024

export function createHandler({ store, settings, pipeline, logs }) {
  const tokens = new Map()

  async function authenticate(req) {
    const token = tokenFromHeaders(req.headers)
    if (!token) return null
    const cached = tokens.get(token)
    if (cached && cached.until > Date.now()) return cached.user
    const value = settings.value
    try {
      const user = await new Jellyfin(value.jellyfinUrl, value.jellyfinApiKey).whoAmI(token)
      tokens.set(token, { user, until: Date.now() + TOKEN_TTL })
      if (tokens.size > 500) tokens.delete(tokens.keys().next().value)
      return user
    } catch {
      return null
    }
  }

  function json(res, status, body) {
    const text = JSON.stringify(body)
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(text) })
    res.end(text)
  }

  function html(res, status, body) {
    res.writeHead(status, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'Content-Security-Policy': "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self' data:",
      'X-Frame-Options': 'SAMEORIGIN',
    })
    res.end(body)
  }

  async function readBody(req) {
    const chunks = []
    let size = 0
    for await (const chunk of req) {
      size += chunk.length
      if (size > MAX_BODY) throw Object.assign(new Error('body too large'), { status: 413 })
      chunks.push(chunk)
    }
    const text = Buffer.concat(chunks).toString('utf8')
    if (!text) return {}
    if ((req.headers['content-type'] || '').includes('application/json')) return JSON.parse(text)
    return Object.fromEntries(new URLSearchParams(text))
  }

  function status() {
    const value = settings.value
    return {
      service: 'couchfin-universes',
      version: VERSION,
      scan: pipeline.status,
      lastScan: store.state.lastScan,
      counts: {
        libraryItems: Object.keys(store.state.library.items).length,
        universes: Object.keys(store.state.universes).length,
        reviews: Object.keys(store.state.reviews).length,
      },
      configured: {
        jellyfin: Boolean(value.jellyfinUrl && value.jellyfinApiKey),
        seerr: Boolean(value.seerrUrl && value.seerrApiKey),
        ai: value.llm.provider !== 'none',
        aiProvider: value.llm.provider,
        youtube: Boolean(value.youtube.apiKey),
      },
    }
  }

  /** Applies a review answer without the scan's inputs (after a restart). */
  function applyDecisionInPlace(universeId, entryId, decision) {
    const universe = store.state.universes[universeId]
    if (!universe) return
    const index = universe.entries.findIndex((entry) => entry.id === entryId)
    if (index === -1) return
    if (decision === 'reject') {
      const [entry] = universe.entries.splice(index, 1)
      if (entry.jellyfinItemId) {
        store.state.itemIndex[entry.jellyfinItemId] = (store.state.itemIndex[entry.jellyfinItemId] || []).filter((id) => id !== universeId)
      }
    } else {
      universe.entries[index] = { ...universe.entries[index], status: 'confirmed', confidence: 1 }
    }
    universe.counts = {
      entries: universe.entries.length,
      inLibrary: universe.entries.filter((entry) => entry.inLibrary).length,
      suggested: universe.entries.filter((entry) => entry.status === 'suggested').length,
    }
    delete store.state.reviews[universeId + '|' + entryId]
    store.save()
  }

  function decide(universeId, entryId, decision) {
    store.state.decisions[universeId + '|' + entryId] = decision
    if (!pipeline.rebuild()) applyDecisionInPlace(universeId, entryId, decision)
    store.save()
  }

  async function api(req, res, url) {
    const path = url.pathname.replace(/\/+$/, '')

    // Unauthenticated: lets Couchfin find this service next to Jellyfin.
    if (path === '/api/v1/ping') return json(res, 200, { service: 'couchfin-universes', version: VERSION })

    const user = await authenticate(req)
    if (!user) return json(res, 401, { error: 'Sign in to Jellyfin first: send the Jellyfin access token.' })

    if (req.method === 'GET' && path === '/api/v1/status') return json(res, 200, status())

    if (req.method === 'GET' && path === '/api/v1/universes') {
      const kind = url.searchParams.get('kind')
      const list = Object.values(store.state.universes)
        .filter((universe) => !kind || universe.kind === kind)
        .map(summaryUniverse)
        .sort((a, b) => b.counts.inLibrary - a.counts.inLibrary || b.counts.entries - a.counts.entries || a.name.localeCompare(b.name))
      return json(res, 200, { universes: list })
    }

    let match = /^\/api\/v1\/universes\/([^/]+)$/.exec(path)
    if (req.method === 'GET' && match) {
      const universe = store.state.universes[decodeURIComponent(match[1])]
      return universe ? json(res, 200, universe) : json(res, 404, { error: 'No such universe' })
    }

    match = /^\/api\/v1\/universes\/([^/]+)\/export$/.exec(path)
    if (req.method === 'GET' && match) {
      const universe = store.state.universes[decodeURIComponent(match[1])]
      return universe ? json(res, 200, exportCurated(universe)) : json(res, 404, { error: 'No such universe' })
    }

    match = /^\/api\/v1\/items\/([^/]+)\/universes$/.exec(path)
    if (req.method === 'GET' && match) {
      const ids = [decodeURIComponent(match[1]), ...url.searchParams.getAll('alsoId')]
      const universeIds = [...new Set(ids.flatMap((id) => store.state.itemIndex[id] || []))]
      const list = universeIds.map((id) => store.state.universes[id]).filter(Boolean)
      // Most specific first: the smallest universe that holds the item is the most telling.
      list.sort((a, b) => (a.id === 'history') - (b.id === 'history') || a.entries.length - b.entries.length || b.parentIds.length - a.parentIds.length)
      return json(res, 200, {
        universes: list.map((universe) => {
          const position = universe.entries.findIndex((entry) => ids.includes(entry.jellyfinItemId))
          return { ...summaryUniverse(universe), position: position === -1 ? null : position + 1 }
        }),
      })
    }

    if (req.method === 'GET' && path === '/api/v1/reviews') {
      return json(res, 200, { reviews: Object.values(store.state.reviews).sort((a, b) => b.confidence - a.confidence) })
    }

    match = /^\/api\/v1\/reviews\/(.+)$/.exec(path)
    if (req.method === 'POST' && match) {
      const body = await readBody(req)
      const id = decodeURIComponent(match[1])
      const [universeId, ...rest] = id.split('|')
      const entryId = rest.join('|')
      if (!['accept', 'reject'].includes(body.decision)) return json(res, 400, { error: 'decision must be accept or reject' })
      if (!store.state.universes[universeId]?.entries.some((entry) => entry.id === entryId)) return json(res, 404, { error: 'No such suggestion' })
      decide(universeId, entryId, body.decision)
      return json(res, 200, { ok: true })
    }

    // "Not part of this universe" from an item's menu: the same as rejecting a suggestion.
    match = /^\/api\/v1\/universes\/([^/]+)\/entries\/(.+)\/decision$/.exec(path)
    if (req.method === 'POST' && match) {
      const body = await readBody(req)
      if (!['accept', 'reject'].includes(body.decision)) return json(res, 400, { error: 'decision must be accept or reject' })
      decide(decodeURIComponent(match[1]), decodeURIComponent(match[2]), body.decision)
      return json(res, 200, { ok: true })
    }

    if (req.method === 'POST' && path === '/api/v1/scan') {
      if (!user.isAdmin) return json(res, 403, { error: 'Only Jellyfin administrators can start a scan.' })
      pipeline.scan('requested from Couchfin')
      return json(res, 202, { ok: true, scan: pipeline.status })
    }

    return json(res, 404, { error: 'Not found' })
  }

  async function ui(req, res, url) {
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '')) {
      return html(res, 200, renderPage({ status: status(), settings: settings.redacted, logs: logs.lines(), universes: Object.values(store.state.universes).map(summaryUniverse), notice: url.searchParams.get('notice') }))
    }
    if (req.method === 'GET' && url.pathname === '/ui/status') return json(res, 200, { ...status(), logs: logs.lines().slice(-40) })
    if (req.method === 'POST' && url.pathname === '/settings') {
      const form = await readBody(req)
      settings.update({
        jellyfinUrl: form.jellyfinUrl,
        jellyfinApiKey: form.jellyfinApiKey,
        seerrUrl: form.seerrUrl,
        seerrApiKey: form.seerrApiKey,
        llm: { provider: form.llmProvider, baseUrl: form.llmBaseUrl, model: form.llmModel, apiKey: form.llmApiKey, maxCallsPerScan: form.llmMaxCalls },
        youtube: { apiKey: form.youtubeApiKey, playlists: form.youtubePlaylists },
        wikidata: { enabled: form.wikidata === 'on' },
        scanIntervalHours: form.scanIntervalHours,
      })
      let notice = 'Saved.'
      const value = settings.value
      if (value.jellyfinApiKey) {
        try {
          await new Jellyfin(value.jellyfinUrl, value.jellyfinApiKey).ping()
          notice = 'Saved. Jellyfin is connected.'
          if (!store.state.lastScan && pipeline.status.state !== 'running') {
            pipeline.scan('first run')
            notice += ' The first scan has started.'
          }
        } catch (error) {
          notice = 'Saved, but Jellyfin did not answer: ' + error.message
        }
      }
      res.writeHead(303, { Location: '/?notice=' + encodeURIComponent(notice) })
      return res.end()
    }
    if (req.method === 'POST' && url.pathname === '/scan') {
      pipeline.scan('manual')
      res.writeHead(303, { Location: '/?notice=' + encodeURIComponent('Scan started.') })
      return res.end()
    }
    if (req.method === 'POST' && url.pathname === '/reviews') {
      const form = await readBody(req)
      const [universeId, ...rest] = String(form.id || '').split('|')
      if (['accept', 'reject'].includes(form.decision) && universeId) decide(universeId, rest.join('|'), form.decision)
      res.writeHead(303, { Location: '/#reviews' })
      return res.end()
    }
    if (req.method === 'GET' && url.pathname === '/ui/reviews') {
      return json(res, 200, { reviews: Object.values(store.state.reviews).map((review) => ({ ...review, entry: summaryEntry(review.entry) })) })
    }
    return html(res, 404, '<p>Not found</p>')
  }

  return async function handler(req, res) {
    const url = new URL(req.url, 'http://localhost')
    try {
      if (url.pathname.startsWith('/api/')) return await api(req, res, url)
      return await ui(req, res, url)
    } catch (error) {
      console.error('[http] ' + req.method + ' ' + url.pathname + ': ' + error.stack)
      if (!res.headersSent) json(res, error.status || 500, { error: error.status ? error.message : 'Something went wrong' })
      else res.end()
    }
  }
}
