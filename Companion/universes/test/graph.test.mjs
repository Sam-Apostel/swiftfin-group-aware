import assert from 'node:assert/strict'
import { test } from 'node:test'
import { buildGraph, pickRoots, summaryUniverse } from '../src/graph.mjs'
import { addamsAndAvatar } from './fixtures.mjs'

function graph(extra = {}) {
  const data = addamsAndAvatar()
  const roots = pickRoots({ libraryWorks: [...data.resolved.values()], edges: data.edges, entities: data.entities })
  return { data, roots, ...buildGraph({ ...data, roots, curated: extra.curated || [], ...extra }) }
}

test('roots come from universe, franchise and shared-character relations', () => {
  const { roots } = graph()
  const byId = Object.fromEntries(roots.map((root) => [root.qid, root.kind]))
  assert.equal(byId.Q10, 'fictional-universe')
  assert.equal(byId.Q30, 'franchise')
  // Wednesday Addams links two library works, so she is a candidate too.
  assert.equal(byId.Q11, 'character')
})

test('Wednesday leads to the Addams Family films, including one not in the library', () => {
  const { universes, itemIndex } = graph()
  const addams = universes['wd-Q10']
  assert.ok(addams)
  assert.deepEqual(addams.entries.map((entry) => entry.title), ['The Addams Family', 'Addams Family Values', 'Wednesday'])
  const values = addams.entries.find((entry) => entry.title === 'Addams Family Values')
  assert.equal(values.inLibrary, false)
  assert.deepEqual(values.seerr, { mediaType: 'movie', tmdbId: 2758, status: null })
  assert.ok(itemIndex['jf-wed'].includes('wd-Q10'))
  assert.deepEqual(addams.relations, [{ from: 'wd:Q2', to: 'wd:Q3', type: 'sequel' }])
  assert.equal(addams.theme.preset, 'gothic')
})

test('the Avatar franchise surfaces the Kyoshi novel and leaves episodes out', () => {
  const { universes } = graph()
  const avatar = universes['wd-Q30']
  const titles = avatar.entries.map((entry) => entry.title)
  assert.ok(titles.includes('The Rise of Kyoshi'))
  assert.ok(!titles.includes('Episode 1'))
  const kyoshi = avatar.entries.find((entry) => entry.title === 'The Rise of Kyoshi')
  assert.equal(kyoshi.kind, 'book')
  assert.match(kyoshi.imageUrl, /covers\.openlibrary\.org\/b\/isbn\/9781419735042/)
})

test('a character universe inside a bigger universe is dropped', () => {
  const { universes } = graph()
  assert.equal(universes['wd-Q11'], undefined)
})

test('documentaries land on the history timeline and share a subject universe', () => {
  const { universes } = graph()
  const history = universes.history
  assert.ok(history)
  const rome = history.entries.find((entry) => entry.title === 'Rome: Rise and Fall')
  assert.deepEqual([rome.positions.historical.start, rome.positions.historical.end], [-753, 476])
  assert.ok(history.timelines.includes('historical'))
  assert.equal(universes['subject-Q50'].counts.inLibrary, 2)
  assert.ok(universes['subject-Q50'].parentIds.includes('history'))
})

test('curated title patterns build a creator universe with a lane per channel', () => {
  const curated = [{ id: 'hc11', name: 'Hermitcraft Season 11', kind: 'creator-collab', lanes: 'channel', theme: { preset: 'blocky' }, match: { titlePatterns: ['hermitcraft\\s*(season\\s*)?11\\b'] } }]
  const { universes } = graph({ curated })
  const hc = universes['curated-hc11']
  assert.equal(hc.entries.length, 2)
  assert.deepEqual(hc.lanes.sort(), ['Grian', 'Mumbo Jumbo'])
  assert.ok(hc.timelines.includes('lanes'))
  assert.equal(hc.theme.preset, 'blocky')
})

test('AI suggestions below the threshold wait for review, and answers stick', () => {
  const videoTags = new Map([
    ['jf-kz', { universes: [{ name: 'Kurzgesagt history', confidence: 0.6, reason: 'Series about history' }], historical: { start: -10000, end: -3000, label: 'First civilizations', confidence: 0.9 }, nonFiction: true }],
    ['jf-hc1', { universes: [{ name: 'Kurzgesagt history', confidence: 0.4, reason: 'unsure' }] }],
    ['jf-hc2', { universes: [{ name: 'Kurzgesagt history', confidence: 0.9, reason: 'sure' }] }],
  ])
  const first = graph({ videoTags })
  const kz = first.universes.history.entries.find((entry) => entry.id === 'yt:abcDEF12345')
  assert.equal(kz.positions.historical.start, -10000)
  const ai = first.universes['ai-kurzgesagt-history']
  assert.ok(ai)
  assert.equal(ai.counts.suggested, 2)
  assert.equal(ai.entries.find((entry) => entry.id === 'yt:BBBBBBBBBB2').status, 'confirmed')
  assert.equal(Object.keys(first.reviews).filter((id) => id.startsWith('ai-kurzgesagt-history|')).length, 2)

  const decisions = { 'ai-kurzgesagt-history|yt:abcDEF12345': 'accept', 'ai-kurzgesagt-history|yt:AAAAAAAAAA1': 'reject' }
  const second = graph({ videoTags, decisions })
  const after = second.universes['ai-kurzgesagt-history']
  assert.deepEqual(after.entries.map((entry) => [entry.id, entry.status]).sort(), [['yt:BBBBBBBBBB2', 'confirmed'], ['yt:abcDEF12345', 'confirmed']])
  assert.equal(Object.keys(second.reviews).filter((id) => id.startsWith('ai-')).length, 0)
})

test('playlists become backlogs in playlist order, with ghosts for undownloaded videos', () => {
  const playlists = {
    PL1: { title: 'Watch later, really', channel: 'me', videos: [
      { id: 'abcDEF12345', title: 'The First Civilizations', channel: 'Kurzgesagt', publishedAt: '2024-01-01T00:00:00Z' },
      { id: 'ZZZZZZZZZZ9', title: 'Something else', channel: 'Other', publishedAt: '2023-01-01T00:00:00Z' },
    ] },
  }
  const { universes } = graph({ playlists })
  const backlog = universes['yt-PL1']
  assert.equal(backlog.kind, 'playlist')
  assert.equal(backlog.theme.preset, 'backlog')
  const downloaded = backlog.entries.find((entry) => entry.id === 'yt:abcDEF12345')
  assert.equal(downloaded.jellyfinItemId, 'jf-kz')
  assert.equal(downloaded.positions.chronological, 1)
  const ghost = backlog.entries.find((entry) => entry.id === 'yt:ZZZZZZZZZZ9')
  assert.equal(ghost.inLibrary, false)
  assert.equal(ghost.links[0].url, 'https://www.youtube.com/watch?v=ZZZZZZZZZZ9')
  assert.equal(backlog.orderSource, 'playlist')
})

test('AI chronology sets in-universe order', () => {
  const chronology = new Map([['wd-Q10', ['wd:Q3', 'wd:Q2', 'wd:Q1']]])
  const { universes } = graph({ chronology })
  const order = Object.fromEntries(universes['wd-Q10'].entries.map((entry) => [entry.title, entry.positions.chronological]))
  assert.deepEqual(order, { 'Addams Family Values': 1, 'The Addams Family': 2, Wednesday: 3 })
  assert.ok(universes['wd-Q10'].timelines.includes('chronological'))
})

test('summaries carry what list screens need', () => {
  const { universes } = graph()
  const summary = summaryUniverse(universes['wd-Q10'])
  assert.deepEqual(summary.span, { from: 1991, to: 2022 })
  assert.deepEqual(summary.sampleItemIds, ['jf-af', 'jf-wed'])
  assert.equal(summary.entries, undefined)
})
