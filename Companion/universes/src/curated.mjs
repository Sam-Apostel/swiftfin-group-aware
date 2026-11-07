// Curated universes: small JSON files that add what Wikidata doesn't know, such as
// creator collaborations, hand-made watch orders and themes. Shipped files live in
// /app/universes; the owner's own files go in the data folder (data/universes/*.json)
// and win over shipped ones with the same id. Same idea as Kometa's shared configs.

import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

export function validateCurated(definition, file = 'universe') {
  const problems = []
  if (!definition || typeof definition !== 'object') return [file + ': not an object']
  if (!/^[a-z0-9-]{2,60}$/.test(definition.id || '')) problems.push(file + ': "id" must be lowercase letters, digits and dashes')
  if (!definition.name) problems.push(file + ': "name" is required')
  for (const pattern of definition.match?.titlePatterns || []) {
    try {
      new RegExp(pattern, 'i')
    } catch {
      problems.push(file + ': invalid title pattern ' + JSON.stringify(pattern))
    }
  }
  if (definition.entries && !Array.isArray(definition.entries)) problems.push(file + ': "entries" must be a list')
  return problems
}

export function loadCurated(dirs, log = () => {}) {
  const byId = new Map()
  for (const dir of dirs) {
    if (!existsSync(dir)) continue
    for (const name of readdirSync(dir).filter((file) => file.endsWith('.json')).sort()) {
      try {
        const definition = JSON.parse(readFileSync(join(dir, name), 'utf8'))
        const problems = validateCurated(definition, name)
        if (problems.length) {
          problems.forEach((problem) => log('curated: ' + problem))
          continue
        }
        byId.set(definition.id, definition)
      } catch (error) {
        log('curated: ' + name + ' is not valid JSON: ' + error.message)
      }
    }
  }
  return [...byId.values()]
}

/** A universe as a curated file, for sharing or hand-editing. */
export function exportCurated(universe) {
  return {
    id: universe.id.replace(/^(curated|wd|ai|yt|subject)-/, '').toLowerCase().replace(/[^a-z0-9-]/g, '-'),
    name: universe.name,
    kind: universe.kind,
    description: universe.description,
    theme: { preset: universe.theme?.preset },
    ...(universe.wikidata ? { match: { wikidata: [universe.wikidata] } } : {}),
    entries: universe.entries
      .filter((entry) => entry.status === 'confirmed')
      .map((entry) => ({
        title: entry.title,
        kind: entry.kind,
        year: entry.year,
        ids: Object.fromEntries(Object.entries(entry.externalIds).filter(([key]) => key !== 'tmdb')),
        ...(Number.isFinite(entry.positions.chronological) ? { chronological: entry.positions.chronological } : {}),
        ...(entry.positions.historical ? { historical: { start: entry.positions.historical.start, end: entry.positions.historical.end, label: entry.positions.historical.label } } : {}),
        ...(entry.lane ? { lane: entry.lane } : {}),
      })),
  }
}
