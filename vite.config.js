import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'node:fs'
import path from 'node:path'

const FILE = path.resolve('data.json')

function iso(d) {
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

function defaults() {
  const now = new Date()
  const end = new Date(now.getFullYear(), now.getMonth() + 6, now.getDate())
  return { startDate: iso(now), endDate: iso(end), goal: 0, loanAmount: 0, apr: 0, loanYears: 5, entries: [] }
}

function read() {
  try {
    return JSON.parse(fs.readFileSync(FILE, 'utf8'))
  } catch {
    return defaults()
  }
}

// Last-modified time of data.json; pages poll it to notice changes made on other devices.
function version() {
  try {
    return fs.statSync(FILE).mtimeMs
  } catch {
    return 0
  }
}

function api(req, res, next) {
  if (!req.url.startsWith('/api/')) return next()
  res.setHeader('Content-Type', 'application/json')
  res.setHeader('Cache-Control', 'no-store')
  if (req.url.startsWith('/api/version')) return res.end(JSON.stringify({ version: version() }))
  if (!req.url.startsWith('/api/data')) return next()
  if (req.method === 'GET') {
    res.setHeader('X-Version', String(version()))
    return res.end(JSON.stringify(read()))
  }
  if (req.method === 'PUT') {
    let body = ''
    req.on('data', (c) => (body += c))
    req.on('end', () => {
      try {
        const data = JSON.parse(body)
        fs.writeFileSync(FILE + '.tmp', JSON.stringify(data, null, 2))
        fs.renameSync(FILE + '.tmp', FILE)
        res.end(JSON.stringify({ ok: true, version: version() }))
      } catch (e) {
        res.statusCode = 400
        res.end(JSON.stringify({ error: String(e) }))
      }
    })
    return
  }
  res.statusCode = 405
  res.end()
}

const dataApi = {
  name: 'data-api',
  configureServer(s) {
    s.middlewares.use(api)
  },
  configurePreviewServer(s) {
    s.middlewares.use(api)
  },
}

export default defineConfig({
  plugins: [react(), dataApi],
  // Fixed port (away from Vite's default 5173); strictPort fails instead of silently picking another.
  server: { host: true, port: 8420, strictPort: true, watch: { ignored: ['**/data.json', '**/data.json.tmp'] } },
  preview: { host: true, port: 8420, strictPort: true },
})
