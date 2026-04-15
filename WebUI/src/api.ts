// Tiny client for Controllarr's qBittorrent-compatible API + the
// Controllarr-native endpoints. All calls are relative so this works
// whether we're served out of the .app bundle or a Vite dev server
// proxy.

export type Torrent = {
  hash: string
  name: string
  size: number
  progress: number
  dlspeed: number
  upspeed: number
  state: string
  save_path: string
  category: string
  added_on: number
  completed: number
  ratio: number
  num_seeds: number
  num_leechs: number
  eta: number
}

export type SessionStats = {
  downloadRate: number
  uploadRate: number
  totalDownloaded: number
  totalUploaded: number
  numTorrents: number
  numPeers: number
  hasIncoming: boolean
  listenPort: number
}

async function form(path: string, fields: Record<string, string>) {
  const body = new URLSearchParams(fields).toString()
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!res.ok) throw new Error(`${path} -> ${res.status}`)
  return res
}

export const api = {
  async login(username: string, password: string) {
    await form('/api/v2/auth/login', { username, password })
  },
  async torrents(): Promise<Torrent[]> {
    const res = await fetch('/api/v2/torrents/info')
    return (await res.json()) as Torrent[]
  },
  async stats(): Promise<SessionStats> {
    const res = await fetch('/api/controllarr/stats')
    return (await res.json()) as SessionStats
  },
  async addMagnet(uri: string, category?: string) {
    const fields: Record<string, string> = { urls: uri }
    if (category) fields.category = category
    await form('/api/v2/torrents/add', fields)
  },
  async pause(hash: string) {
    await form('/api/v2/torrents/pause', { hashes: hash })
  },
  async resume(hash: string) {
    await form('/api/v2/torrents/resume', { hashes: hash })
  },
  async remove(hash: string, deleteFiles: boolean) {
    await form('/api/v2/torrents/delete', {
      hashes: hash,
      deleteFiles: String(deleteFiles),
    })
  },
  async cyclePort() {
    await fetch('/api/controllarr/port/cycle', { method: 'POST' })
  },
}
