// Builds the universe graph from everything the pipeline gathered. Pure: no I/O,
// so it's easy to test and cheap to rebuild after every review answer.

import { chooseTheme } from './theme.mjs'
import { isCharacter, isGrouper, kindOf, SKIP_TYPES } from './wikidata.mjs'
import { isoDate, releaseKey, slug, unique, yearOf } from './util.mjs'

export const SUGGESTION_THRESHOLD = 0.8

const KIND_RANK = { 'fictional-universe': 0, franchise: 1, series: 2, 'creator-collab': 3, character: 4, 'non-fiction': 5, playlist: 6 }

const JELLYFIN_KIND = { Movie: 'movie', Series: 'series', Episode: 'video', Video: 'video', MusicVideo: 'video' }

/** The universe-like targets worth expanding, from the library works' relations. */
export function pickRoots({ libraryWorks, edges, entities }) {
  const roots = new Map()
  const characterUse = new Map()
  const add = (target, kind, via) => {
    const entity = entities.get(target)
    if (!entity || entity.types.some((type) => SKIP_TYPES.has(type))) return
    const current = roots.get(target)
    if (!current || KIND_RANK[kind] < KIND_RANK[current.kind]) roots.set(target, { qid: target, kind, via })
  }
  for (const work of libraryWorks) {
    for (const edge of edges.get(work) || []) {
      const target = entities.get(edge.target)
      if (!target) continue
      switch (edge.prop) {
        case 'P1434':
          add(edge.target, 'fictional-universe', edge.prop)
          break
        case 'P8345':
          add(edge.target, 'franchise', edge.prop)
          break
        case 'P179':
          add(edge.target, 'series', edge.prop)
          break
        case 'P361':
          if (isGrouper(target.types)) add(edge.target, 'franchise', edge.prop)
          break
        case 'P144':
          if (isCharacter(target.types)) add(edge.target, 'character', edge.prop)
          else add(edge.target, 'franchise', edge.prop)
          break
        case 'P674':
          if (!characterUse.has(edge.target)) characterUse.set(edge.target, new Set())
          characterUse.get(edge.target).add(work)
          break
      }
    }
  }
  // A character becomes a universe when they connect two works in the library.
  for (const [character, works] of characterUse) {
    if (works.size >= 2 && !roots.has(character)) add(character, 'character', 'P674')
  }
  return [...roots.values()]
}

function wikidataLinks(entity) {
  const links = [{ kind: 'wikidata', url: 'https://www.wikidata.org/wiki/' + entity.id }]
  if (entity.wikipedia) links.push({ kind: 'wikipedia', url: entity.wikipedia })
  return links
}

function commonsImage(file) {
  if (!file) return null
  const name = decodeURIComponent(String(file).replace(/^.*Special:FilePath\//, ''))
  return 'https://commons.wikimedia.org/wiki/Special:FilePath/' + encodeURIComponent(name) + '?width=400'
}

function historicalSpan(dates) {
  const starts = []
  const ends = []
  for (const date of dates) {
    for (const value of [date.start, date.pointInTime, date.inception, date.published]) {
      const year = yearOf(value)
      if (year !== null) starts.push(year)
    }
    for (const value of [date.end, date.pointInTime]) {
      const year = yearOf(value)
      if (year !== null) ends.push(year)
    }
  }
  if (!starts.length) return null
  const start = Math.min(...starts)
  const end = ends.length ? Math.max(...ends, start) : start
  return { start, end }
}

export function buildGraph(input) {
  const {
    library = [],
    resolved = new Map(), // jellyfin item id -> QID
    entities = new Map(),
    edges = new Map(),
    roots = [],
    members = new Map(),
    curated = [],
    playlists = {},
    videoTags = new Map(), // jellyfin item id -> tag
    chronology = new Map(), // universe id -> [entry ids]
    themes = new Map(), // universe id -> { preset }
    seerr = new Map(), // "movie:123" -> { posterPath, status }
    decisions = {},
    now = new Date().toISOString(),
  } = input

  const libraryById = new Map(library.map((item) => [item.id, item]))
  const libraryByQid = new Map()
  for (const [itemId, q] of resolved) if (!libraryByQid.has(q)) libraryByQid.set(q, libraryById.get(itemId))
  const libraryByYoutube = new Map(library.filter((item) => item.ids.youtube).map((item) => [item.ids.youtube, item]))

  // ---------- entries ----------

  const entryCache = new Map()

  function seerrFor(ids) {
    if (ids.tmdbMovie) return { mediaType: 'movie', tmdbId: Number(ids.tmdbMovie), ...(seerr.get('movie:' + ids.tmdbMovie) || {}) }
    if (ids.tmdbTv) return { mediaType: 'tv', tmdbId: Number(ids.tmdbTv), ...(seerr.get('tv:' + ids.tmdbTv) || {}) }
    return null
  }

  function libraryFields(item) {
    return { jellyfinItemId: item.id, inLibrary: true }
  }

  /** Non-fiction position from the work's subjects (P921) or period (P2408). */
  function workHistorical(q, kind, item) {
    const entity = entities.get(q)
    const documentary = entity?.types.includes('Q93204') || (item?.genres || []).some((genre) => /documentary|history/i.test(genre))
    if (!documentary) return null
    const subjects = (edges.get(q) || []).filter((edge) => edge.prop === 'P921' || edge.prop === 'P2408')
    const dated = subjects.map((edge) => entities.get(edge.target)).filter(Boolean)
    const span = historicalSpan(dated)
    if (!span) return null
    // A subject dated after the work itself is a typo or a misread; skip it.
    const released = yearOf(entity?.published || entity?.start)
    if (released !== null && span.start > released) return null
    return { ...span, label: dated.map((subject) => subject.name).filter(Boolean).slice(0, 2).join(', ') || null, source: 'wikidata' }
  }

  function workEntry(q) {
    if (entryCache.has(q)) return entryCache.get(q)
    const entity = entities.get(q)
    const item = libraryByQid.get(q)
    let entry = null
    if (entity || item) {
      const kind = kindOf(entity?.types) || (item ? JELLYFIN_KIND[item.type] || 'video' : null)
      if (kind && !(entity?.types || []).some((type) => SKIP_TYPES.has(type))) {
        const ids = { wikidata: q, ...(entity?.ids || {}) }
        if (item?.ids.tmdb && !ids.tmdbMovie && !ids.tmdbTv) ids[item.type === 'Series' ? 'tmdbTv' : 'tmdbMovie'] = item.ids.tmdb
        const date = isoDate(entity?.published || entity?.start || entity?.inception) || item?.premiereDate || null
        const seerrInfo = item ? null : seerrFor(ids)
        const links = entity ? wikidataLinks(entity) : []
        if (ids.openLibrary) links.push({ kind: 'openlibrary', url: 'https://openlibrary.org/' + (/W$/.test(ids.openLibrary) ? 'works/' : 'books/') + ids.openLibrary })
        if (ids.anilistManga) links.push({ kind: 'anilist', url: 'https://anilist.co/manga/' + ids.anilistManga })
        if (ids.anilistAnime) links.push({ kind: 'anilist', url: 'https://anilist.co/anime/' + ids.anilistAnime })
        let imageUrl = null
        if (seerrInfo?.posterPath) imageUrl = 'https://image.tmdb.org/t/p/w342' + seerrInfo.posterPath
        else if (ids.isbn) imageUrl = 'https://covers.openlibrary.org/b/isbn/' + String(ids.isbn).replace(/[^0-9X]/gi, '') + '-M.jpg?default=false'
        else if (entity?.image) imageUrl = commonsImage(entity.image)
        entry = {
          id: 'wd:' + q,
          title: entity?.name || item?.name || q,
          description: entity?.description || null,
          kind,
          year: yearOf(date),
          releaseDate: date,
          jellyfinItemId: null,
          inLibrary: false,
          externalIds: Object.fromEntries(Object.entries(ids).filter(([, value]) => value)),
          imageUrl: item ? null : imageUrl,
          links,
          seerr: seerrInfo && seerrInfo.tmdbId ? { mediaType: seerrInfo.mediaType, tmdbId: seerrInfo.tmdbId, status: seerrInfo.status ?? null } : null,
          positions: { release: releaseKey(date), chronological: null, historical: workHistorical(q, kind, item) },
          lane: null,
          source: 'wikidata',
          confidence: 0.95,
          status: 'confirmed',
          ...(item ? libraryFields(item) : {}),
        }
      }
    }
    entryCache.set(q, entry)
    return entry
  }

  function libraryEntry(item) {
    if (resolved.has(item.id)) return workEntry(resolved.get(item.id))
    const key = item.ids.youtube ? 'yt:' + item.ids.youtube : 'jf:' + item.id
    if (entryCache.has(key)) return entryCache.get(key)
    const entry = {
      id: key,
      title: item.name,
      description: item.overview ? item.overview.slice(0, 280) : null,
      kind: JELLYFIN_KIND[item.type] || 'video',
      year: item.year || yearOf(item.premiereDate),
      releaseDate: item.premiereDate,
      jellyfinItemId: item.id,
      inLibrary: true,
      externalIds: Object.fromEntries(Object.entries({ youtube: item.ids.youtube, tmdb: item.ids.tmdb, imdb: item.ids.imdb }).filter(([, value]) => value)),
      imageUrl: null,
      links: item.ids.youtube ? [{ kind: 'youtube', url: 'https://www.youtube.com/watch?v=' + item.ids.youtube }] : [],
      seerr: null,
      positions: { release: releaseKey(item.premiereDate), chronological: null, historical: null },
      lane: item.ids.youtube ? item.seriesName || null : null,
      source: 'jellyfin',
      confidence: 1,
      status: 'confirmed',
    }
    entryCache.set(key, entry)
    return entry
  }

  function videoEntry(video, playlistChannel) {
    const item = libraryByYoutube.get(video.id)
    if (item) return libraryEntry(item)
    const key = 'yt:' + video.id
    if (entryCache.has(key)) return entryCache.get(key)
    const date = video.publishedAt ? String(video.publishedAt).slice(0, 10) : null
    const entry = {
      id: key,
      title: video.title,
      description: video.description ? video.description.slice(0, 280) : null,
      kind: 'video',
      year: yearOf(date),
      releaseDate: date,
      jellyfinItemId: null,
      inLibrary: false,
      externalIds: { youtube: video.id },
      imageUrl: video.thumbnail || 'https://i.ytimg.com/vi/' + video.id + '/hqdefault.jpg',
      links: [{ kind: 'youtube', url: 'https://www.youtube.com/watch?v=' + video.id }],
      seerr: null,
      positions: { release: releaseKey(date), chronological: null, historical: null },
      lane: video.channel || playlistChannel || null,
      source: 'youtube',
      confidence: 1,
      status: 'confirmed',
    }
    entryCache.set(key, entry)
    return entry
  }

  // ---------- universes ----------

  /** id -> { meta, entries: Map(entryId -> entry overrides) } */
  const drafts = new Map()

  function draft(id, meta) {
    if (!drafts.has(id)) drafts.set(id, { ...meta, id, entries: new Map(), parentIds: new Set(meta.parentIds || []), sources: new Set(meta.sources || []) })
    return drafts.get(id)
  }

  function addEntry(universe, entry, overrides = {}) {
    if (!entry) return
    const decision = decisions[universe.id + '|' + entry.id]
    if (decision === 'reject') return
    const current = universe.entries.get(entry.id)
    const merged = { ...entry, ...overrides, positions: { ...entry.positions, ...(current?.positions || {}), ...(overrides.positions || {}) } }
    if (current && current.status === 'confirmed' && merged.status !== 'confirmed') merged.status = 'confirmed'
    if (decision === 'accept') {
      merged.status = 'confirmed'
      merged.confidence = 1
    }
    universe.entries.set(entry.id, merged)
  }

  // 1. Wikidata roots
  for (const root of roots) {
    const entity = entities.get(root.qid)
    if (!entity) continue
    const universe = draft('wd-' + root.qid, {
      name: entity.name || root.qid,
      kind: root.kind,
      description: entity.description,
      wikidata: root.qid,
      links: wikidataLinks(entity),
      sources: ['Wikidata'],
    })
    const memberQids = unique([...(members.get(root.qid) || []), ...[...libraryByQid.keys()].filter((q) => (edges.get(q) || []).some((edge) => edge.target === root.qid && ['P1434', 'P8345', 'P179', 'P144', 'P361', 'P674'].includes(edge.prop)))])
    if (kindOf(entity.types)) memberQids.push(root.qid)
    for (const q of unique(memberQids)) {
      const entry = workEntry(q)
      if (!entry) continue
      const ordinal = (edges.get(q) || []).find((edge) => edge.prop === 'P179' && edge.target === root.qid && edge.ordinal)?.ordinal
      addEntry(universe, entry, ordinal && Number.isFinite(Number(ordinal)) ? { positions: { chronological: Number(ordinal), chronologicalSource: 'series' } } : {})
    }
    for (const edge of edges.get(root.qid) || []) {
      if (['P1434', 'P8345', 'P361', 'P179'].includes(edge.prop) && roots.some((other) => other.qid === edge.target)) universe.parentIds.add('wd-' + edge.target)
    }
  }

  // 2. Shared non-fiction subjects in the library ("World War II", "Ancient Egypt")
  const subjectUse = new Map()
  for (const [q, item] of libraryByQid) {
    const entry = workEntry(q)
    if (!entry?.positions.historical) continue
    for (const edge of edges.get(q) || []) {
      if (edge.prop !== 'P921') continue
      if (!subjectUse.has(edge.target)) subjectUse.set(edge.target, [])
      subjectUse.get(edge.target).push(entry)
    }
  }
  for (const [subject, entries] of subjectUse) {
    const entity = entities.get(subject)
    if (!entity || entries.length < 2) continue
    const universe = draft('subject-' + subject, { name: entity.name || subject, kind: 'non-fiction', description: entity.description, wikidata: subject, links: wikidataLinks(entity), sources: ['Wikidata'], parentIds: ['history'] })
    for (const entry of entries) addEntry(universe, entry)
  }

  // 3. YouTube playlists: backlogs, in playlist order
  for (const [playlistId, playlist] of Object.entries(playlists)) {
    const universe = draft('yt-' + playlistId, {
      name: playlist.title || 'YouTube playlist',
      kind: 'playlist',
      description: playlist.description || null,
      links: [{ kind: 'youtube', url: 'https://www.youtube.com/playlist?list=' + playlistId }],
      sources: ['YouTube'],
    })
    ;(playlist.videos || []).forEach((video, index) => addEntry(universe, videoEntry(video, playlist.channel), { positions: { chronological: index + 1, chronologicalSource: 'playlist' } }))
  }

  // 4. LLM suggestions for videos and unmatched items
  const universeByName = () => {
    const map = new Map()
    for (const universe of drafts.values()) map.set(slug(universe.name), universe)
    for (const definition of curated) map.set(slug(definition.name), drafts.get('curated-' + definition.id) || { pendingCurated: definition })
    return map
  }
  const aiCandidates = new Map()
  for (const [itemId, tag] of videoTags) {
    const item = libraryById.get(itemId)
    if (!item || !tag) continue
    const entry = libraryEntry(item)
    if (tag.historical && tag.nonFiction !== false && Number.isFinite(tag.historical.start)) {
      const confidence = Number(tag.historical.confidence ?? tag.confidence ?? 0.7)
      if (!entry.positions.historical && confidence >= 0.5) {
        entry.positions.historical = {
          start: Math.trunc(tag.historical.start),
          end: Math.trunc(Number.isFinite(tag.historical.end) ? tag.historical.end : tag.historical.start),
          label: tag.historical.label || null,
          source: 'llm',
          confidence,
        }
      }
    }
    for (const suggestion of tag.universes || []) {
      if (!suggestion?.name) continue
      const key = slug(suggestion.name)
      if (!key) continue
      if (!aiCandidates.has(key)) aiCandidates.set(key, { name: suggestion.name, items: [] })
      aiCandidates.get(key).items.push({ entry, suggestion })
    }
  }

  // 5. Curated universes (shipped files and the owner's own)
  const allEntries = () => {
    const map = new Map()
    for (const item of library) {
      const entry = libraryEntry(item)
      if (entry) map.set(entry.id, entry)
    }
    for (const universe of drafts.values()) for (const entry of universe.entries.values()) if (!map.has(entry.id)) map.set(entry.id, entry)
    return [...map.values()]
  }

  for (const definition of curated) {
    const universe = draft('curated-' + definition.id, {
      name: definition.name,
      kind: definition.kind || 'franchise',
      description: definition.description || null,
      links: definition.links || [],
      sources: ['Curated'],
      eras: definition.eras || null,
      themeOverride: definition.theme || null,
      parentIds: definition.parents ? definition.parents.map((parent) => 'curated-' + parent) : [],
      lanes: definition.lanes || null,
    })
    const match = definition.match || {}
    const patterns = (match.titlePatterns || []).map((pattern) => {
      try {
        return new RegExp(pattern, 'i')
      } catch {
        return null
      }
    }).filter(Boolean)
    const channels = new Set((match.channels || []).map((channel) => channel.toLowerCase()))
    const everything = allEntries()
    for (const entry of everything) {
      const titleMatch = patterns.length && patterns.some((pattern) => pattern.test(entry.title))
      const channelOk = !channels.size || (entry.lane && channels.has(entry.lane.toLowerCase()))
      if ((titleMatch && channelOk) || (!patterns.length && channels.size && channelOk && entry.kind === 'video')) {
        addEntry(universe, entry, definition.lanes === 'channel' ? { lane: entry.lane } : {})
      }
      if (match.historical && entry.positions.historical) addEntry(universe, entry)
    }
    for (const q of match.wikidata || []) {
      const source = drafts.get('wd-' + q)
      if (source) for (const entry of source.entries.values()) addEntry(universe, entry)
    }
    for (const [index, item] of (definition.entries || []).entries()) {
      const ids = item.ids || {}
      let entry = everything.find((candidate) =>
        Object.entries(ids).some(([key, value]) => value && String(candidate.externalIds[key]) === String(value)),
      )
      if (!entry) {
        const date = item.releaseDate || (item.year ? String(item.year) + '-01-01' : null)
        entry = {
          id: 'cu:' + definition.id + ':' + (item.key || slug(item.title) || index),
          title: item.title,
          description: item.description || null,
          kind: item.kind || 'other',
          year: yearOf(date),
          releaseDate: isoDate(date),
          jellyfinItemId: null,
          inLibrary: false,
          externalIds: ids,
          imageUrl: item.imageUrl || null,
          links: item.links || [],
          seerr: ids.tmdbMovie ? { mediaType: 'movie', tmdbId: Number(ids.tmdbMovie), status: null } : ids.tmdbTv ? { mediaType: 'tv', tmdbId: Number(ids.tmdbTv), status: null } : null,
          positions: { release: releaseKey(date), chronological: null, historical: null },
          lane: item.lane || null,
          source: 'curated',
          confidence: 1,
          status: 'confirmed',
        }
      }
      addEntry(universe, entry, {
        positions: {
          ...(Number.isFinite(item.chronological) ? { chronological: item.chronological, chronologicalSource: 'curated' } : {}),
          ...(item.historical ? { historical: { ...item.historical, source: 'curated' } } : {}),
        },
        ...(item.lane ? { lane: item.lane } : {}),
      })
    }
  }

  // LLM suggestions join existing universes by name, or form a new one when two videos agree.
  const names = universeByName()
  for (const [key, candidate] of aiCandidates) {
    let universe = names.get(key)
    if (universe?.pendingCurated) universe = drafts.get('curated-' + universe.pendingCurated.id)
    if (!universe) {
      if (candidate.items.length < 2) continue
      universe = draft('ai-' + key, { name: candidate.name, kind: candidate.items.some(({ entry }) => entry.lane) ? 'creator-collab' : 'franchise', description: null, links: [], sources: ['Suggested by AI'] })
    }
    for (const { entry, suggestion } of candidate.items) {
      const confidence = Math.max(0, Math.min(1, Number(suggestion.confidence ?? 0.5)))
      if (universe.entries.get(entry.id)?.status === 'confirmed') continue
      addEntry(universe, entry, {
        source: 'llm',
        confidence,
        status: confidence >= SUGGESTION_THRESHOLD ? 'confirmed' : 'suggested',
        reason: suggestion.reason || null,
        ...(suggestion.lane ? { lane: suggestion.lane } : {}),
        ...(Number.isFinite(suggestion.order) ? { positions: { chronological: suggestion.order, chronologicalSource: 'llm' } } : {}),
      })
    }
  }

  // 6. Human history: every non-fiction entry with a real-world date
  const history = draft('history', {
    name: 'Human history',
    kind: 'non-fiction',
    description: 'Documentaries and explainers on one timeline, by the period they are about.',
    links: [],
    sources: ['Wikidata', 'Suggested by AI'],
    eras: HISTORY_ERAS,
  })
  for (const entry of allEntries()) {
    if (entry.positions.historical) {
      const suggested = entry.positions.historical.source === 'llm' && (entry.positions.historical.confidence ?? 1) < SUGGESTION_THRESHOLD
      addEntry(history, entry, suggested ? { status: 'suggested', source: 'llm', confidence: entry.positions.historical.confidence, reason: entry.positions.historical.label } : {})
    }
  }

  // ---------- finalise ----------

  const universes = {}
  for (const universe of drafts.values()) {
    const entries = [...universe.entries.values()]
    const inLibrary = entries.filter((entry) => entry.inLibrary).length
    const minimum = universe.kind === 'playlist' || universe.id.startsWith('curated-') || universe.id === 'history' ? 1 : 2
    if (entries.length < minimum || (inLibrary === 0 && universe.kind !== 'playlist' && !universe.id.startsWith('curated-'))) continue
    // A character universe is only worth showing when it links works you have.
    if (universe.kind === 'character' && inLibrary < 2) continue

    const order = chronology.get(universe.id)
    if (order?.length) {
      order.forEach((entryId, index) => {
        const entry = universe.entries.get(entryId)
        if (entry) entry.positions = { ...entry.positions, chronological: index + 1, chronologicalSource: 'llm' }
      })
    }

    entries.sort((a, b) => (a.positions.release ?? Infinity) - (b.positions.release ?? Infinity) || a.title.localeCompare(b.title))
    const lanes = unique(entries.map((entry) => entry.lane))
    const timelines = ['release']
    if (entries.filter((entry) => Number.isFinite(entry.positions.chronological)).length >= 2) timelines.push('chronological')
    if (entries.filter((entry) => entry.positions.historical).length >= 1 && (universe.kind === 'non-fiction' || entries.some((entry) => entry.positions.historical))) timelines.push('historical')
    if (lanes.length >= 2) timelines.push('lanes')

    const orderSources = entries.map((entry) => entry.positions.chronologicalSource).filter(Boolean)
    const orderSource = ['llm', 'curated', 'playlist', 'series'].find((source) => orderSources.filter((value) => value === source).length >= orderSources.length / 2) || orderSources[0] || null

    const genres = entries.filter((entry) => entry.inLibrary).flatMap((entry) => libraryById.get(entry.jellyfinItemId)?.genres || [])
    const relations = []
    const ids = new Set(entries.map((entry) => entry.id))
    for (const entry of entries) {
      const q = entry.externalIds.wikidata
      if (!q) continue
      for (const edge of edges.get(q) || []) {
        const target = 'wd:' + edge.target
        if (!ids.has(target)) continue
        if (edge.prop === 'P156') relations.push({ from: entry.id, to: target, type: 'sequel' })
        if (edge.prop === 'P155') relations.push({ from: target, to: entry.id, type: 'sequel' })
        if (edge.prop === 'P144') relations.push({ from: entry.id, to: target, type: 'based-on' })
      }
    }
    const seen = new Set()
    universes[universe.id] = {
      id: universe.id,
      name: universe.name,
      kind: universe.kind,
      description: universe.description || null,
      wikidata: universe.wikidata || null,
      links: universe.links || [],
      sources: [...universe.sources],
      parentIds: [...universe.parentIds],
      childIds: [],
      theme: chooseTheme({ name: universe.name, kind: universe.kind, genres, override: themes.get(universe.id) || universe.themeOverride, eras: universe.eras }),
      timelines,
      orderSource,
      lanes,
      entries,
      relations: relations.filter((relation) => {
        const key = relation.from + '>' + relation.to + ':' + relation.type
        return !seen.has(key) && seen.add(key)
      }),
      counts: {
        entries: entries.length,
        inLibrary,
        suggested: entries.filter((entry) => entry.status === 'suggested').length,
      },
      updatedAt: now,
    }
  }

  dedupe(universes)
  link(universes)

  // Index + reviews
  const itemIndex = {}
  const reviews = {}
  for (const universe of Object.values(universes)) {
    for (const entry of universe.entries) {
      if (entry.jellyfinItemId) {
        if (!itemIndex[entry.jellyfinItemId]) itemIndex[entry.jellyfinItemId] = []
        itemIndex[entry.jellyfinItemId].push(universe.id)
      }
      if (entry.status === 'suggested') {
        const id = universe.id + '|' + entry.id
        reviews[id] = {
          id,
          universeId: universe.id,
          universeName: universe.name,
          entry: summaryEntry(entry),
          confidence: entry.confidence,
          reason: entry.reason || null,
          question: 'Is "' + entry.title + '" part of ' + universe.name + '?',
        }
      }
    }
  }
  return { universes, itemIndex, reviews }
}

/** Universes with the same entries are the same thing seen twice: keep the broadest kind. */
function dedupe(universes) {
  const bySignature = new Map()
  for (const universe of Object.values(universes)) {
    // The history timeline is a view over everything; it's never a duplicate.
    if (universe.id === 'history') continue
    const signature = universe.entries.map((entry) => entry.id).sort().join(',')
    const other = bySignature.get(signature)
    if (!other) {
      bySignature.set(signature, universe)
      continue
    }
    const curatedA = universe.id.startsWith('curated-')
    const curatedB = other.id.startsWith('curated-')
    // Someone wrote both files on purpose (a season and its show); keep both.
    if (curatedA && curatedB) continue
    const keep = curatedA !== curatedB ? (curatedA ? universe : other) : (KIND_RANK[universe.kind] ?? 9) < (KIND_RANK[other.kind] ?? 9) ? universe : other
    const drop = keep === universe ? other : universe
    keep.parentIds = unique([...keep.parentIds, ...drop.parentIds]).filter((id) => id !== keep.id)
    delete universes[drop.id]
    bySignature.set(signature, keep)
  }
  // Two universes with the same name (Wikidata's "Arrowverse" universe and "Arrowverse" franchise)
  // are one universe to people: merge the smaller into the bigger.
  const byName = new Map()
  for (const universe of Object.values(universes).sort((a, b) => b.entries.length - a.entries.length)) {
    const key = universe.name.trim().toLowerCase()
    const keep = byName.get(key)
    if (!keep || universe.kind === 'playlist' || keep.kind === 'playlist' || universe.id.startsWith('curated-')) {
      if (!keep) byName.set(key, universe)
      continue
    }
    const ids = new Set(keep.entries.map((entry) => entry.id))
    for (const entry of universe.entries) if (!ids.has(entry.id)) keep.entries.push(entry)
    keep.entries.sort((a, b) => (a.positions.release ?? Infinity) - (b.positions.release ?? Infinity) || a.title.localeCompare(b.title))
    keep.parentIds = unique([...keep.parentIds, ...universe.parentIds]).filter((id) => id !== keep.id && id !== universe.id)
    keep.counts = { entries: keep.entries.length, inLibrary: keep.entries.filter((entry) => entry.inLibrary).length, suggested: keep.entries.filter((entry) => entry.status === 'suggested').length }
    if ((KIND_RANK[universe.kind] ?? 9) < (KIND_RANK[keep.kind] ?? 9)) keep.kind = universe.kind
    for (const other of Object.values(universes)) other.parentIds = other.parentIds.map((id) => (id === universe.id ? keep.id : id))
    delete universes[universe.id]
  }

  // Character universes fully inside a bigger universe add nothing.
  const list = Object.values(universes)
  for (const universe of list) {
    if (universe.kind !== 'character' || !universes[universe.id]) continue
    const ids = new Set(universe.entries.map((entry) => entry.id))
    const container = list.find((other) => other !== universe && universes[other.id] && other.kind !== 'character' && other.entries.length >= ids.size && [...ids].every((id) => other.entries.some((entry) => entry.id === id)))
    if (container) delete universes[universe.id]
  }
}

/** Parents from Wikidata plus "this universe sits entirely inside that one". */
function link(universes) {
  const list = Object.values(universes)
  // Only confirmed entries say what a universe is; an unsure AI guess shouldn't reshape the tree.
  const sets = new Map(list.map((universe) => [universe.id, new Set(universe.entries.filter((entry) => entry.status === 'confirmed').map((entry) => entry.id))]))
  for (const universe of list) {
    universe.parentIds = universe.parentIds.filter((id) => universes[id] && id !== universe.id)
    if (universe.parentIds.length || universe.kind === 'playlist' || universe.id === 'history') continue
    const own = sets.get(universe.id)
    const containers = list.filter((other) => {
      if (other === universe || other.kind === 'playlist' || other.kind === 'character' || other.parentIds.includes(universe.id)) return false
      const theirs = sets.get(other.id)
      return theirs.size > own.size && [...own].every((id) => theirs.has(id))
    })
    containers.sort((a, b) => sets.get(a.id).size - sets.get(b.id).size)
    if (containers[0]) universe.parentIds.push(containers[0].id)
  }
  // A parent is always the bigger universe: break loops like A -> B -> A.
  for (const universe of list) {
    universe.parentIds = unique(universe.parentIds).filter((id) => {
      const parent = universes[id]
      if (!parent) return false
      if (!parent.parentIds.includes(universe.id)) return true
      return sets.get(id).size > sets.get(universe.id).size || (sets.get(id).size === sets.get(universe.id).size && id < universe.id)
    })
  }
  // Sub-universes look like their parent unless something specific says otherwise
  // (Iron Man films are Marvel, whatever their genre).
  const inherit = (universe, seen = new Set()) => {
    if (seen.has(universe.id)) return universe.theme
    seen.add(universe.id)
    if (!['genre', 'default'].includes(universe.theme.basis)) return universe.theme
    const parent = universes[universe.parentIds[0]]
    if (!parent) return universe.theme
    const theme = inherit(parent, seen)
    if (['genre', 'default'].includes(theme.basis)) return universe.theme
    universe.theme = { ...theme, basis: 'parent', eras: universe.theme.eras }
    return universe.theme
  }
  for (const universe of list) inherit(universe)

  for (const universe of list) {
    for (const parentId of universe.parentIds) {
      const parent = universes[parentId]
      if (parent && !parent.childIds.includes(universe.id)) parent.childIds.push(universe.id)
    }
  }
}

export function summaryEntry(entry) {
  return {
    id: entry.id,
    title: entry.title,
    kind: entry.kind,
    year: entry.year,
    jellyfinItemId: entry.jellyfinItemId,
    inLibrary: entry.inLibrary,
    imageUrl: entry.imageUrl,
    lane: entry.lane,
  }
}

export function summaryUniverse(universe) {
  const inLibrary = universe.entries.filter((entry) => entry.inLibrary)
  return {
    id: universe.id,
    name: universe.name,
    kind: universe.kind,
    description: universe.description,
    theme: universe.theme,
    timelines: universe.timelines,
    parentIds: universe.parentIds,
    childIds: universe.childIds,
    counts: universe.counts,
    span: (() => {
      const years = universe.entries.map((entry) => entry.year).filter((year) => Number.isFinite(year))
      return years.length ? { from: Math.min(...years), to: Math.max(...years) } : null
    })(),
    sampleItemIds: inLibrary.slice(0, 8).map((entry) => entry.jellyfinItemId),
    sampleImageUrls: universe.entries.filter((entry) => !entry.inLibrary && entry.imageUrl).slice(0, 4).map((entry) => entry.imageUrl),
    updatedAt: universe.updatedAt,
  }
}

/** Real-world eras for the history timeline; years, negative is BCE. */
export const HISTORY_ERAS = [
  { label: 'Deep time', start: -13800000000, end: -300000 },
  { label: 'Prehistory', start: -300000, end: -3200 },
  { label: 'Ancient world', start: -3200, end: 500 },
  { label: 'Middle Ages', start: 500, end: 1500 },
  { label: 'Early modern', start: 1500, end: 1800 },
  { label: 'Industrial age', start: 1800, end: 1914 },
  { label: 'World wars', start: 1914, end: 1945 },
  { label: 'Postwar', start: 1945, end: 1991 },
  { label: 'Our time', start: 1991, end: 2100 },
]
