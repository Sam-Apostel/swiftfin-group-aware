// Jellyfin: reads the library with the owner's API key, and checks the access
// tokens Couchfin sends so only people on this Jellyfin server can use the API.

import { basename, extname } from 'node:path'
import { fetchJson, trimSlash } from './util.mjs'

const PAGE = 500
const FIELDS = ['ProviderIds', 'Path', 'PremiereDate', 'ProductionYear', 'Genres', 'Overview', 'SeriesId', 'SeriesName', 'Tags'].join(',')

function authHeader(token) {
  return {
    Authorization: 'MediaBrowser Client="Couchfin Universes", Device="Umbrel", DeviceId="couchfin-universes", Version="1.0.0", Token="' + token + '"',
  }
}

/** YouTube video id from a downloaded file: yt-dlp's "Title [id].mkv", or TubeArchivist's "<id>.mp4". */
export function youtubeIdFromPath(path) {
  if (!path) return null
  const name = basename(String(path), extname(String(path)))
  const bracketed = /\[([A-Za-z0-9_-]{11})\](?!.*\[[A-Za-z0-9_-]{11}\])/.exec(name)
  if (bracketed) return bracketed[1]
  // A bare 11-character name only counts when it looks random: a digit, - or _, or a capital
  // letter after the first character (so "Interstella.mkv" isn't mistaken for a video id).
  if (/^[A-Za-z0-9_-]{11}$/.test(name) && (/[0-9_-]/.test(name) || (/.[A-Z]/.test(name) && /[a-z]/.test(name)))) return name
  return null
}

function providerId(ids, ...names) {
  if (!ids) return null
  for (const name of names) {
    for (const [key, value] of Object.entries(ids)) {
      if (key.toLowerCase() === name.toLowerCase() && value) return String(value)
    }
  }
  return null
}

/** Normalises a Jellyfin BaseItemDto into what the pipeline needs. */
export function toLibraryItem(dto) {
  const youtubeId = providerId(dto.ProviderIds, 'YouTube', 'Youtube', 'YoutubeMetadata') || youtubeIdFromPath(dto.Path)
  return {
    id: dto.Id,
    type: dto.Type,
    name: dto.Name || '',
    year: dto.ProductionYear || (dto.PremiereDate ? Number(String(dto.PremiereDate).slice(0, 4)) : null),
    premiereDate: dto.PremiereDate ? String(dto.PremiereDate).slice(0, 10) : null,
    genres: dto.Genres || [],
    tags: dto.Tags || [],
    overview: (dto.Overview || '').slice(0, 800),
    seriesId: dto.SeriesId || null,
    seriesName: dto.SeriesName || null,
    ids: {
      tmdb: providerId(dto.ProviderIds, 'Tmdb'),
      imdb: providerId(dto.ProviderIds, 'Imdb'),
      tvdb: providerId(dto.ProviderIds, 'Tvdb'),
      youtube: youtubeId,
    },
  }
}

export class Jellyfin {
  constructor(url, apiKey) {
    this.url = trimSlash(url)
    this.apiKey = apiKey
  }

  get configured() {
    return Boolean(this.url && this.apiKey)
  }

  async get(path, token = this.apiKey) {
    return fetchJson(this.url + path, { headers: authHeader(token), timeoutMs: 120000 })
  }

  async ping() {
    return this.get('/System/Info')
  }

  /**
   * Movies, series, standalone videos, and episodes that came from YouTube
   * (TubeArchivist / Pinchflat / yt-dlp libraries map a channel to a series).
   */
  async library(onProgress = () => {}) {
    const items = []
    for (let start = 0; ; start += PAGE) {
      const query = new URLSearchParams({
        Recursive: 'true',
        IncludeItemTypes: 'Movie,Series,Video,MusicVideo,Episode',
        Fields: FIELDS,
        StartIndex: String(start),
        Limit: String(PAGE),
        EnableImages: 'false',
        EnableUserData: 'false',
        SortBy: 'SortName',
      })
      const page = await this.get('/Items?' + query)
      const dtos = page?.Items || []
      for (const dto of dtos) {
        const item = toLibraryItem(dto)
        // Ordinary TV episodes belong to their series; only YouTube episodes stand on their own.
        if (item.type === 'Episode' && !item.ids.youtube) continue
        items.push(item)
      }
      onProgress(Math.min(start + dtos.length, page?.TotalRecordCount || 0), page?.TotalRecordCount || 0)
      if (dtos.length < PAGE) break
    }
    return items
  }

  /** Validates a person's access token; returns { id, name, isAdmin } or throws. */
  async whoAmI(token) {
    const me = await this.get('/Users/Me', token)
    return { id: me.Id, name: me.Name, isAdmin: Boolean(me.Policy?.IsAdministrator) }
  }
}

/** Extracts the token from the headers Jellyfin clients send. */
export function tokenFromHeaders(headers) {
  const direct = headers['x-emby-token'] || headers['x-mediabrowser-token']
  if (direct) return String(direct)
  const auth = headers['authorization'] || headers['x-emby-authorization'] || ''
  const match = /Token="([^"]+)"/i.exec(auth)
  if (match) return match[1]
  const bearer = /^Bearer\s+(.+)$/i.exec(auth)
  return bearer ? bearer[1].trim() : null
}
