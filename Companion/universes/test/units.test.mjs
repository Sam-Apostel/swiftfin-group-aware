import assert from 'node:assert/strict'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { validateCurated, exportCurated } from '../src/curated.mjs'
import { tokenFromHeaders, toLibraryItem, youtubeIdFromPath } from '../src/jellyfin.mjs'
import { parseJson } from '../src/llm.mjs'
import { parsePlaylistIds, Settings } from '../src/settings.mjs'
import { chooseTheme } from '../src/theme.mjs'
import { isoDate, releaseKey, yearOf } from '../src/util.mjs'

test('YouTube ids from yt-dlp and TubeArchivist file names', () => {
  assert.equal(youtubeIdFromPath('/media/yt/Grian/Hermitcraft 11 Ep 1 [dQw4w9WgXcQ].mkv'), 'dQw4w9WgXcQ')
  assert.equal(youtubeIdFromPath('/youtube/UCabc/dQw4w9WgXcQ.mp4'), 'dQw4w9WgXcQ')
  assert.equal(youtubeIdFromPath('/movies/Interstella.mkv'), null)
  assert.equal(youtubeIdFromPath('/movies/Heat (1995).mkv'), null)
  assert.equal(youtubeIdFromPath(null), null)
})

test('Jellyfin items are normalised with provider ids in any case', () => {
  const item = toLibraryItem({ Id: '1', Type: 'Movie', Name: 'Iron Man', ProviderIds: { tmdb: '1726', IMDB: 'tt0371746' }, PremiereDate: '2008-04-30T00:00:00.0000000Z' })
  assert.deepEqual(item.ids, { tmdb: '1726', imdb: 'tt0371746', tvdb: null, youtube: null })
  assert.equal(item.year, 2008)
  assert.equal(item.premiereDate, '2008-04-30')
})

test('tokens from the headers Jellyfin clients send', () => {
  assert.equal(tokenFromHeaders({ 'x-emby-token': 'a' }), 'a')
  assert.equal(tokenFromHeaders({ authorization: 'MediaBrowser Client="Couchfin", Token="b"' }), 'b')
  assert.equal(tokenFromHeaders({ authorization: 'Bearer c' }), 'c')
  assert.equal(tokenFromHeaders({}), null)
})

test('dates, including BCE', () => {
  assert.equal(yearOf('-0753-01-01T00:00:00Z'), -753)
  assert.equal(yearOf('+2019-07-16T00:00:00Z'), 2019)
  assert.equal(isoDate('2019-07-16T00:00:00Z'), '2019-07-16')
  assert.equal(isoDate('-0500-01-01'), null)
  assert.equal(releaseKey('2008-04-30'), 20080430)
})

test('playlist ids from URLs and plain ids', () => {
  assert.deepEqual(
    parsePlaylistIds('https://www.youtube.com/playlist?list=PLabc123def456\nPLxyz7890000, https://youtube.com/watch?v=x&list=PLabc123def456'),
    ['PLabc123def456', 'PLxyz7890000'],
  )
})

test('settings: blank secrets keep their value, "-" clears them', () => {
  const dir = mkdtempSync(join(tmpdir(), 'universes-'))
  const settings = new Settings(dir, { JELLYFIN_URL: 'http://jf:8096' }).load()
  settings.update({ jellyfinApiKey: 'secret', llm: { provider: 'ollama', baseUrl: 'http://ollama:11434/', model: 'qwen3:8b' } })
  settings.update({ jellyfinApiKey: '' })
  assert.equal(settings.value.jellyfinApiKey, 'secret')
  assert.equal(settings.value.llm.baseUrl, 'http://ollama:11434')
  assert.equal(settings.redacted.jellyfinApiKey, true)
  settings.update({ jellyfinApiKey: '-' })
  assert.equal(settings.value.jellyfinApiKey, '')
  assert.equal(new Settings(dir, {}).load().value.llm.provider, 'ollama')
})

test('JSON from chatty models', () => {
  assert.deepEqual(parseJson('Sure! ```json\n{"a": 1}\n```'), { a: 1 })
  assert.equal(parseJson('no json here'), null)
})

test('themes from names, genres and overrides', () => {
  assert.equal(chooseTheme({ name: 'Hermitcraft Season 11', kind: 'creator-collab' }).preset, 'blocky')
  assert.equal(chooseTheme({ name: 'Something', genres: ['Science Fiction', 'Action'] }).preset, 'cosmic')
  assert.equal(chooseTheme({ name: 'Something', genres: ['Drama'] }).preset, 'cinematic')
  assert.equal(chooseTheme({ name: 'Marvel Cinematic Universe', override: { preset: 'mythic' } }).preset, 'mythic')
  assert.equal(chooseTheme({ name: 'Watch later', kind: 'playlist' }).timelineStyle, 'queue')
})

test('curated files are validated and universes export to the same format', () => {
  assert.deepEqual(validateCurated({ id: 'ok-id', name: 'Fine' }), [])
  assert.equal(validateCurated({ id: 'Bad Id', name: 'x', match: { titlePatterns: ['('] } }).length, 2)
  const exported = exportCurated({
    id: 'wd-Q10', name: 'Addams', kind: 'fictional-universe', description: null, wikidata: 'Q10', theme: { preset: 'gothic' },
    entries: [{ title: 'Wednesday', kind: 'series', year: 2022, status: 'confirmed', externalIds: { wikidata: 'Q1', tmdbTv: '119051' }, positions: { chronological: 3 }, lane: null }],
  })
  assert.equal(exported.id, 'q10')
  assert.deepEqual(exported.match, { wikidata: ['Q10'] })
  assert.deepEqual(exported.entries[0], { title: 'Wednesday', kind: 'series', year: 2022, ids: { wikidata: 'Q1', tmdbTv: '119051' }, chronological: 3 })
  assert.deepEqual(validateCurated(exported), [])
})
