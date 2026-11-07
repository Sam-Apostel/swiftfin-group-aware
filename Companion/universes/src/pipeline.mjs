// The scan: library -> Wikidata -> YouTube -> Seerr -> AI -> graph. One at a time;
// a scan started while another runs just waits for it.

import { join } from 'node:path'
import { loadCurated } from './curated.mjs'
import { buildGraph, pickRoots } from './graph.mjs'
import { Jellyfin } from './jellyfin.mjs'
import { LLM } from './llm.mjs'
import { Seerr } from './seerr.mjs'
import { mapLimit, unique } from './util.mjs'
import { isCharacter, Wikidata } from './wikidata.mjs'
import { fetchPlaylist } from './youtube.mjs'

const MAX_ROOTS = 250
const MAX_SEERR_LOOKUPS = 400
const DAY = 24 * 60 * 60 * 1000

export class Pipeline {
  constructor({ store, settings, curatedDirs, log }) {
    this.store = store
    this.settings = settings
    this.curatedDirs = curatedDirs
    this.log = log
    this.running = null
    this.status = { state: 'idle', step: null, progress: null, startedAt: null, finishedAt: null, error: null }
    // Kept between scans so review answers can rebuild the graph without the network.
    this.inputs = null
  }

  setStep(step, progress = null) {
    this.status = { ...this.status, step, progress }
    if (progress === null) this.log(step)
  }

  scan(reason = 'manual') {
    if (!this.running) {
      this.running = this.run(reason).finally(() => {
        this.running = null
      })
    }
    return this.running
  }

  async run(reason) {
    const settings = this.settings.value
    this.status = { state: 'running', step: 'Starting', progress: null, startedAt: new Date().toISOString(), finishedAt: null, error: null }
    this.log('Scan started (' + reason + ')')
    try {
      const jellyfin = new Jellyfin(settings.jellyfinUrl, settings.jellyfinApiKey)
      if (!jellyfin.configured) throw new Error('Add a Jellyfin API key in the settings first.')

      // 1. Library
      this.setStep('Reading the Jellyfin library')
      const library = await jellyfin.library((done, total) => this.setStep('Reading the Jellyfin library', { done, total }))
      this.store.state.library = { items: Object.fromEntries(library.map((item) => [item.id, item])), scannedAt: new Date().toISOString() }
      this.log('Library: ' + library.length + ' items (' + library.filter((item) => item.ids.youtube).length + ' from YouTube)')

      // 2. Wikidata
      const wikidata = new Wikidata(this.store, { log: this.log })
      const resolved = new Map()
      let entities = new Map()
      let edges = new Map()
      let roots = []
      const members = new Map()
      if (settings.wikidata.enabled) {
        this.setStep('Matching the library with Wikidata')
        const wanted = []
        for (const item of library) {
          if (item.ids.tmdb) wanted.push({ prop: item.type === 'Series' ? 'P4983' : 'P4947', value: item.ids.tmdb })
          if (item.ids.imdb) wanted.push({ prop: 'P345', value: item.ids.imdb })
          if (item.ids.tvdb && item.type === 'Series') wanted.push({ prop: 'P4835', value: item.ids.tvdb })
        }
        const found = await wikidata.resolve(wanted)
        for (const item of library) {
          const q =
            (item.ids.tmdb && found.get((item.type === 'Series' ? 'P4983:' : 'P4947:') + item.ids.tmdb)) ||
            (item.ids.imdb && found.get('P345:' + item.ids.imdb)) ||
            (item.ids.tvdb && item.type === 'Series' && found.get('P4835:' + item.ids.tvdb))
          if (q) resolved.set(item.id, q)
        }
        const libraryWorks = unique([...resolved.values()])
        this.log('Wikidata: matched ' + resolved.size + ' of ' + library.length + ' items')

        this.setStep('Reading relations')
        edges = await wikidata.edges(libraryWorks)
        const targets = unique([...edges.values()].flat().map((edge) => edge.target))
        entities = await wikidata.entities(unique([...libraryWorks, ...targets]))

        roots = pickRoots({ libraryWorks, edges, entities })
        // Biggest first: those are the ones people want to explore.
        roots.sort((a, b) => countUse(b.qid, edges) - countUse(a.qid, edges))
        if (roots.length > MAX_ROOTS) {
          this.log('Wikidata: ' + roots.length + ' candidate universes, expanding the ' + MAX_ROOTS + ' that hold most of the library')
          roots = roots.slice(0, MAX_ROOTS)
        }

        let done = 0
        for (const root of roots) {
          this.setStep('Exploring universes', { done: done++, total: roots.length })
          const entity = entities.get(root.qid)
          members.set(root.qid, await wikidata.members(root.qid, { character: isCharacter(entity?.types || []) }))
        }

        this.setStep('Reading universe members')
        const memberQids = unique([...members.values()].flat())
        const more = await wikidata.entities(memberQids.filter((q) => !entities.has(q)))
        for (const [q, entity] of more) entities.set(q, entity)
        // Relations of members (sequels, based-on) and of roots (nesting).
        const moreEdges = await wikidata.edges(unique([...memberQids, ...roots.map((root) => root.qid)]).filter((q) => !edges.has(q)))
        for (const [q, list] of moreEdges) edges.set(q, list)
        // Dates of non-fiction subjects.
        const subjects = unique([...edges.values()].flat().filter((edge) => edge.prop === 'P921' || edge.prop === 'P2408').map((edge) => edge.target))
        const subjectEntities = await wikidata.entities(subjects.filter((q) => !entities.has(q)))
        for (const [q, entity] of subjectEntities) entities.set(q, entity)
        this.log('Wikidata: ' + roots.length + ' universes, ' + memberQids.length + ' works, ' + wikidata.queries + ' queries')
      }

      // 3. YouTube playlists
      const playlists = {}
      if (settings.youtube.playlists.length) {
        if (!settings.youtube.apiKey) {
          this.log('YouTube: playlists are set but there is no YouTube Data API key; skipped')
        } else {
          for (const playlistId of settings.youtube.playlists) {
            this.setStep('Reading YouTube playlist ' + playlistId)
            const cached = this.store.state.playlists[playlistId]
            try {
              playlists[playlistId] = cached && Date.now() - Date.parse(cached.fetchedAt) < 6 * 60 * 60 * 1000 && reason !== 'manual'
                ? cached
                : await fetchPlaylist(settings.youtube.apiKey, playlistId)
              this.store.state.playlists[playlistId] = playlists[playlistId]
            } catch (error) {
              this.log('YouTube: ' + error.message)
              if (cached) playlists[playlistId] = cached
            }
          }
        }
      }
      for (const id of Object.keys(this.store.state.playlists)) if (!settings.youtube.playlists.includes(id)) delete this.store.state.playlists[id]

      const curated = loadCurated(this.curatedDirs, this.log)
      const inputs = { library, resolved, entities, edges, roots, members, curated, playlists, videoTags: new Map(), chronology: new Map(), themes: new Map(), seerr: new Map() }

      // 4. Seerr posters for what's not in the library
      const seerr = new Seerr(settings.seerrUrl, settings.seerrApiKey)
      if (seerr.configured) {
        const first = buildGraph({ ...inputs, decisions: this.store.state.decisions })
        const ghosts = unique(
          Object.values(first.universes).flatMap((universe) => universe.entries.filter((entry) => !entry.inLibrary && entry.seerr).map((entry) => entry.seerr.mediaType + ':' + entry.seerr.tmdbId)),
        ).slice(0, MAX_SEERR_LOOKUPS)
        let done = 0
        await mapLimit(ghosts, 4, async (key) => {
          this.setStep('Fetching posters from Seerr', { done: done++, total: ghosts.length })
          const hit = this.store.cached('seerr:' + key, 3 * DAY)
          if (hit !== undefined) return inputs.seerr.set(key, hit)
          const [mediaType, tmdbId] = key.split(':')
          try {
            const info = await seerr.lookup(mediaType, tmdbId)
            this.store.setCached('seerr:' + key, info)
            inputs.seerr.set(key, info)
          } catch (error) {
            if (error.status === 404) this.store.setCached('seerr:' + key, null)
          }
        })
      }

      // 5. AI: videos and unmatched non-fiction, then chronology and themes
      const llm = new LLM(settings.llm, this.store, { log: this.log })
      if (llm.configured) {
        const preliminary = buildGraph({ ...inputs, decisions: this.store.state.decisions })
        const knownNames = unique([...Object.values(preliminary.universes).map((universe) => universe.name), ...curated.map((definition) => definition.name)])
        const candidates = library.filter(
          (item) => !resolved.has(item.id) && (item.ids.youtube || item.type === 'Video' || item.genres.some((genre) => /documentary/i.test(genre))),
        )
        let done = 0
        for (const item of candidates) {
          if (!llm.budgetLeft) break
          this.setStep('Asking AI about videos', { done: done++, total: candidates.length })
          const tag = await llm.tagVideo(item, knownNames)
          if (tag) inputs.videoTags.set(item.id, tag)
        }
        // Answers cached from earlier scans count too, even when this scan's budget ran out.
        for (const item of candidates) {
          if (inputs.videoTags.has(item.id)) continue
          const tag = await llm.tagVideo(item, knownNames).catch(() => null)
          if (tag) inputs.videoTags.set(item.id, tag)
        }

        const tagged = buildGraph({ ...inputs, decisions: this.store.state.decisions })
        const orderable = Object.values(tagged.universes).filter(
          (universe) => ['fictional-universe', 'franchise', 'series'].includes(universe.kind) && universe.entries.length >= 3 && universe.entries.length <= 120,
        )
        done = 0
        for (const universe of orderable.sort((a, b) => b.counts.inLibrary - a.counts.inLibrary)) {
          this.setStep('Asking AI for in-universe order', { done: done++, total: orderable.length })
          if (universe.entries.filter((entry) => Number.isFinite(entry.positions.chronological)).length >= universe.entries.length * 0.8) continue
          const order = await llm.orderChronologically(universe)
          if (order) inputs.chronology.set(universe.id, order)
        }
        for (const universe of Object.values(tagged.universes)) {
          if (universe.theme.preset !== 'cinematic' || universe.kind === 'playlist') continue
          const theme = await llm.pickTheme(universe)
          if (theme) inputs.themes.set(universe.id, theme)
        }
        this.log('AI: ' + llm.calls + ' new questions this scan')
      }

      // 6. Graph
      this.setStep('Building universes')
      this.inputs = inputs
      this.rebuild()
      this.store.state.lastScan = { at: new Date().toISOString(), reason, wikidataQueries: wikidata.queries }
      this.store.pruneCache(60 * DAY)
      this.store.saveNow()
      const count = Object.keys(this.store.state.universes).length
      this.log('Scan finished: ' + count + ' universes, ' + Object.keys(this.store.state.reviews).length + ' suggestions to review')
      this.status = { ...this.status, state: 'idle', step: null, progress: null, finishedAt: new Date().toISOString() }
    } catch (error) {
      this.log('Scan failed: ' + error.message)
      this.status = { ...this.status, state: 'error', step: null, progress: null, finishedAt: new Date().toISOString(), error: error.message }
    }
  }

  /** Rebuilds the graph from the last scan's inputs, e.g. after a review answer. */
  rebuild() {
    if (!this.inputs) return false
    const graph = buildGraph({ ...this.inputs, decisions: this.store.state.decisions })
    this.store.state.universes = graph.universes
    this.store.state.itemIndex = graph.itemIndex
    this.store.state.reviews = graph.reviews
    this.store.save()
    return true
  }
}

function countUse(qid, edges) {
  let count = 0
  for (const list of edges.values()) if (list.some((edge) => edge.target === qid)) count++
  return count
}

export const defaultCuratedDirs = (appDir, dataDir) => [join(appDir, 'universes'), join(dataDir, 'universes')]
