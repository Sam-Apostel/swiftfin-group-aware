# Couchfin settings & menus audit

The starting point: 13 settings screens reached from 2 different roots, the most-used
options (player, subtitles, skip lengths, autoplay) 2–3 levels deep behind a row called
"Advanced", the same key exposed in several places, and a device-profile editor 6 levels
deep. This is what changed and what's still open.

## New map

```
Settings (sheet from the couch avatars on iOS · Settings tab on tvOS)
├─ Couch card ............ who's on the couch, "browsing as" + [Change who's watching]
├─ Watching
│  ├─ Playback ........... Player · Quality › · While watching (autoplay, skip back/forward,
│  │                       rewind on resume, remaining time) · Controls (bar/menu buttons,
│  │                       gestures, supplements, chapter slider, scrub preview)
│  ├─ Audio & subtitles .. languages, subtitle mode, remember, burn-in, subtitle look
│  └─ Couch & kids ....... kid-safe browsing, hide watched, who's a kid
├─ Look
│  ├─ Home & libraries ... home rows, library layout/filters/letter picker, search filters,
│  │                       tvOS tab bar layout
│  └─ Posters & item pages  poster labels/indicators + item page style, trailers, buttons
├─ Connections
│  ├─ <you> .............. account, password, Quick Connect, lock (PIN / Face ID)
│  ├─ Server ............. name, version, connections
│  ├─ Requests ........... Seerr (iOS)
│  └─ Server dashboard ... admins only (iOS)
└─ About Couchfin ........ version, permissions, splash screen, sign-out on close /
                           background, logs, experimental, debug, source & license
```

The couch picker's "…" menu opens the same **About Couchfin** screen, so the
pre-sign-in "Advanced" sheet no longer exists as a second, different settings root.

## Decisions

| What | Before | Now | Why |
|---|---|---|---|
| Player choice, quality, autoplay, skip lengths | Settings › Advanced › Video player (depth 2) | Settings › Playback (depth 1) | Most-changed settings, buried under "Advanced" |
| Audio & subtitle languages | Two sections of Video player with identical labels ("Preferred language" ×2, "Remember track selection" ×2) | Own screen, Audio & subtitles | Clear grouping |
| Gestures, Supplements, Slider, Timestamp, Resume | 5 sections, 4 of them a single row | 2 sections: While watching, Controls | Less scrolling, same reach |
| Libraries / Items | Separate screens under Advanced (depth 2, filters at 3) | Embedded in Home & libraries / Posters & item pages | One level less; related options together |
| Appearance (×2 keys: `userAppearance`, `appAppearance`) | Picker in two places, one hidden while splash is on | Removed — always dark | The identity is dark water |
| Accent color | ColorPicker | Removed — fin-blue tint | Brand colour; Increased Contrast still lightens it |
| App icon picker (6 Jellyfin-blob colours) | About › App icon | Removed | One Couchfin icon |
| About | Only reachable before sign-in | Settings root and couch picker | Was unreachable in a session |
| Logs / Debug | In both Settings and App settings | About › Diagnostics | One place |
| Experimental | Always on the Settings root | About › Diagnostics | Power-user only |
| "Sign out on close" footer + "Sign out on background" | Two sections | One section, one footer | Same concern |
| `IndicatorSettingsView`, `.itemSettings`, `.librarySettings`, `.indicatorSettings` routes | Orphaned / superseded | Deleted | Dead code |

## Still open (recommendations, not done yet)

1. **Autoplay is written from two places.** Adding/removing the autoplay player button
   silently rewrites the server's `enableNextEpisodeAutoPlay`. Make the button a pure
   shortcut for the toggle in Playback.
2. **Colliding Defaults keys.** `VideoPlayer.appMaximumBitrate` and
   `VideoPlayer.Playback.appMaximumBitrate` share the stored key `appMaximumBitrate` with
   different defaults (same for `appMaximumBitrateTest`); one is still read by
   `MediaPlayerManager`. Pick one.
3. **Dead keys:** `VideoPlayer.autoPlayEnabled`, `Experimental.downloads`,
   `Customization.*PosterType` (5), and the now-unused `userAppearance`,
   `appAppearance`, `userAccentColor`.
4. **Device profiles** (Quality › Profiles › Custom profile › codecs = depth 4–6): move
   behind a single "Advanced" disclosure inside Quality.
5. **Kid flag in two places** (Couch & kids list + long-press on the couch picker) — keep
   both, they're the same `UserState.isKid`; fine.
6. **Library layout in two places** (settings default + per-library menu) — label the
   settings one "Default layout".
7. **tvOS `confirmClose`, `Library.cinematicBackground`, `Transition.pauseOnBackground`**
   are read but have no UI. Either surface them in Playback / Home & libraries or drop them.
8. **Strings:** the Experimental labels are hard-coded English; "Swiftfin" still appears
   in a couple of footers (kid-safe browsing, Seerr errors).
