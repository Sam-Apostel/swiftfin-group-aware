// Seerr: posters and request status for movies and shows that aren't in the
// library yet, so the timeline can show them instead of blank cards. Optional.

import { fetchJson, trimSlash } from './util.mjs'

const STATUS = { 1: 'unknown', 2: 'pending', 3: 'processing', 4: 'partially-available', 5: 'available', 6: 'deleted' }

export class Seerr {
  constructor(url, apiKey) {
    this.url = trimSlash(url)
    this.apiKey = apiKey
  }

  get configured() {
    return Boolean(this.url && this.apiKey)
  }

  /** { posterPath, status } for "movie" / "tv" + TMDB id. */
  async lookup(mediaType, tmdbId) {
    const data = await fetchJson(this.url + '/api/v1/' + mediaType + '/' + encodeURIComponent(tmdbId), {
      headers: { 'X-Api-Key': this.apiKey },
      retries: 1,
      timeoutMs: 20000,
    })
    return {
      posterPath: data?.posterPath || null,
      status: STATUS[data?.mediaInfo?.status] || null,
    }
  }
}
