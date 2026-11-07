// End to end without the internet: a fake Jellyfin and a fake Ollama, Wikidata off.

import assert from 'node:assert/strict'
import { mkdtempSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { createHandler } from '../src/api.mjs'
import { Pipeline } from '../src/pipeline.mjs'
import { Settings } from '../src/settings.mjs'
import { Store } from '../src/store.mjs'

const items = [
  { Id: 'hc1', Type: 'Episode', Name: 'Hermitcraft 11: Episode 1', SeriesName: 'Grian', Path: '/yt/Grian/ep [AAAAAAAAAA1].mkv', PremiereDate: '2025-03-01T00:00:00Z' },
  { Id: 'hc2', Type: 'Episode', Name: 'HermitCraft Season 11 Ep 1', SeriesName: 'Mumbo Jumbo', Path: '/yt/Mumbo/ep [BBBBBBBBBB2].mkv', PremiereDate: '2025-03-02T00:00:00Z' },
  { Id: 'kz', Type: 'Episode', Name: 'The First Civilizations', SeriesName: 'Kurzgesagt', Path: '/yt/Kurzgesagt/x [abcDEF12345].mkv', PremiereDate: '2024-01-01T00:00:00Z' },
  { Id: 'tv', Type: 'Episode', Name: 'Pilot', SeriesName: 'Some Show', Path: '/tv/Some Show/S01E01.mkv' },
]

const servers = []
let base

function listen(handler) {
  return new Promise((resolve) => {
    const server = createServer(handler).listen(0, '127.0.0.1', () => resolve('http://127.0.0.1:' + server.address().port))
    servers.push(server)
  })
}

const call = async (path, { token = 'good', method = 'GET', body } = {}) => {
  const response = await fetch(base + path, {
    method,
    headers: { ...(token ? { 'X-Emby-Token': token } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    redirect: 'manual',
  })
  const text = await response.text()
  return { status: response.status, body: text.startsWith('{') ? JSON.parse(text) : text }
}

let pipeline
before(async () => {
  const jellyfin = await listen((req, res) => {
    res.setHeader('Content-Type', 'application/json')
    const token = /Token="([^"]+)"/.exec(req.headers.authorization || '')?.[1]
    if (req.url.startsWith('/Users/Me')) {
      if (token === 'good') return res.end(JSON.stringify({ Id: 'u1', Name: 'Sam', Policy: { IsAdministrator: true } }))
      if (token === 'guest') return res.end(JSON.stringify({ Id: 'u2', Name: 'Guest', Policy: { IsAdministrator: false } }))
      res.statusCode = 401
      return res.end('{}')
    }
    if (req.url.startsWith('/Items') && token === 'server-key') return res.end(JSON.stringify({ Items: items, TotalRecordCount: items.length }))
    res.statusCode = 404
    res.end('{}')
  })
  const ollama = await listen(async (req, res) => {
    let body = ''
    for await (const chunk of req) body += chunk
    const request = JSON.parse(body)
    const user = request.messages[1].content
    let answer = { universes: [], historical: { applies: false, start: 0, end: 0, label: '', confidence: 0 } }
    if (user.includes('First Civilizations')) {
      answer = { universes: [{ name: 'Hermitcraft Season 11', confidence: 0.3, reason: 'a stretch' }], historical: { applies: true, start: -10000, end: -3000, label: 'First civilizations', confidence: 0.9 } }
    }
    res.setHeader('Content-Type', 'application/json')
    res.end(JSON.stringify({ message: { role: 'assistant', content: JSON.stringify(answer) } }))
  })

  const dir = mkdtempSync(join(tmpdir(), 'universes-api-'))
  const settings = new Settings(dir, {}).load()
  settings.update({ jellyfinUrl: jellyfin, jellyfinApiKey: 'server-key', wikidata: { enabled: false }, llm: { provider: 'ollama', baseUrl: ollama, model: 'test' } })
  const store = new Store(dir).load()
  const lines = []
  const logs = { lines: () => lines }
  pipeline = new Pipeline({ store, settings, curatedDirs: [new URL('../universes', import.meta.url).pathname], log: (line) => lines.push(line) })
  base = await listen(createHandler({ store, settings, pipeline, logs }))
})

after(() => servers.forEach((server) => server.close()))

test('ping is open, everything else needs a Jellyfin token', async () => {
  assert.equal((await call('/api/v1/ping', { token: null })).body.service, 'couchfin-universes')
  assert.equal((await call('/api/v1/universes', { token: null })).status, 401)
  assert.equal((await call('/api/v1/universes', { token: 'bad' })).status, 401)
})

test('only admins start scans', async () => {
  assert.equal((await call('/api/v1/scan', { token: 'guest', method: 'POST' })).status, 403)
  assert.equal((await call('/api/v1/scan', { method: 'POST' })).status, 202)
  await pipeline.running
  const status = (await call('/api/v1/status')).body
  assert.equal(status.scan.state, 'idle', JSON.stringify(status.scan))
  assert.equal(status.counts.libraryItems, 3, 'ordinary TV episodes are skipped')
})

test('a scan builds the creator universe and the history timeline', async () => {
  const { universes } = (await call('/api/v1/universes')).body
  const ids = universes.map((universe) => universe.id)
  assert.ok(ids.includes('curated-hermitcraft-season-11'))
  assert.ok(ids.includes('curated-hermitcraft'))
  assert.ok(ids.includes('history'))

  const season = (await call('/api/v1/universes/curated-hermitcraft-season-11')).body
  // The AI's (unsure) suggestion is in there too, marked as such, until someone answers it.
  assert.deepEqual(season.lanes.sort(), ['Grian', 'Kurzgesagt', 'Mumbo Jumbo'])
  assert.equal(season.entries.find((entry) => entry.jellyfinItemId === 'kz').status, 'suggested')
  assert.ok(season.parentIds.includes('curated-hermitcraft'))

  const history = (await call('/api/v1/universes/history')).body
  assert.equal(history.entries[0].positions.historical.label, 'First civilizations')
})

test('reviews, then item lookup', async () => {
  const { reviews } = (await call('/api/v1/reviews')).body
  const review = reviews.find((r) => r.entry.jellyfinItemId === 'kz' && r.universeId === 'curated-hermitcraft-season-11')
  assert.ok(review, JSON.stringify(reviews))
  assert.equal((await call('/api/v1/reviews/' + encodeURIComponent(review.id), { method: 'POST', body: { decision: 'nope' } })).status, 400)
  assert.equal((await call('/api/v1/reviews/' + encodeURIComponent(review.id), { method: 'POST', body: { decision: 'reject' } })).status, 200)

  const season = (await call('/api/v1/universes/curated-hermitcraft-season-11')).body
  assert.ok(!season.entries.some((entry) => entry.jellyfinItemId === 'kz'))
  assert.ok(!(await call('/api/v1/reviews')).body.reviews.some((r) => r.id === review.id))

  const lookup = (await call('/api/v1/items/hc1/universes')).body
  assert.equal(lookup.universes[0].id, 'curated-hermitcraft-season-11', 'most specific universe first')
  assert.equal(lookup.universes[0].position, 1)
})

test('the settings page renders without secrets', async () => {
  const page = await call('/', { token: null })
  assert.equal(page.status, 200)
  assert.match(page.body, /Couchfin Universes/)
  assert.ok(!page.body.includes('server-key'))
})
