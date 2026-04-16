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

export type RecoveryTrigger =
  | 'metadata_timeout'
  | 'no_peers'
  | 'stalled_with_peers'
  | 'awaiting_recheck'
  | 'post_process_move_failed'
  | 'post_process_extraction_failed'
  | 'disk_pressure'

export type RecoveryAction =
  | 'reannounce'
  | 'pause'
  | 'remove_keep_files'
  | 'remove_delete_files'
  | 'retry_post_process'

export type RecoveryRule = {
  enabled: boolean
  trigger: RecoveryTrigger
  action: RecoveryAction
  delayMinutes: number
}

export type BandwidthScheduleRule = {
  name: string
  enabled: boolean
  daysOfWeek: number[]
  startHour: number
  startMinute: number
  endHour: number
  endMinute: number
  maxDownloadKBps: number
  maxUploadKBps: number
}

export type ArrEndpoint = {
  name: string
  kind: 'sonarr' | 'radarr'
  baseURL: string
  apiKey?: string
}

export type DiskSpaceStatus = {
  freeBytes: number
  thresholdBytes: number
  monitorPath: string
  shortfallBytes: number
  isPaused: boolean
  pausedCount: number
  pausedHashes: string[]
}

export type ArrNotification = {
  infoHash: string
  name: string
  endpoint: string
  success: boolean
  message: string
  timestamp: number
}

export type VPNStatus = {
  isConnected: boolean
  interfaceName: string
  interfaceIP: string
  killSwitchEngaged: boolean
  pausedCount: number
  boundToVPN: boolean
}

export type NetworkLANInterface = {
  name: string
  ip: string
}

export type NetworkDiagnostics = {
  bindHost: string
  bindPort: number
  localOpenURL: string
  remoteAccessConfigured: boolean
  suggestedRemoteURLs: string[]
  recommendedRemoteURL?: string
  vpnConnected: boolean
  vpnInterfaceName: string
  vpnInterfaceIP: string
  vpnBoundToTorrentEngine: boolean
  lanInterfaces: NetworkLANInterface[]
  warning?: string
}

export type BackupImportResult = {
  restoredAt: number
  categoryCount: number
  endpointCount: number
  includedSecrets: boolean
  restartRecommended: boolean
}

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
  recoveryRules: RecoveryRule[]
  bandwidthSchedule: BandwidthScheduleRule[]
  vpnEnabled: boolean
  vpnKillSwitch: boolean
  vpnBindInterface: boolean
  vpnInterfacePrefix: string
  vpnMonitorIntervalSeconds: number
  diskSpaceMinimumGB: number | null
  diskSpaceMonitorPath: string
  arrReSearchAfterHours: number
  arrEndpoints: ArrEndpoint[]
}

export type HealthReason = RecoveryTrigger

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
  canRetry: boolean
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

export type RecoverySource = 'automatic' | 'manual'

export type RecoveryRecord = {
  infoHash: string
  name: string
  reason: RecoveryTrigger
  action: RecoveryAction
  source: RecoverySource
  success: boolean
  message: string
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

// Per-torrent detail
export async function fetchFiles(hash: string): Promise<any[]> {
  const r = await fetch(`/api/controllarr/torrents/${hash}/files`);
  return r.ok ? r.json() : [];
}
export async function setFilePriorities(hash: string, priorities: number[]): Promise<boolean> {
  const r = await fetch(`/api/controllarr/torrents/${hash}/files`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ priorities })
  });
  return r.ok;
}
export async function fetchTrackers(hash: string): Promise<any[]> {
  const r = await fetch(`/api/controllarr/torrents/${hash}/trackers`);
  return r.ok ? r.json() : [];
}
export async function fetchPeers(hash: string): Promise<any[]> {
  const r = await fetch(`/api/controllarr/torrents/${hash}/peers`);
  return r.ok ? r.json() : [];
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

  async addTorrentFile(file: File, category?: string): Promise<void> {
    const body = new FormData()
    body.append('torrents', file)
    if (category) body.append('category', category)
    const res = await fetch('/api/v2/torrents/add', {
      method: 'POST',
      body,
      credentials: 'include',
    })
    if (!res.ok) throw new Error(`Upload failed: ${res.status}`)
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
      recoveryRules: response.recoveryRules ?? [],
      bandwidthSchedule: response.bandwidthSchedule ?? [],
      vpnEnabled: response.vpnEnabled ?? false,
      vpnKillSwitch: response.vpnKillSwitch ?? true,
      vpnBindInterface: response.vpnBindInterface ?? true,
      vpnInterfacePrefix: response.vpnInterfacePrefix ?? 'utun',
      vpnMonitorIntervalSeconds: response.vpnMonitorIntervalSeconds ?? 5,
      diskSpaceMinimumGB: response.diskSpaceMinimumGB ?? null,
      diskSpaceMonitorPath: response.diskSpaceMonitorPath ?? '',
      arrReSearchAfterHours: response.arrReSearchAfterHours ?? 6,
      arrEndpoints: response.arrEndpoints ?? [],
    }
  },

  async saveSettings(settings: Settings) {
    await sendJSON('/api/controllarr/settings', {
      ...settings,
      webUIPassword: settings.webUIPassword?.trim() ? settings.webUIPassword : undefined,
      globalMaxRatio: settings.globalMaxRatio,
      globalMaxSeedingTimeMinutes: settings.globalMaxSeedingTimeMinutes,
      recoveryRules: settings.recoveryRules,
      bandwidthSchedule: settings.bandwidthSchedule,
      vpnEnabled: settings.vpnEnabled,
      vpnKillSwitch: settings.vpnKillSwitch,
      vpnBindInterface: settings.vpnBindInterface,
      vpnInterfacePrefix: settings.vpnInterfacePrefix,
      vpnMonitorIntervalSeconds: settings.vpnMonitorIntervalSeconds,
      diskSpaceMinimumGB: settings.diskSpaceMinimumGB,
      diskSpaceMonitorPath: settings.diskSpaceMonitorPath,
      arrReSearchAfterHours: settings.arrReSearchAfterHours,
      arrEndpoints: settings.arrEndpoints,
    })
  },

  async exportBackup(includeSecrets: boolean): Promise<{ blob: Blob; filename: string }> {
    const res = await request(`/api/controllarr/backup?includeSecrets=${includeSecrets}`)
    const disposition = res.headers.get('Content-Disposition') ?? ''
    const filename =
      disposition.match(/filename=\"([^\"]+)\"/)?.[1]
      ?? `controllarr-backup-${new Date().toISOString()}.json`
    return {
      blob: await res.blob(),
      filename,
    }
  },

  async importBackup(file: File): Promise<BackupImportResult> {
    return json<BackupImportResult>('/api/controllarr/backup/import', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: await file.text(),
    })
  },

  async recovery(): Promise<RecoveryRecord[]> {
    return json<RecoveryRecord[]>('/api/controllarr/recovery')
  },

  async runRecovery(hash: string, action?: RecoveryAction): Promise<RecoveryRecord> {
    const fields: Record<string, string> = { hash }
    if (action) fields.action = action
    return json<RecoveryRecord>('/api/controllarr/recovery/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(fields).toString(),
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

  async retryPostProcessor(hash: string): Promise<PostProcessorRecord> {
    return json<PostProcessorRecord>('/api/controllarr/postprocessor/retry', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ hash }).toString(),
    })
  },

  async seeding(): Promise<SeedingEnforcement[]> {
    return json<SeedingEnforcement[]>('/api/controllarr/seeding')
  },

  async log(limit = 500): Promise<LogEntry[]> {
    return json<LogEntry[]>(`/api/controllarr/log?limit=${limit}`)
  },

  async diskSpace(): Promise<DiskSpaceStatus> {
    return json<DiskSpaceStatus>('/api/controllarr/diskspace')
  },

  async recheckDiskSpace(): Promise<DiskSpaceStatus> {
    return json<DiskSpaceStatus>('/api/controllarr/diskspace/recheck', {
      method: 'POST',
    })
  },

  async networkDiagnostics(): Promise<NetworkDiagnostics> {
    return json<NetworkDiagnostics>('/api/controllarr/network')
  },

  async arrNotifications(): Promise<ArrNotification[]> {
    return json<ArrNotification[]>('/api/controllarr/arr')
  },

  async vpnStatus(): Promise<VPNStatus> {
    return json<VPNStatus>('/api/controllarr/vpn')
  },
}
