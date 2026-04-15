// Tiny client for Controllarr's qBittorrent-compatible API plus the
// Controllarr-native management endpoints used by the richer browser UI.
// All requests are relative so this works both from the bundled app and
// from a local Vite dev server with the configured proxy.

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

export type Category = {
  name: string
  savePath: string
  completePath?: string
  extractArchives: boolean
  blockedExtensions: string[]
  maxRatio?: number | null
  maxSeedingTimeMinutes?: number | null
}

export type SeedLimitAction = 'pause' | 'remove_keep_files' | 'remove_delete_files'

export type Settings = {
  listenPortRangeStart: number
  listenPortRangeEnd: number
  stallThresholdMinutes: number
  defaultSavePath: string
  webUIHost: string
  webUIPort: number
  webUIUsername: string
  webUIPassword?: string
  globalMaxRatio: number | null
  globalMaxSeedingTimeMinutes: number | null
  seedLimitAction: SeedLimitAction
  minimumSeedTimeMinutes: number
  healthStallMinutes: number
  healthReannounceOnStall: boolean
}

export type HealthReason =
  | 'metadataTimeout'
  | 'noPeers'
  | 'stalledWithPeers'
  | 'awaitingRecheck'

export type HealthIssue = {
  infoHash: string
  name: string
  reason: HealthReason
  firstSeen: number
  lastProgress: number
  lastUpdated: number
}

export type PostProcessorRecord = {
  infoHash: string
  name: string
  stage: string
  lastUpdated: number
  category?: string
  message?: string
}

export type SeedingEnforcement = {
  infoHash: string
  name: string
  reason: string
  action: SeedLimitAction
  timestamp: number
}

export type LogLevel = 'debug' | 'info' | 'warn' | 'error'

export type LogEntry = {
  id: string
  timestamp: number
  level: LogLevel
  source: string
  message: string
}

async function request(path: string, init?: RequestInit): Promise<Response> {
  const res = await fetch(path, {
    credentials: 'same-origin',
    ...init,
  })

  if (!res.ok) {
    const message = (await res.text()).trim()
    const suffix = message ? `: ${message}` : ''
    throw new Error(`${init?.method ?? 'GET'} ${path} -> ${res.status}${suffix}`)
  }

  return res
}

async function json<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await request(path, init)
  return (await res.json()) as T
}

async function form(path: string, fields: Record<string, string>): Promise<void> {
  await request(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields).toString(),
  })
}

async function sendJSON(path: string, body: unknown, method = 'POST'): Promise<void> {
  await request(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export const api = {
  async login(username: string, password: string) {
    await form('/api/v2/auth/login', { username, password })
  },

  async torrents(): Promise<Torrent[]> {
    return json<Torrent[]>('/api/v2/torrents/info')
  },

  async stats(): Promise<SessionStats> {
    return json<SessionStats>('/api/controllarr/stats')
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
    await request('/api/controllarr/port/cycle', { method: 'POST' })
  },

  async categories(): Promise<Category[]> {
    return json<Category[]>('/api/controllarr/categories')
  },

  async saveCategory(category: Category) {
    await sendJSON('/api/controllarr/categories', {
      ...category,
      completePath: category.completePath ?? '',
      maxRatio: category.maxRatio ?? null,
      maxSeedingTimeMinutes: category.maxSeedingTimeMinutes ?? null,
    })
  },

  async deleteCategory(name: string) {
    await request(`/api/controllarr/categories/${encodeURIComponent(name)}`, {
      method: 'DELETE',
    })
  },

  async settings(): Promise<Settings> {
    const response = await json<Partial<Settings>>('/api/controllarr/settings')
    return {
      listenPortRangeStart: response.listenPortRangeStart ?? 49152,
      listenPortRangeEnd: response.listenPortRangeEnd ?? 65000,
      stallThresholdMinutes: response.stallThresholdMinutes ?? 10,
      defaultSavePath: response.defaultSavePath ?? '',
      webUIHost: response.webUIHost ?? '127.0.0.1',
      webUIPort: response.webUIPort ?? 8791,
      webUIUsername: response.webUIUsername ?? 'admin',
      webUIPassword: response.webUIPassword ?? '',
      globalMaxRatio: response.globalMaxRatio ?? null,
      globalMaxSeedingTimeMinutes: response.globalMaxSeedingTimeMinutes ?? null,
      seedLimitAction: response.seedLimitAction ?? 'pause',
      minimumSeedTimeMinutes: response.minimumSeedTimeMinutes ?? 60,
      healthStallMinutes: response.healthStallMinutes ?? 30,
      healthReannounceOnStall: response.healthReannounceOnStall ?? true,
    }
  },

  async saveSettings(settings: Settings) {
    await sendJSON('/api/controllarr/settings', {
      ...settings,
      webUIPassword: settings.webUIPassword?.trim() ? settings.webUIPassword : undefined,
      globalMaxRatio: settings.globalMaxRatio,
      globalMaxSeedingTimeMinutes: settings.globalMaxSeedingTimeMinutes,
    })
  },

  async health(): Promise<HealthIssue[]> {
    return json<HealthIssue[]>('/api/controllarr/health')
  },

  async clearHealthIssue(hash: string) {
    await form('/api/controllarr/health/clear', { hash })
  },

  async postProcessor(): Promise<PostProcessorRecord[]> {
    return json<PostProcessorRecord[]>('/api/controllarr/postprocessor')
  },

  async seeding(): Promise<SeedingEnforcement[]> {
    return json<SeedingEnforcement[]>('/api/controllarr/seeding')
  },

  async log(limit = 500): Promise<LogEntry[]> {
    return json<LogEntry[]>(`/api/controllarr/log?limit=${limit}`)
  },
}
