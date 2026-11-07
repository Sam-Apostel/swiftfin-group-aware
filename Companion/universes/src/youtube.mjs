// YouTube playlists as backlogs, through the YouTube Data API (an API key from
// Google Cloud, read-only, free quota). Only metadata is read; videos are watched
// in the YouTube app or from what TubeArchivist / Pinchflat downloaded into Jellyfin.

import { fetchJson } from './util.mjs'

const API = 'https://www.googleapis.com/youtube/v3/'

export async function fetchPlaylist(apiKey, playlistId, { maxVideos = 500 } = {}) {
  const meta = await fetchJson(API + 'playlists?' + new URLSearchParams({ part: 'snippet', id: playlistId, key: apiKey }))
  const snippet = meta?.items?.[0]?.snippet
  if (!snippet) throw new Error('playlist ' + playlistId + ' not found (is it private?)')

  const videos = []
  let pageToken = ''
  do {
    const query = new URLSearchParams({ part: 'snippet,contentDetails', playlistId, maxResults: '50', key: apiKey })
    if (pageToken) query.set('pageToken', pageToken)
    const page = await fetchJson(API + 'playlistItems?' + query)
    for (const item of page?.items || []) {
      const id = item.contentDetails?.videoId
      const title = item.snippet?.title
      // Deleted and private videos stay in playlists as placeholders.
      if (!id || !title || title === 'Deleted video' || title === 'Private video') continue
      videos.push({
        id,
        title,
        channel: item.snippet?.videoOwnerChannelTitle || null,
        publishedAt: item.contentDetails?.videoPublishedAt || null,
        description: (item.snippet?.description || '').slice(0, 600),
        thumbnail: item.snippet?.thumbnails?.high?.url || item.snippet?.thumbnails?.medium?.url || null,
      })
    }
    pageToken = page?.nextPageToken || ''
  } while (pageToken && videos.length < maxVideos)

  return {
    title: snippet.title,
    description: (snippet.description || '').slice(0, 600),
    channel: snippet.channelTitle || null,
    videos,
    fetchedAt: new Date().toISOString(),
  }
}
