// Themes are parameters for a fixed design system, not hand-made designs: Couchfin
// draws each preset (typeface, texture, timeline style) and takes the colours from
// the artwork on the device. Here we only decide which preset fits.

export const PRESETS = {
  cinematic: { typeface: 'sans', texture: 'grain', timelineStyle: 'years' },
  cosmic: { typeface: 'futuristic', texture: 'starfield', timelineStyle: 'years' },
  heroic: { typeface: 'condensed', texture: 'halftone', timelineStyle: 'phases' },
  mythic: { typeface: 'serif', texture: 'parchment', timelineStyle: 'eras' },
  gothic: { typeface: 'serif', texture: 'grain', timelineStyle: 'years' },
  ink: { typeface: 'serif', texture: 'ink', timelineStyle: 'eras' },
  blocky: { typeface: 'mono', texture: 'pixel', timelineStyle: 'seasons' },
  playful: { typeface: 'rounded', texture: 'paper', timelineStyle: 'years' },
  'deep-time': { typeface: 'sans', texture: 'strata', timelineStyle: 'history' },
  backlog: { typeface: 'rounded', texture: 'none', timelineStyle: 'queue' },
}

export const PRESET_NAMES = Object.keys(PRESETS)

const RULES = [
  { preset: 'blocky', words: ['minecraft', 'hermitcraft', 'smp', 'pixel', 'lego'] },
  { preset: 'heroic', words: ['marvel', 'dc ', 'dc comics', 'arrowverse', 'superhero', 'avengers', 'x-men', 'spider-man', 'batman', 'superman', 'justice league'] },
  { preset: 'cosmic', words: ['star wars', 'star trek', 'dune', 'alien', 'stargate', 'battlestar', 'expanse', 'galaxy', 'space'] },
  { preset: 'ink', words: ['avatar: the last airbender', 'legend of korra', 'world of avatar', 'ghibli', 'naruto', 'dragon ball', 'one piece'] },
  { preset: 'mythic', words: ['middle-earth', 'tolkien', 'lord of the rings', 'hobbit', 'witcher', 'game of thrones', 'a song of ice and fire', 'narnia', 'wizarding world', 'harry potter'] },
  { preset: 'gothic', words: ['addams', 'dracula', 'frankenstein', 'conjuring', 'vampire', 'halloween', 'tim burton'] },
]

const GENRE_PRESETS = [
  { preset: 'heroic', genres: ['superhero'] },
  { preset: 'cosmic', genres: ['science fiction', 'sci-fi', 'sci-fi & fantasy'] },
  { preset: 'gothic', genres: ['horror', 'thriller'] },
  { preset: 'mythic', genres: ['fantasy'] },
  { preset: 'playful', genres: ['animation', 'family', 'kids', 'comedy'] },
  { preset: 'deep-time', genres: ['documentary', 'history'] },
]

/**
 * Picks a preset from the universe's name, kind and its library genres.
 * `override` (from a curated file or the LLM) wins when it names a known preset.
 */
export function chooseTheme({ name = '', kind = '', genres = [], override = null, eras = null } = {}) {
  let preset = PRESET_NAMES.includes(override?.preset) ? override.preset : null
  let basis = preset ? 'override' : null

  if (!preset) {
    if (kind === 'playlist') preset = 'backlog'
    else if (kind === 'non-fiction') preset = 'deep-time'
    if (preset) basis = 'kind'
  }

  const lowerName = ' ' + String(name).toLowerCase() + ' '
  if (!preset) {
    for (const rule of RULES) {
      if (rule.words.some((word) => lowerName.includes(word))) {
        preset = rule.preset
        basis = 'name'
        break
      }
    }
  }

  if (!preset && genres.length) {
    const counts = new Map()
    for (const genre of genres) {
      const lower = String(genre).toLowerCase()
      for (const rule of GENRE_PRESETS) {
        if (rule.genres.includes(lower)) counts.set(rule.preset, (counts.get(rule.preset) || 0) + 1)
      }
    }
    const best = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]
    // Only follow a genre when it's typical for the universe, not one stray film.
    if (best && best[1] >= Math.max(1, genres.length * 0.25)) {
      preset = best[0]
      basis = 'genre'
    }
  }

  if (!preset) {
    preset = kind === 'creator-collab' ? 'playful' : 'cinematic'
    basis = 'default'
  }
  return { preset, basis, ...PRESETS[preset], ...(override?.accent ? { accent: override.accent } : {}), eras: eras || null }
}
