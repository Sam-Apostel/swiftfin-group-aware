// The settings page umbrelOS opens. Plain server-rendered HTML; one small script
// refreshes the scan status while a scan runs.

const escape = (value) =>
  String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char])

const secretPlaceholder = (isSet) => (isSet ? 'Saved. Leave empty to keep, "-" to remove' : 'Not set')

const KIND_LABELS = {
  'fictional-universe': 'Fictional universe',
  franchise: 'Franchise',
  series: 'Series',
  character: 'Character',
  'creator-collab': 'Creators',
  'non-fiction': 'Non-fiction',
  playlist: 'Playlist',
}

export function renderPage({ status, settings, logs, universes, notice }) {
  const scan = status.scan
  const running = scan.state === 'running'
  const top = universes.sort((a, b) => b.counts.inLibrary - a.counts.inLibrary).slice(0, 60)
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Couchfin Universes</title>
<style>
  :root { color-scheme: light dark; --bg: #f6f5f2; --card: #fff; --text: #1d1d1f; --muted: #6e6e73; --line: #e2e0db; --accent: #6b4de6; --ok: #1f8a4c; --bad: #c0362c; }
  @media (prefers-color-scheme: dark) { :root { --bg: #111114; --card: #1c1c20; --text: #f2f2f4; --muted: #a1a1a8; --line: #2c2c32; --accent: #9d86ff; --ok: #4cc27c; --bad: #ff6b5f; } }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 880px; margin: 0 auto; padding: 32px 16px 64px; }
  h1 { font-size: 28px; margin: 0 0 4px; letter-spacing: -0.02em; }
  h2 { font-size: 18px; margin: 0 0 12px; }
  p.lead { color: var(--muted); margin: 0 0 24px; }
  section { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 20px; margin-bottom: 16px; }
  label { display: block; font-weight: 600; margin: 14px 0 4px; }
  label small, .hint { display: block; font-weight: 400; color: var(--muted); font-size: 13px; }
  input[type=text], input[type=password], input[type=number], select, textarea { width: 100%; padding: 9px 11px; border-radius: 9px; border: 1px solid var(--line); background: var(--bg); color: var(--text); font: inherit; }
  textarea { min-height: 72px; }
  .row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  @media (max-width: 600px) { .row { grid-template-columns: 1fr; } }
  button { background: var(--accent); color: #fff; border: 0; border-radius: 999px; padding: 10px 20px; font: inherit; font-weight: 600; cursor: pointer; }
  button.secondary { background: transparent; color: var(--accent); border: 1px solid var(--accent); }
  button:disabled { opacity: .5; cursor: default; }
  .actions { display: flex; gap: 10px; margin-top: 18px; flex-wrap: wrap; }
  .notice { background: color-mix(in srgb, var(--accent) 12%, var(--card)); border-color: var(--accent); }
  .pill { display: inline-block; padding: 2px 10px; border-radius: 999px; font-size: 13px; border: 1px solid var(--line); margin: 0 6px 6px 0; }
  .ok { color: var(--ok); } .bad { color: var(--bad); }
  .stats { display: flex; gap: 24px; flex-wrap: wrap; }
  .stats div strong { display: block; font-size: 24px; }
  .stats div span { color: var(--muted); font-size: 13px; }
  pre { background: var(--bg); border-radius: 9px; padding: 12px; overflow-x: auto; font-size: 12px; max-height: 260px; white-space: pre-wrap; word-break: break-word; }
  ul.universes { list-style: none; padding: 0; margin: 0; columns: 2; }
  @media (max-width: 600px) { ul.universes { columns: 1; } }
  ul.universes li { break-inside: avoid; padding: 6px 0; border-bottom: 1px solid var(--line); }
  ul.universes li span { color: var(--muted); font-size: 13px; }
  .review { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 10px 0; border-bottom: 1px solid var(--line); }
  .review form { display: flex; gap: 6px; }
  .review button { padding: 6px 14px; }
</style>
</head>
<body>
<main>
  <h1>Couchfin Universes</h1>
  <p class="lead">Links your library into shared worlds, timelines and backlogs for Couchfin. Open a movie or show in Couchfin to see the universes it belongs to.</p>

  ${notice ? `<section class="notice">${escape(notice)}</section>` : ''}

  <section>
    <h2>Status</h2>
    <div class="stats">
      <div><strong>${status.counts.universes}</strong><span>universes</span></div>
      <div><strong>${status.counts.libraryItems}</strong><span>library items read</span></div>
      <div><strong>${status.counts.reviews}</strong><span>suggestions to review</span></div>
    </div>
    <p id="scan-state">${running ? 'Scanning: ' + escape(scan.step || '') + progressText(scan.progress) : status.lastScan ? 'Last scan ' + escape(new Date(status.lastScan.at).toLocaleString()) : 'Not scanned yet.'}${scan.error ? ` <span class="bad">${escape(scan.error)}</span>` : ''}</p>
    <div>
      <span class="pill ${status.configured.jellyfin ? 'ok' : 'bad'}">Jellyfin ${status.configured.jellyfin ? 'connected' : 'needs an API key'}</span>
      <span class="pill">${status.configured.seerr ? 'Seerr posters on' : 'Seerr off'}</span>
      <span class="pill">${status.configured.ai ? 'AI: ' + escape(status.configured.aiProvider) : 'AI off'}</span>
      <span class="pill">${status.configured.youtube ? 'YouTube on' : 'YouTube off'}</span>
    </div>
    <form method="post" action="/scan" class="actions"><button ${running || !status.configured.jellyfin ? 'disabled' : ''}>Scan now</button></form>
  </section>

  <form method="post" action="/settings">
    <section>
      <h2>Jellyfin</h2>
      <label>Server URL <small>On umbrelOS: http://jellyfin_server_1:8096</small></label>
      <input type="text" name="jellyfinUrl" value="${escape(settings.jellyfinUrl)}">
      <label>API key <small>Jellyfin → Dashboard → API Keys → +. Read-only use: the library is read, nothing is changed.</small></label>
      <input type="password" name="jellyfinApiKey" placeholder="${escape(secretPlaceholder(settings.jellyfinApiKey))}" autocomplete="off">
    </section>

    <section>
      <h2>Wikidata</h2>
      <label><input type="checkbox" name="wikidata" ${settings.wikidata.enabled ? 'checked' : ''}> Look up franchises, universes, books and comics on Wikidata</label>
      <p class="hint">Only external ids (TMDB, IMDb, TVDB) of your library leave the server, as public SPARQL queries to query.wikidata.org.</p>
    </section>

    <section>
      <h2>Seerr</h2>
      <p class="hint">Optional: posters and request status for movies and shows you don't have yet. Filled in automatically on umbrelOS.</p>
      <div class="row">
        <div><label>URL</label><input type="text" name="seerrUrl" value="${escape(settings.seerrUrl)}"></div>
        <div><label>API key</label><input type="password" name="seerrApiKey" placeholder="${escape(secretPlaceholder(settings.seerrApiKey))}" autocomplete="off"></div>
      </div>
    </section>

    <section>
      <h2>AI tagging</h2>
      <p class="hint">Optional. Places YouTube videos and documentaries in universes and on the history timeline, suggests in-universe order and picks themes for universes the rules don't recognise. Suggestions it isn't sure about wait for a yes or no in Couchfin. Run it on the Umbrel with the Ollama app to keep everything local.</p>
      <label>Provider</label>
      <select name="llmProvider">
        ${['none', 'ollama', 'openai-compatible', 'anthropic'].map((provider) => `<option value="${provider}" ${settings.llm.provider === provider ? 'selected' : ''}>${{ none: 'Off', ollama: 'Ollama (local)', 'openai-compatible': 'OpenAI-compatible server (local, e.g. LM Studio)', anthropic: 'Claude (Anthropic API, cloud)' }[provider]}</option>`).join('')}
      </select>
      <div class="row">
        <div><label>Server URL <small>Ollama: e.g. http://umbrel.local:11434. Not used for Claude.</small></label><input type="text" name="llmBaseUrl" value="${escape(settings.llm.baseUrl)}"></div>
        <div><label>Model <small>e.g. qwen3:8b for Ollama. Claude: empty uses claude-opus-5-5.</small></label><input type="text" name="llmModel" value="${escape(settings.llm.model)}"></div>
      </div>
      <div class="row">
        <div><label>API key <small>Claude, or a server that needs one.</small></label><input type="password" name="llmApiKey" placeholder="${escape(secretPlaceholder(settings.llm.apiKey))}" autocomplete="off"></div>
        <div><label>New questions per scan <small>Answers are cached, so only new videos count.</small></label><input type="number" name="llmMaxCalls" min="0" max="5000" value="${escape(settings.llm.maxCallsPerScan)}"></div>
      </div>
    </section>

    <section>
      <h2>YouTube backlogs</h2>
      <p class="hint">Each playlist becomes a backlog universe, mixed with the rest of your library. Videos downloaded with TubeArchivist or Pinchflat play from Jellyfin; the others open in the YouTube app. Needs a YouTube Data API key (Google Cloud console, free quota); playlists must be public or unlisted.</p>
      <label>YouTube Data API key</label>
      <input type="password" name="youtubeApiKey" placeholder="${escape(secretPlaceholder(settings.youtube.apiKey))}" autocomplete="off">
      <label>Playlists <small>One URL or id per line.</small></label>
      <textarea name="youtubePlaylists">${escape(settings.youtube.playlists.join('\n'))}</textarea>
    </section>

    <section>
      <h2>Schedule</h2>
      <label>Scan every (hours)</label>
      <input type="number" name="scanIntervalHours" min="1" max="168" value="${escape(settings.scanIntervalHours)}">
      <div class="actions"><button type="submit">Save</button></div>
    </section>
  </form>

  <section id="reviews">
    <h2>Suggestions</h2>
    <p class="hint">Couchfin asks the same questions on the item pages. Answers are kept across scans.</p>
    <div id="review-list"><p class="hint">Loading…</p></div>
  </section>

  <section>
    <h2>Universes</h2>
    ${top.length ? `<ul class="universes">${top.map((universe) => `<li>${escape(universe.name)} <span>· ${escape(KIND_LABELS[universe.kind] || universe.kind)} · ${universe.counts.inLibrary}/${universe.counts.entries} in library</span></li>`).join('')}</ul>` : '<p class="hint">None yet. Connect Jellyfin and scan.</p>'}
  </section>

  <section>
    <h2>Log</h2>
    <pre id="log">${escape(logs.slice(-40).join('\n'))}</pre>
  </section>
</main>
<script>
  const escapeHtml = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  async function loadReviews() {
    const list = document.getElementById('review-list');
    try {
      const { reviews } = await (await fetch('/ui/reviews')).json();
      if (!reviews.length) { list.innerHTML = '<p class="hint">Nothing to review.</p>'; return; }
      list.innerHTML = reviews.slice(0, 50).map((r) =>
        '<div class="review"><div>' + escapeHtml(r.question) + (r.reason ? '<br><span class="hint">' + escapeHtml(r.reason) + '</span>' : '') + '</div>' +
        '<form method="post" action="/reviews"><input type="hidden" name="id" value="' + escapeHtml(r.id) + '">' +
        '<button name="decision" value="accept">Yes</button><button class="secondary" name="decision" value="reject">No</button></form></div>').join('');
    } catch { list.innerHTML = '<p class="hint">Could not load suggestions.</p>'; }
  }
  async function poll() {
    try {
      const status = await (await fetch('/ui/status')).json();
      const state = document.getElementById('scan-state');
      if (status.scan.state === 'running') {
        const p = status.scan.progress;
        state.textContent = 'Scanning: ' + (status.scan.step || '') + (p && p.total ? ' (' + p.done + ' of ' + p.total + ')' : '');
        setTimeout(poll, 2000);
      } else if (state.textContent.startsWith('Scanning')) {
        location.reload();
      }
      document.getElementById('log').textContent = status.logs.join('\\n');
    } catch { setTimeout(poll, 5000); }
  }
  loadReviews();
  ${running ? 'poll();' : ''}
</script>
</body>
</html>`
}

function progressText(progress) {
  return progress && progress.total ? ' (' + progress.done + ' of ' + progress.total + ')' : ''
}
