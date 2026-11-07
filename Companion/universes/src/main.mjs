// Couchfin Universes: entry point.

import { createServer } from 'node:http'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHandler } from './api.mjs'
import { defaultCuratedDirs, Pipeline } from './pipeline.mjs'
import { Settings } from './settings.mjs'
import { Store } from './store.mjs'
import { VERSION } from './util.mjs'

const appDir = join(dirname(fileURLToPath(import.meta.url)), '..')
const dataDir = process.env.DATA_DIR || '/data'
const port = Number(process.env.PORT || 7457)

class Logs {
  constructor(size = 300) {
    this.size = size
    this.buffer = []
  }

  add(message) {
    const line = new Date().toISOString().slice(0, 19).replace('T', ' ') + '  ' + message
    console.log(line)
    this.buffer.push(line)
    if (this.buffer.length > this.size) this.buffer.shift()
  }

  lines() {
    return this.buffer
  }
}

const logs = new Logs()
const log = (message) => logs.add(message)
const store = new Store(dataDir).load()
const settings = new Settings(dataDir).load()
const pipeline = new Pipeline({ store, settings, curatedDirs: defaultCuratedDirs(appDir, dataDir), log })

const server = createServer(createHandler({ store, settings, pipeline, logs }))
server.listen(port, () => log('Couchfin Universes ' + VERSION + ' listening on :' + port))

// Scan on start (once Jellyfin is set up) and then on the configured interval.
let timer = null
function schedule(delayMs) {
  clearTimeout(timer)
  timer = setTimeout(async () => {
    if (settings.value.jellyfinApiKey) await pipeline.scan('scheduled')
    schedule(Math.max(1, settings.value.scanIntervalHours) * 60 * 60 * 1000)
  }, delayMs)
}
const last = store.state.lastScan?.at ? Date.parse(store.state.lastScan.at) : 0
const interval = Math.max(1, settings.value.scanIntervalHours) * 60 * 60 * 1000
schedule(Math.max(15000, last + interval - Date.now()))

function shutdown() {
  log('Shutting down')
  try {
    store.saveNow()
  } catch (error) {
    console.error(error)
  }
  server.close(() => process.exit(0))
  setTimeout(() => process.exit(0), 3000).unref()
}
process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)
