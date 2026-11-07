# Curated universes

Wikidata already knows most franchises, fictional universes and series. These files
add what it doesn't: creator collaborations, hand-made watch orders, themes.

Put your own files in the app's data folder (`data/universes/*.json` on the Umbrel);
a file with the same `id` as a shipped one replaces it. Rescan to apply.

```jsonc
{
  "id": "my-universe",                 // lowercase letters, digits, dashes
  "name": "My universe",
  "kind": "franchise",                 // fictional-universe | franchise | series | creator-collab | non-fiction
  "description": "Optional.",
  "theme": { "preset": "mythic" },     // cinematic | cosmic | heroic | mythic | gothic | ink | blocky | playful | deep-time | backlog
  "parents": ["other-curated-id"],     // nests this universe inside another curated one
  "lanes": "channel",                  // one lane per YouTube channel on the timeline
  "eras": [{ "label": "Phase One", "start": 2008, "end": 2012 }],
  "match": {
    "titlePatterns": ["regex, case-insensitive"],
    "channels": ["Only videos from these channels"],
    "wikidata": ["Q642878"],           // include everything Wikidata puts in these universes
    "historical": true                 // include every non-fiction entry with a real-world date
  },
  "entries": [
    // Matched to the library (and to Wikidata entries) by any of the ids.
    { "title": "Iron Man", "kind": "movie", "year": 2008, "ids": { "tmdbMovie": "1726" }, "chronological": 3 },
    { "title": "A book", "kind": "book", "ids": { "isbn": "9781419735042" }, "historical": { "start": -2000, "end": -1500, "label": "Bronze Age" } }
  ]
}
```

`GET /api/v1/universes/<id>/export` turns any universe into this format, a good start for your own edits.
