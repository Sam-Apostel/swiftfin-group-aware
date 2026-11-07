# Couchfin companions

Services that run next to Jellyfin and give Couchfin things Jellyfin doesn't have.

## Universes

`universes/` is a small Node service; `umbrel/couchfin-universes/` is its app for the
Couchfin Umbrel store ([Sam-Apostel/umbrel-apps](https://github.com/Sam-Apostel/umbrel-apps)).

It turns the Jellyfin library into **universes**: shared worlds, franchises, series,
creator collaborations, non-fiction history, and YouTube backlogs. Couchfin shows them on
item pages ("Part of"), in Discover, and as themed timelines.

### How a scan works

1. **Jellyfin**: reads movies, shows, videos and YouTube episodes (TubeArchivist, Pinchflat and
   yt-dlp file names carry the video id) with the owner's API key. Read-only.
2. **Wikidata**: matches items by TMDB / IMDb / TVDB id, follows *fictional universe*,
   *media franchise*, *part of the series*, *based on*, *characters* and *main subject*, and
   pulls in every work of those universes: films, shows, novels, comics, games. That's how
   Wednesday leads to the Addams Family films, and Avatar to the Kyoshi novels. Only external
   ids leave the server, as public SPARQL queries.
3. **YouTube** (optional, Data API key): each playlist becomes a backlog universe.
4. **Seerr** (optional, found automatically on umbrelOS): posters and request status for
   what's not in the library, so it can be requested from the timeline.
5. **AI** (optional): Ollama or an OpenAI-compatible server on the Umbrel, or Claude. It places
   videos and documentaries in universes and on the history timeline, suggests in-universe
   order, and picks themes for universes the rules don't recognise. Guesses below 80%
   confidence wait for a yes/no in Couchfin. Answers are cached by input, and there's a
   per-scan cap.
6. **Curated files** (`universes/*.json`, plus the owner's own in the data folder) add
   creator collaborations such as Hermitcraft Season 11, watch orders and themes. See
   `universes/universes/README.md`.

Themes are presets (`cinematic`, `cosmic`, `heroic`, `mythic`, `gothic`, `ink`, `blocky`,
`playful`, `deep-time`, `backlog`). Couchfin draws each preset with its own typeface and
procedural texture, and takes the colour from the universe's artwork.

### API

Every `/api/v1` call except `ping` needs the person's Jellyfin token (`X-Emby-Token` or the
`MediaBrowser … Token="…"` header). The service checks it with Jellyfin.

| | |
| --- | --- |
| `GET /api/v1/ping` | `{ service: "couchfin-universes" }`, used for discovery |
| `GET /api/v1/universes` | summaries |
| `GET /api/v1/universes/:id` | a universe with its entries, timelines and relations |
| `GET /api/v1/universes/:id/export` | the universe as a curated file |
| `GET /api/v1/items/:jellyfinId/universes?alsoId=` | universes an item (or its series) belongs to |
| `GET /api/v1/reviews` · `POST /api/v1/reviews/:id {decision}` | AI suggestions waiting for a yes/no |
| `POST /api/v1/universes/:id/entries/:entryId/decision` | "Not part of this universe" |
| `POST /api/v1/scan` | Jellyfin admins only |

The settings page (`/`) sits behind Umbrel's login. `/api/*` doesn't, because Couchfin
signs in with Jellyfin instead.

### Develop

```sh
cd Companion/universes
npm install
npm test
DATA_DIR=./data PORT=7457 npm start   # then open http://localhost:7457
```

### Release

1. Bump `version` in `universes/package.json` and merge. The **Companion: Universes**
   workflow publishes `ghcr.io/sam-apostel/couchfin-universes:<version>` for amd64 and arm64.
   The first time, set the package to public on GitHub (Package settings → Change
   visibility) so umbrelOS can pull it.
2. `Companion/umbrel/pin-image.sh <version> ../umbrel-apps` pins the digest and copies the
   app into the store checkout. Commit it there.
