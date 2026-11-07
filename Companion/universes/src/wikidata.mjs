// Wikidata: the backbone of the universe graph. Everything here is a public,
// read-only SPARQL query against query.wikidata.org, cached in the store.

import { chunk, fetchJson, sleep, unique } from './util.mjs'

const ENDPOINT = 'https://query.wikidata.org/sparql'
const DAY = 24 * 60 * 60 * 1000

/** What a Wikidata `instance of` means for us. */
export const ENTRY_KINDS = {
  // films
  Q11424: 'movie', Q202866: 'movie', Q506240: 'movie', Q24862: 'movie', Q93204: 'movie', Q24869: 'movie',
  Q29168811: 'movie', Q20650540: 'movie', Q17517379: 'movie', Q226730: 'movie', Q1261214: 'movie', Q229390: 'movie',
  // series
  Q5398426: 'series', Q581714: 'series', Q1259759: 'series', Q15416: 'series', Q526877: 'series', Q63952888: 'series',
  Q1366112: 'series', Q117467246: 'series',
  // books
  Q7725634: 'book', Q8261: 'book', Q571: 'book', Q47461344: 'book', Q49084: 'book', Q747381: 'book', Q1279564: 'book',
  // comics and manga
  Q21198342: 'comic', Q8274: 'comic', Q725377: 'comic', Q1004: 'comic', Q14406742: 'comic', Q1760610: 'comic', Q838795: 'comic',
  // games
  Q7889: 'game', Q16070115: 'game',
}

/** Types that group works rather than being one. */
export const GROUPER_TYPES = new Set([
  'Q559618', // fictional universe
  'Q196600', // media franchise
  'Q24856', // film series
  'Q7725310', // series of creative works
  'Q1667921', // novel series
  'Q277759', // book series
  'Q20937557', // series
])

export const CHARACTER_TYPES = new Set([
  'Q95074', // fictional character
  'Q15632617', // fictional human
  'Q15773347', // film character
  'Q15773317', // television character
  'Q1114461', // comics character
  'Q3658341', // literary character
  'Q4271324', // mythical character
])

export const SKIP_TYPES = new Set(['Q5', 'Q13406463', 'Q4167836', 'Q21191270', 'Q3464665'])

export function kindOf(types = []) {
  for (const type of types) if (ENTRY_KINDS[type]) return ENTRY_KINDS[type]
  return null
}

export function isGrouper(types = []) {
  return types.some((type) => GROUPER_TYPES.has(type))
}

export function isCharacter(types = []) {
  return types.some((type) => CHARACTER_TYPES.has(type))
}

const qid = (uri) => (uri ? String(uri).replace(/^.*\//, '') : null)
const value = (binding, name) => binding[name]?.value ?? null
const values = (list) => list.filter((id) => /^Q\d+$/.test(id)).map((id) => 'wd:' + id).join(' ')
const literal = (text) => '"' + String(text).replace(/["\\]/g, '') + '"'

export class Wikidata {
  constructor(store, { delayMs = 250, log = () => {} } = {}) {
    this.store = store
    this.delayMs = delayMs
    this.log = log
    this.queries = 0
  }

  async sparql(query) {
    this.queries++
    if (this.delayMs) await sleep(this.delayMs)
    const data = await fetchJson(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/sparql-results+json' },
      body: new URLSearchParams({ query }).toString(),
      retries: 3,
      timeoutMs: 90000,
    })
    return data?.results?.bindings || []
  }

  /** Cached per key: runs `fetcher` for the keys that aren't cached (or are stale), in batches. */
  async cachedBatch(prefix, keys, maxAgeMs, batchSize, fetcher) {
    const result = new Map()
    const missing = []
    for (const key of unique(keys)) {
      const hit = this.store.cached(prefix + key, maxAgeMs)
      if (hit !== undefined) result.set(key, hit)
      else missing.push(key)
    }
    for (const batch of chunk(missing, batchSize)) {
      let fetched
      try {
        fetched = await fetcher(batch)
      } catch (error) {
        this.log('Wikidata query failed (' + prefix + batch.length + '): ' + error.message)
        continue
      }
      for (const key of batch) {
        const hit = fetched.get(key) ?? null
        this.store.setCached(prefix + key, hit)
        result.set(key, hit)
      }
    }
    return result
  }

  /**
   * Library external ids -> QIDs. `wanted` is [{ prop, value }] with prop one of
   * P4947 (TMDB movie), P4983 (TMDB TV), P345 (IMDb), P4835 (TVDB series).
   */
  async resolve(wanted) {
    const byProp = new Map()
    for (const { prop, value: id } of wanted) {
      if (!id) continue
      if (!byProp.has(prop)) byProp.set(prop, [])
      byProp.get(prop).push(String(id))
    }
    const out = new Map()
    for (const [prop, ids] of byProp) {
      const found = await this.cachedBatch('resolve:' + prop + ':', ids, 30 * DAY, 150, async (batch) => {
        const rows = await this.sparql(
          'SELECT ?item ?v WHERE { VALUES ?v { ' + batch.map(literal).join(' ') + ' } ?item wdt:' + prop + ' ?v . }',
        )
        const map = new Map()
        for (const row of rows) if (!map.has(value(row, 'v'))) map.set(value(row, 'v'), qid(value(row, 'item')))
        return map
      })
      for (const [id, item] of found) if (item) out.set(prop + ':' + id, item)
    }
    return out
  }

  /** Labels, descriptions, types, dates and external ids for any entities. */
  async entities(qids) {
    const core = await this.cachedBatch('entity:', qids, 30 * DAY, 60, async (batch) => {
      const rows = await this.sparql(`
        SELECT ?e (COALESCE(SAMPLE(?label), SAMPLE(?mul)) AS ?name) (SAMPLE(?desc) AS ?description)
          (GROUP_CONCAT(DISTINCT STRAFTER(STR(?type), "entity/"); separator=" ") AS ?types)
          (SAMPLE(?enwiki) AS ?wikipedia) (SAMPLE(?image) AS ?img)
        WHERE {
          VALUES ?e { ${values(batch)} }
          OPTIONAL { ?e rdfs:label ?label FILTER(LANG(?label) = "en") }
          OPTIONAL { ?e rdfs:label ?mul FILTER(LANG(?mul) = "mul") }
          OPTIONAL { ?e schema:description ?desc FILTER(LANG(?desc) = "en") }
          OPTIONAL { ?e wdt:P31 ?type }
          OPTIONAL { ?e wdt:P18 ?image }
          OPTIONAL { ?enwiki schema:about ?e ; schema:isPartOf <https://en.wikipedia.org/> }
        } GROUP BY ?e`)
      const map = new Map()
      for (const row of rows) {
        map.set(qid(value(row, 'e')), {
          id: qid(value(row, 'e')),
          name: value(row, 'name'),
          description: value(row, 'description'),
          types: (value(row, 'types') || '').split(' ').filter(Boolean),
          wikipedia: value(row, 'wikipedia'),
          image: value(row, 'img'),
        })
      }
      return map
    })
    const extra = await this.cachedBatch('entity-ids:', qids, 30 * DAY, 60, async (batch) => {
      const rows = await this.sparql(`
        SELECT ?e (MIN(?pub) AS ?published) (MIN(?st) AS ?start) (MAX(?en) AS ?end) (MIN(?pit) AS ?pointInTime)
          (MIN(?inc) AS ?inception)
          (SAMPLE(?tm) AS ?tmdbMovie) (SAMPLE(?tt) AS ?tmdbTv) (SAMPLE(?im) AS ?imdb) (SAMPLE(?tv) AS ?tvdb)
          (SAMPLE(?is) AS ?isbn) (SAMPLE(?ol) AS ?openLibrary) (SAMPLE(?aa) AS ?anilistAnime) (SAMPLE(?am) AS ?anilistManga)
        WHERE {
          VALUES ?e { ${values(batch)} }
          OPTIONAL { ?e wdt:P577 ?pub }
          OPTIONAL { ?e wdt:P580 ?st }
          OPTIONAL { ?e wdt:P582 ?en }
          OPTIONAL { ?e wdt:P585 ?pit }
          OPTIONAL { ?e wdt:P571 ?inc }
          OPTIONAL { ?e wdt:P4947 ?tm }
          OPTIONAL { ?e wdt:P4983 ?tt }
          OPTIONAL { ?e wdt:P345 ?im }
          OPTIONAL { ?e wdt:P4835 ?tv }
          OPTIONAL { ?e wdt:P212 ?is }
          OPTIONAL { ?e wdt:P648 ?ol }
          OPTIONAL { ?e wdt:P8729 ?aa }
          OPTIONAL { ?e wdt:P8731 ?am }
        } GROUP BY ?e`)
      const map = new Map()
      for (const row of rows) {
        map.set(qid(value(row, 'e')), {
          published: value(row, 'published'),
          start: value(row, 'start'),
          end: value(row, 'end'),
          pointInTime: value(row, 'pointInTime'),
          inception: value(row, 'inception'),
          ids: {
            tmdbMovie: value(row, 'tmdbMovie'),
            tmdbTv: value(row, 'tmdbTv'),
            imdb: value(row, 'imdb'),
            tvdb: value(row, 'tvdb'),
            isbn: value(row, 'isbn'),
            openLibrary: value(row, 'openLibrary'),
            anilistAnime: value(row, 'anilistAnime'),
            anilistManga: value(row, 'anilistManga'),
          },
        })
      }
      return map
    })
    const out = new Map()
    for (const id of unique(qids)) {
      const a = core.get(id)
      if (!a) continue
      out.set(id, { ...a, ...(extra.get(id) || { ids: {} }) })
    }
    return out
  }

  /**
   * Outgoing relations for works: universe, franchise, series (with ordinal), based on,
   * part of, main subject, set in period, characters, follows / followed by.
   * Returns Map<QID, [{ prop, target, ordinal }]>.
   */
  async edges(qids) {
    const found = await this.cachedBatch('edges:', qids, 14 * DAY, 40, async (batch) => {
      const rows = await this.sparql(`
        SELECT ?work ?prop ?target ?ordinal WHERE {
          VALUES ?work { ${values(batch)} }
          {
            VALUES (?p ?prop) {
              (wdt:P1434 "P1434") (wdt:P8345 "P8345") (wdt:P144 "P144") (wdt:P361 "P361") (wdt:P921 "P921")
              (wdt:P2408 "P2408") (wdt:P674 "P674") (wdt:P155 "P155") (wdt:P156 "P156")
            }
            ?work ?p ?target .
          } UNION {
            ?work p:P179 ?statement . ?statement ps:P179 ?target .
            OPTIONAL { ?statement pq:P1545 ?ordinal }
            BIND("P179" AS ?prop)
          }
          FILTER(isIRI(?target))
        }`)
      const map = new Map()
      for (const row of rows) {
        const work = qid(value(row, 'work'))
        if (!map.has(work)) map.set(work, [])
        map.get(work).push({ prop: value(row, 'prop'), target: qid(value(row, 'target')), ordinal: value(row, 'ordinal') })
      }
      return map
    })
    // Works without any relations are cached as null; callers want a list.
    for (const [key, list] of found) if (!list) found.set(key, [])
    return found
  }

  /**
   * Works that belong to a universe-like entity. For characters, the works they
   * appear in or that are based on them. Episodes and seasons are left out.
   */
  async members(rootQid, { character = false } = {}) {
    const found = await this.cachedBatch('members:', [rootQid + (character ? ':c' : '')], 7 * DAY, 1, async ([key]) => {
      const root = 'wd:' + key.replace(/:c$/, '')
      const patterns = character
        ? [`?work wdt:P674 ${root}`, `?work wdt:P144 ${root}`]
        : [
            `?work wdt:P1434 ${root}`,
            `?work wdt:P8345 ${root}`,
            `?work wdt:P179 ${root}`,
            `?work wdt:P144 ${root}`,
            `?work wdt:P361 ${root}`,
            `?work wdt:P179 ?series . ?series wdt:P179|wdt:P8345|wdt:P1434|wdt:P361 ${root}`,
          ]
      const rows = await this.sparql(`
        SELECT DISTINCT ?work WHERE {
          { ${patterns.join(' } UNION { ')} }
          FILTER NOT EXISTS { ?work wdt:P31 wd:Q21191270 }
          FILTER NOT EXISTS { ?work wdt:P31 wd:Q3464665 }
          FILTER NOT EXISTS { ?work wdt:P31 wd:Q5 }
        } LIMIT 800`)
      return new Map([[key, rows.map((row) => qid(value(row, 'work')))]])
    })
    return found.get(rootQid + (character ? ':c' : '')) || []
  }
}
