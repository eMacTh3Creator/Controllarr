import { startTransition, useCallback, useDeferredValue, useEffect, useState, type FormEvent } from 'react'
import {
  api,
  fetchFiles,
  fetchTrackers,
  fetchPeers,
  setFilePriorities,
  type ArrEndpoint,
  type ArrNotification,
  type BandwidthScheduleRule,
  type Category,
  type DiskSpaceStatus,
  type HealthIssue,
  type LogEntry,
  type PostProcessorRecord,
  type SeedLimitAction,
  type SeedingEnforcement,
  type SessionStats,
  type Settings,
  type Torrent,
} from './api'
import {
  fmtBytes,
  fmtDateTime,
  fmtETA,
  fmtOptionalNumber,
  fmtPercent,
  fmtRate,
  fmtRelativeTime,
} from './format'

type TabId =
  | 'torrents'
  | 'categories'
  | 'settings'
  | 'health'
  | 'postprocessor'
  | 'seeding'
  | 'log'

type TabMeta = {
  id: TabId
  label: string
  description: string
}

type LiveSnapshot = {
  torrents: Torrent[]
  stats: SessionStats | null
  categories: Category[]
  health: HealthIssue[]
  postProcessor: PostProcessorRecord[]
  seeding: SeedingEnforcement[]
  log: LogEntry[]
}

type CategoryModalState =
  | { mode: 'new' }
  | { mode: 'edit'; category: Category }

const TABS: TabMeta[] = [
  {
    id: 'torrents',
    label: 'Torrents',
    description: 'Add magnets, watch live throughput, and manage the active queue.',
  },
  {
    id: 'categories',
    label: 'Categories',
    description: 'Map incoming downloads, completion paths, extraction rules, and file filters.',
  },
  {
    id: 'settings',
    label: 'Settings',
    description: 'Tune WebUI access, listen ports, seeding policy, and health monitoring.',
  },
  {
    id: 'health',
    label: 'Health',
    description: 'Review stalled or unhealthy torrents and clear issues once resolved.',
  },
  {
    id: 'postprocessor',
    label: 'Post-Processor',
    description: 'See completed torrents moving, extracting, and landing in their final destination.',
  },
  {
    id: 'seeding',
    label: 'Seeding',
    description: 'Audit seeding-limit enforcement and what action Controllarr applied.',
  },
  {
    id: 'log',
    label: 'Log',
    description: 'Tail the in-app ring buffer with live filtering and level coloring.',
  },
]

const EMPTY_SNAPSHOT: LiveSnapshot = {
  torrents: [],
  stats: null,
  categories: [],
  health: [],
  postProcessor: [],
  seeding: [],
  log: [],
}

export function App() {
  const [authed, setAuthed] = useState(false)
  const [username, setUsername] = useState('admin')
  const [password, setPassword] = useState('adminadmin')
  const [activeTab, setActiveTab] = useState<TabId>('torrents')
  const [snapshot, setSnapshot] = useState<LiveSnapshot>(EMPTY_SNAPSHOT)
  const [serverSettings, setServerSettings] = useState<Settings | null>(null)
  const [settingsDraft, setSettingsDraft] = useState<Settings | null>(null)
  const [settingsDirty, setSettingsDirty] = useState(false)
  const [settingsMessage, setSettingsMessage] = useState<string | null>(null)
  const [magnet, setMagnet] = useState('')
  const [magnetCategory, setMagnetCategory] = useState('')
  const [logFilter, setLogFilter] = useState('')
  const [categoryModal, setCategoryModal] = useState<CategoryModalState | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [hasLoaded, setHasLoaded] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [lastUpdated, setLastUpdated] = useState<number | null>(null)

  const deferredLogFilter = useDeferredValue(logFilter)
  const currentTab = TABS.find((tab) => tab.id === activeTab) ?? TABS[0]

  const fetchDashboard = useCallback(
    async ({
      includeSettings,
      silent,
      forceSettingsSync = false,
    }: {
      includeSettings: boolean
      silent: boolean
      forceSettingsSync?: boolean
    }) => {
      if (!silent) setIsLoading(true)

      try {
        const livePromise = Promise.all([
          api.torrents(),
          api.stats(),
          api.categories(),
          api.health(),
          api.postProcessor(),
          api.seeding(),
          api.log(500),
        ])

        const settingsPromise = includeSettings
          ? api.settings()
          : Promise.resolve<Settings | null>(null)

        const [
          torrents,
          stats,
          categories,
          health,
          postProcessor,
          seeding,
          log,
          nextSettings,
        ] = [...(await livePromise), await settingsPromise]

        startTransition(() => {
          setSnapshot({
            torrents: sortedCopy(torrents, (a, b) => b.added_on - a.added_on),
            stats,
            categories: sortedCopy(categories, (a, b) => a.name.localeCompare(b.name)),
            health: sortedCopy(health, (a, b) => b.lastUpdated - a.lastUpdated),
            postProcessor: sortedCopy(postProcessor, (a, b) => b.lastUpdated - a.lastUpdated),
            seeding: sortedCopy(seeding, (a, b) => b.timestamp - a.timestamp),
            log: sortedCopy(log, (a, b) => b.timestamp - a.timestamp),
          })

          if (nextSettings) {
            const normalized = normalizeSettings(nextSettings)
            setServerSettings(normalized)
            setSettingsDraft((current) => {
              if (forceSettingsSync || !settingsDirty || current === null) return normalized
              return current
            })
          }
        })

        setLastUpdated(Date.now())
        setHasLoaded(true)
        setError(null)
      } catch (fetchError: unknown) {
        setError(fetchError instanceof Error ? fetchError.message : String(fetchError))
      } finally {
        if (!silent) setIsLoading(false)
      }
    },
    [settingsDirty],
  )

  const refreshAll = useCallback(
    async (silent = false, forceSettingsSync = false) => {
      await fetchDashboard({ includeSettings: true, silent, forceSettingsSync })
    },
    [fetchDashboard],
  )

  const refreshLive = useCallback(
    async (silent = true) => {
      await fetchDashboard({ includeSettings: false, silent })
    },
    [fetchDashboard],
  )

  useEffect(() => {
    if (!authed) return

    void refreshAll(false, true)
    const intervalId = window.setInterval(() => {
      void refreshLive(true)
    }, 2_000)

    return () => window.clearInterval(intervalId)
  }, [authed, refreshAll, refreshLive])

  useEffect(() => {
    if (!settingsMessage) return
    const timeout = window.setTimeout(() => setSettingsMessage(null), 2_500)
    return () => window.clearTimeout(timeout)
  }, [settingsMessage])

  const runAction = useCallback(
    async (action: () => Promise<void>, options?: { refreshAll?: boolean; silent?: boolean }) => {
      try {
        await action()
        setError(null)
        if (options?.refreshAll) {
          await refreshAll(options.silent ?? true, options.refreshAll)
        } else {
          await refreshLive(options?.silent ?? true)
        }
      } catch (actionError: unknown) {
        setError(actionError instanceof Error ? actionError.message : String(actionError))
      }
    },
    [refreshAll, refreshLive],
  )

  async function handleLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsLoading(true)

    try {
      await api.login(username, password)
      setAuthed(true)
      setError(null)
    } catch (loginError: unknown) {
      setError(loginError instanceof Error ? loginError.message : String(loginError))
      setIsLoading(false)
    }
  }

  async function handleAddMagnet(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const uri = magnet.trim()
    if (!uri) return

    await runAction(async () => {
      await api.addMagnet(uri, magnetCategory.trim() || undefined)
      setMagnet('')
      setMagnetCategory('')
    })
  }

  function updateSettings(next: Settings) {
    setSettingsDraft(normalizeSettings(next))
    setSettingsDirty(true)
    setSettingsMessage(null)
  }

  async function saveSettings(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!settingsDraft) return

    try {
      setIsLoading(true)
      await api.saveSettings(settingsDraft)
      setSettingsDirty(false)
      setSettingsMessage('Settings saved')
      await refreshAll(true, true)
    } catch (saveError: unknown) {
      setError(saveError instanceof Error ? saveError.message : String(saveError))
    } finally {
      setIsLoading(false)
    }
  }

  function revertSettings() {
    if (!serverSettings) return
    setSettingsDraft(serverSettings)
    setSettingsDirty(false)
    setSettingsMessage(null)
  }

  async function saveCategory(category: Category) {
    try {
      await api.saveCategory(category)
      setCategoryModal(null)
      setError(null)
      await refreshLive(false)
    } catch (saveError: unknown) {
      const message = saveError instanceof Error ? saveError.message : String(saveError)
      setError(message)
      throw saveError
    }
  }

  async function deleteCategory(name: string) {
    const confirmed = window.confirm(`Delete category "${name}"?`)
    if (!confirmed) return

    await runAction(async () => {
      await api.deleteCategory(name)
    })
  }

  async function clearHealth(hash: string) {
    await runAction(async () => {
      await api.clearHealthIssue(hash)
    })
  }

  if (!authed) {
    return (
      <div className="sign-in-shell">
        <form className="sign-in-card" onSubmit={handleLogin}>
          <div className="brand-kicker">Controllarr</div>
          <h1>Browser control room</h1>
          <p>
            Sign in with the WebUI account so you can manage torrents, categories, seeding
            policy, health, and logs from another machine.
          </p>

          <label className="field">
            <span>Username</span>
            <input value={username} onChange={(event) => setUsername(event.target.value)} />
          </label>

          <label className="field">
            <span>Password</span>
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>

          <div className="button-row">
            <button className="primary" type="submit" disabled={isLoading}>
              {isLoading ? 'Signing in…' : 'Sign in'}
            </button>
          </div>

          {error && <Banner tone="error" message={error} />}
        </form>
      </div>
    )
  }

  return (
    <div className="app-shell">
      <div className="shell">
        <aside className="sidebar panel">
          <div className="sidebar-header">
            <div className="brand-kicker">Controllarr</div>
            <div className="sidebar-title">Operations</div>
            <p>qBittorrent-compatible control surface with Controllarr-native automation.</p>
          </div>

          <nav className="tab-nav" aria-label="Sections">
            {TABS.map((tab) => (
              <button
                key={tab.id}
                type="button"
                className={tab.id === activeTab ? 'tab-button active' : 'tab-button'}
                onClick={() => setActiveTab(tab.id)}
              >
                <span>{tab.label}</span>
                <span className="tab-count">{countForTab(tab.id, snapshot)}</span>
              </button>
            ))}
          </nav>

          <div className="sidebar-footer">
            <div className="mini-stat">
              <span>Listen port</span>
              <strong>{snapshot.stats?.listenPort ?? '—'}</strong>
            </div>
            <div className="mini-stat">
              <span>Incoming</span>
              <strong>{snapshot.stats?.hasIncoming ? 'Healthy' : 'Waiting'}</strong>
            </div>
            <button type="button" onClick={() => void refreshAll(false, false)} disabled={isLoading}>
              {isLoading ? 'Refreshing…' : 'Refresh now'}
            </button>
          </div>
        </aside>

        <main className="main-column">
          <section className="hero panel">
            <div>
              <div className="brand-kicker">{currentTab.label}</div>
              <h1>{currentTab.description}</h1>
              <p>
                Live data updates every two seconds. The older qBit endpoints stay in place for
                Sonarr, Radarr, and Overseerr while this UI exposes the Controllarr-native knobs.
              </p>
            </div>

            <div className="hero-actions">
              <div className={statusPillClass(snapshot.stats)}>
                {snapshot.stats?.hasIncoming ? 'Incoming connections healthy' : 'Watching listen state'}
              </div>
              <button type="button" className="primary" onClick={() => void refreshAll(false, false)}>
                Refresh all
              </button>
            </div>
          </section>

          <StatsGrid stats={snapshot.stats} lastUpdated={lastUpdated} />

          {error && <Banner tone="error" message={error} />}
          {settingsMessage && <Banner tone="success" message={settingsMessage} />}

          <section className="panel panel-body">
            {!hasLoaded && isLoading ? (
              <div className="empty-state">
                <h2>Loading Controllarr…</h2>
                <p>Pulling session stats, categories, health state, and the latest log entries.</p>
              </div>
            ) : (
              <>
                {activeTab === 'torrents' && (
                  <TorrentsTab
                    torrents={snapshot.torrents}
                    categories={snapshot.categories}
                    magnet={magnet}
                    magnetCategory={magnetCategory}
                    onMagnetChange={setMagnet}
                    onCategoryChange={setMagnetCategory}
                    onSubmit={handleAddMagnet}
                    onPause={(hash) => void runAction(() => api.pause(hash))}
                    onResume={(hash) => void runAction(() => api.resume(hash))}
                    onRemove={(hash, deleteFiles) =>
                      void runAction(() => api.remove(hash, deleteFiles), { silent: false })
                    }
                  />
                )}

                {activeTab === 'categories' && (
                  <CategoriesTab
                    categories={snapshot.categories}
                    onNew={() => setCategoryModal({ mode: 'new' })}
                    onEdit={(category) => setCategoryModal({ mode: 'edit', category })}
                    onDelete={(name) => void deleteCategory(name)}
                  />
                )}

                {activeTab === 'settings' && settingsDraft && (
                  <SettingsTab
                    settings={settingsDraft}
                    settingsDirty={settingsDirty}
                    onChange={updateSettings}
                    onSave={saveSettings}
                    onRevert={revertSettings}
                    onCyclePort={() => void runAction(() => api.cyclePort(), { silent: false })}
                  />
                )}

                {activeTab === 'health' && (
                  <HealthTab issues={snapshot.health} onClear={(hash) => void clearHealth(hash)} />
                )}

                {activeTab === 'postprocessor' && (
                  <PostProcessorTab records={snapshot.postProcessor} />
                )}

                {activeTab === 'seeding' && <SeedingTab records={snapshot.seeding} />}

                {activeTab === 'log' && (
                  <LogTab
                    entries={snapshot.log}
                    filter={logFilter}
                    deferredFilter={deferredLogFilter}
                    onFilterChange={setLogFilter}
                  />
                )}
              </>
            )}
          </section>
        </main>
      </div>

      {categoryModal && (
        <CategoryModal
          defaultSavePath={settingsDraft?.defaultSavePath ?? snapshot.categories[0]?.savePath ?? ''}
          initialCategory={categoryModal.mode === 'edit' ? categoryModal.category : undefined}
          onClose={() => setCategoryModal(null)}
          onSave={saveCategory}
        />
      )}
    </div>
  )
}

function StatsGrid({
  stats,
  lastUpdated,
}: {
  stats: SessionStats | null
  lastUpdated: number | null
}) {
  const cards = [
    {
      label: 'Download',
      value: stats ? fmtRate(stats.downloadRate) : '—',
      tone: 'blue',
    },
    {
      label: 'Upload',
      value: stats ? fmtRate(stats.uploadRate) : '—',
      tone: 'green',
    },
    {
      label: 'Listen port',
      value: stats ? String(stats.listenPort) : '—',
      tone: stats?.hasIncoming ? 'green' : stats ? 'amber' : 'neutral',
    },
    {
      label: 'Peers',
      value: stats ? String(stats.numPeers) : '—',
      tone: 'neutral',
    },
    {
      label: 'Downloaded',
      value: stats ? fmtBytes(stats.totalDownloaded) : '—',
      tone: 'neutral',
    },
    {
      label: 'Live sync',
      value: lastUpdated ? fmtRelativeTime(lastUpdated / 1000) : 'Waiting',
      tone: 'neutral',
    },
  ]

  return (
    <section className="stats-grid">
      {cards.map((card) => (
        <article key={card.label} className={`metric-card ${card.tone}`}>
          <div className="metric-label">{card.label}</div>
          <div className="metric-value">{card.value}</div>
        </article>
      ))}
    </section>
  )
}

type DetailSubTab = 'files' | 'trackers' | 'peers'

function TorrentsTab({
  torrents,
  categories,
  magnet,
  magnetCategory,
  onMagnetChange,
  onCategoryChange,
  onSubmit,
  onPause,
  onResume,
  onRemove,
}: {
  torrents: Torrent[]
  categories: Category[]
  magnet: string
  magnetCategory: string
  onMagnetChange: (value: string) => void
  onCategoryChange: (value: string) => void
  onSubmit: (event: FormEvent<HTMLFormElement>) => void
  onPause: (hash: string) => void
  onResume: (hash: string) => void
  onRemove: (hash: string, deleteFiles: boolean) => void
}) {
  const [selectedHash, setSelectedHash] = useState<string | null>(null)
  const [detailTab, setDetailTab] = useState<DetailSubTab>('files')
  const [files, setFiles] = useState<any[]>([])
  const [trackers, setTrackers] = useState<any[]>([])
  const [peers, setPeers] = useState<any[]>([])

  const selectedTorrent = torrents.find((t) => t.hash === selectedHash) ?? null

  useEffect(() => {
    if (!selectedHash) return
    let cancelled = false

    async function load() {
      try {
        const [f, t, p] = await Promise.all([
          fetchFiles(selectedHash!),
          fetchTrackers(selectedHash!),
          fetchPeers(selectedHash!),
        ])
        if (!cancelled) {
          setFiles(f)
          setTrackers(t)
          setPeers(p)
        }
      } catch {
        // silently ignore — detail panel is best-effort
      }
    }

    void load()
    const interval = window.setInterval(load, 3_000)
    return () => {
      cancelled = true
      window.clearInterval(interval)
    }
  }, [selectedHash])

  function handleRowClick(hash: string) {
    if (selectedHash === hash) {
      setSelectedHash(null)
    } else {
      setSelectedHash(hash)
      setDetailTab('files')
      setFiles([])
      setTrackers([])
      setPeers([])
    }
  }

  async function handleToggleFilePriority(index: number) {
    if (!selectedHash) return
    const updated = files.map((f, i) => {
      if (i === index) return { ...f, priority: f.priority === 0 ? 4 : 0 }
      return f
    })
    setFiles(updated)
    const priorities = updated.map((f: any) => f.priority as number)
    const ok = await setFilePriorities(selectedHash, priorities)
    if (!ok) {
      // revert on failure
      const fresh = await fetchFiles(selectedHash)
      setFiles(fresh)
    }
  }

  return (
    <div className="section-stack">
      <header className="section-header">
        <div>
          <h2>Torrents</h2>
          <p>Live queue, qBit-style actions, and a quick magnet intake form.</p>
        </div>
        <div className="section-meta">{torrents.length} total</div>
      </header>

      <form className="form-panel accent-panel" onSubmit={onSubmit}>
        <div className="form-panel-header">
          <h3>Add magnet</h3>
          <p>Assign a category now so post-processing and file filters apply immediately.</p>
        </div>

        <div className="form-grid compact">
          <label className="field wide">
            <span>Magnet URI</span>
            <textarea
              rows={3}
              placeholder="magnet:?xt=urn:btih:…"
              value={magnet}
              onChange={(event) => onMagnetChange(event.target.value)}
            />
          </label>

          <label className="field">
            <span>Category</span>
            <select value={magnetCategory} onChange={(event) => onCategoryChange(event.target.value)}>
              <option value="">No category</option>
              {categories.map((category) => (
                <option key={category.name} value={category.name}>
                  {category.name}
                </option>
              ))}
            </select>
          </label>
        </div>

        <div className="button-row">
          <button className="primary" type="submit" disabled={!magnet.trim()}>
            Add magnet
          </button>
        </div>
      </form>

      {torrents.length === 0 ? (
        <EmptyState
          title="No torrents yet"
          body="Add a magnet above or point your *arr apps at Controllarr's qBittorrent-compatible API."
        />
      ) : (
        <>
          <div className="table-shell">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Category</th>
                  <th>Progress</th>
                  <th>Transfer</th>
                  <th>Peers</th>
                  <th>Ratio</th>
                  <th>ETA</th>
                  <th>State</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {torrents.map((torrent) => {
                  const paused = torrent.state.startsWith('paused')
                  const seeding = torrent.state === 'uploading' || torrent.state === 'stalledUP'
                  const isSelected = torrent.hash === selectedHash

                  return (
                    <tr
                      key={torrent.hash}
                      style={isSelected ? { background: 'rgba(97, 199, 255, 0.08)', cursor: 'pointer' } : { cursor: 'pointer' }}
                      onClick={() => handleRowClick(torrent.hash)}
                    >
                      <td>
                        <div className="primary-cell">{torrent.name || '(fetching metadata…)'} </div>
                        <div className="subtle-cell">{torrent.save_path || 'Save path pending'}</div>
                      </td>
                      <td>{torrent.category || 'Unassigned'}</td>
                      <td className="progress-cell">
                        <div className="progress-track">
                          <div
                            className={seeding ? 'progress-fill success' : paused ? 'progress-fill muted' : 'progress-fill'}
                            style={{ width: `${Math.min(100, torrent.progress * 100)}%` }}
                          />
                        </div>
                        <div className="subtle-cell">
                          {fmtPercent(torrent.progress)} · {fmtBytes(torrent.completed)} / {fmtBytes(torrent.size)}
                        </div>
                      </td>
                      <td className="mono-cell">
                        ↓ {fmtRate(torrent.dlspeed)}
                        <br />
                        ↑ {fmtRate(torrent.upspeed)}
                      </td>
                      <td className="mono-cell">
                        {torrent.num_seeds}S / {torrent.num_leechs}L
                      </td>
                      <td className="mono-cell">{torrent.ratio.toFixed(2)}</td>
                      <td>{fmtETA(torrent.eta)}</td>
                      <td>
                        <span className={`pill ${stateTone(torrent.state)}`}>{torrent.state}</span>
                      </td>
                      <td>
                        <div className="action-cluster" onClick={(e) => e.stopPropagation()}>
                          {paused ? (
                            <button type="button" onClick={() => onResume(torrent.hash)}>
                              Resume
                            </button>
                          ) : (
                            <button type="button" onClick={() => onPause(torrent.hash)}>
                              Pause
                            </button>
                          )}
                          <button type="button" onClick={() => onRemove(torrent.hash, false)}>
                            Remove
                          </button>
                          <button
                            type="button"
                            className="danger"
                            onClick={() => onRemove(torrent.hash, true)}
                          >
                            Delete files
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          {selectedTorrent && (
            <div className="form-panel" style={{ marginTop: '8px' }}>
              <div className="form-panel-header">
                <h3>{selectedTorrent.name || '(fetching metadata…)'}</h3>
                <p>Inspect files, trackers, and peers for this torrent.</p>
              </div>

              <div className="button-row" style={{ marginBottom: '4px' }}>
                {(['files', 'trackers', 'peers'] as DetailSubTab[]).map((tab) => (
                  <button
                    key={tab}
                    type="button"
                    className={detailTab === tab ? 'primary' : undefined}
                    onClick={() => setDetailTab(tab)}
                  >
                    {tab.charAt(0).toUpperCase() + tab.slice(1)}
                  </button>
                ))}
              </div>

              {detailTab === 'files' && (
                files.length === 0 ? (
                  <EmptyState title="No file data" body="Waiting for metadata or the torrent has no files listed yet." />
                ) : (
                  <div className="table-shell">
                    <table className="data-table" style={{ minWidth: '600px' }}>
                      <thead>
                        <tr>
                          <th>Name</th>
                          <th>Size</th>
                          <th>Priority</th>
                          <th>Toggle</th>
                        </tr>
                      </thead>
                      <tbody>
                        {files.map((file: any, idx: number) => (
                          <tr key={idx}>
                            <td className="primary-cell">{file.name ?? `File ${idx}`}</td>
                            <td className="mono-cell">{fmtBytes(file.size ?? 0)}</td>
                            <td>
                              <span className={`pill ${file.priority === 0 ? 'neutral' : 'blue'}`}>
                                {file.priority === 0 ? 'Skipped' : `Priority ${file.priority}`}
                              </span>
                            </td>
                            <td>
                              <button type="button" onClick={() => void handleToggleFilePriority(idx)}>
                                {file.priority === 0 ? 'Enable' : 'Skip'}
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )
              )}

              {detailTab === 'trackers' && (
                trackers.length === 0 ? (
                  <EmptyState title="No tracker data" body="Waiting for tracker information." />
                ) : (
                  <div className="table-shell">
                    <table className="data-table" style={{ minWidth: '800px' }}>
                      <thead>
                        <tr>
                          <th>URL</th>
                          <th>Status</th>
                          <th>Tier</th>
                          <th>Seeds</th>
                          <th>Peers</th>
                          <th>Leechers</th>
                          <th>Message</th>
                        </tr>
                      </thead>
                      <tbody>
                        {trackers.map((tracker: any, idx: number) => {
                          const statusText = trackerStatusText(tracker.status)
                          const statusTone = trackerStatusTone(tracker.status)
                          return (
                            <tr key={idx}>
                              <td className="primary-cell" style={{ wordBreak: 'break-all' }}>{tracker.url ?? '—'}</td>
                              <td>
                                <span className={`pill ${statusTone}`}>{statusText}</span>
                              </td>
                              <td className="mono-cell">{tracker.tier ?? '—'}</td>
                              <td className="mono-cell">{tracker.seeds ?? tracker.num_seeds ?? '—'}</td>
                              <td className="mono-cell">{tracker.peers ?? tracker.num_peers ?? '—'}</td>
                              <td className="mono-cell">{tracker.leechers ?? tracker.num_leechers ?? '—'}</td>
                              <td>{tracker.message || tracker.msg || '—'}</td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                )
              )}

              {detailTab === 'peers' && (
                peers.length === 0 ? (
                  <EmptyState title="No peer data" body="No peers connected to this torrent right now." />
                ) : (
                  <div className="table-shell">
                    <table className="data-table" style={{ minWidth: '700px' }}>
                      <thead>
                        <tr>
                          <th>IP</th>
                          <th>Client</th>
                          <th>Progress</th>
                          <th>Download rate</th>
                          <th>Upload rate</th>
                          <th>Flags</th>
                        </tr>
                      </thead>
                      <tbody>
                        {peers.map((peer: any, idx: number) => (
                          <tr key={idx}>
                            <td className="mono-cell">{peer.ip ?? '—'}</td>
                            <td>{peer.client ?? '—'}</td>
                            <td className="mono-cell">{fmtPercent(peer.progress ?? 0)}</td>
                            <td className="mono-cell">{fmtRate(peer.dl_speed ?? peer.dlspeed ?? 0)}</td>
                            <td className="mono-cell">{fmtRate(peer.up_speed ?? peer.upspeed ?? 0)}</td>
                            <td className="mono-cell">{peer.flags ?? '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )
              )}
            </div>
          )}
        </>
      )}
    </div>
  )
}

function CategoriesTab({
  categories,
  onNew,
  onEdit,
  onDelete,
}: {
  categories: Category[]
  onNew: () => void
  onEdit: (category: Category) => void
  onDelete: (name: string) => void
}) {
  return (
    <div className="section-stack">
      <header className="section-header">
        <div>
          <h2>Categories</h2>
          <p>Route downloads to scratch storage, final libraries, and per-category seeding limits.</p>
        </div>
        <div className="button-row">
          <button className="primary" type="button" onClick={onNew}>
            New category
          </button>
        </div>
      </header>

      {categories.length === 0 ? (
        <EmptyState
          title="No categories configured"
          body="Create one to define save paths, archive extraction, blocked extensions, and seeding overrides."
        />
      ) : (
        <div className="table-shell">
          <table className="data-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Save path</th>
                <th>Complete path</th>
                <th>Extract</th>
                <th>Blocked extensions</th>
                <th>Max ratio</th>
                <th>Max seed time</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {categories.map((category) => (
                <tr key={category.name}>
                  <td className="primary-cell">{category.name}</td>
                  <td>{category.savePath}</td>
                  <td>{category.completePath || '—'}</td>
                  <td>{category.extractArchives ? 'Yes' : 'No'}</td>
                  <td>{category.blockedExtensions.join(', ') || '—'}</td>
                  <td>{fmtOptionalNumber(category.maxRatio)}</td>
                  <td>{fmtOptionalNumber(category.maxSeedingTimeMinutes, ' min')}</td>
                  <td>
                    <div className="action-cluster">
                      <button type="button" onClick={() => onEdit(category)}>
                        Edit
                      </button>
                      <button type="button" className="danger" onClick={() => onDelete(category.name)}>
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function SettingsTab({
  settings,
  settingsDirty,
  onChange,
  onSave,
  onRevert,
  onCyclePort,
}: {
  settings: Settings
  settingsDirty: boolean
  onChange: (settings: Settings) => void
  onSave: (event: FormEvent<HTMLFormElement>) => void
  onRevert: () => void
  onCyclePort: () => void
}) {
  function patch(patchValues: Partial<Settings>) {
    onChange({ ...settings, ...patchValues })
  }

  return (
    <form className="section-stack" onSubmit={onSave}>
      <header className="section-header">
        <div>
          <h2>Settings</h2>
          <p>These fields mirror the native Settings view and post back to the full server schema.</p>
        </div>
        <div className="section-meta">{settingsDirty ? 'Unsaved changes' : 'In sync'}</div>
      </header>

      <div className="settings-grid">
        <section className="form-panel">
          <div className="form-panel-header">
            <h3>WebUI</h3>
            <p>Connection details for the browser-facing admin interface.</p>
          </div>
          <div className="form-grid">
            <label className="field">
              <span>Host</span>
              <input
                value={settings.webUIHost}
                onChange={(event) => patch({ webUIHost: event.target.value })}
              />
            </label>
            <label className="field">
              <span>Port</span>
              <input
                type="number"
                value={settings.webUIPort}
                onChange={(event) =>
                  patch({ webUIPort: readNumber(event.currentTarget.valueAsNumber, settings.webUIPort) })
                }
              />
            </label>
            <label className="field">
              <span>Username</span>
              <input
                value={settings.webUIUsername}
                onChange={(event) => patch({ webUIUsername: event.target.value })}
              />
            </label>
            <label className="field">
              <span>Password</span>
              <input
                type="password"
                placeholder="Leave blank to keep existing password"
                value={settings.webUIPassword ?? ''}
                onChange={(event) => patch({ webUIPassword: event.target.value })}
              />
            </label>
          </div>
        </section>

        <section className="form-panel">
          <div className="form-panel-header">
            <h3>Listen port range</h3>
            <p>PortWatcher will rotate within this range if the session goes stale.</p>
          </div>
          <div className="form-grid">
            <label className="field">
              <span>Range start</span>
              <input
                type="number"
                value={settings.listenPortRangeStart}
                onChange={(event) =>
                  patch({
                    listenPortRangeStart: readNumber(
                      event.currentTarget.valueAsNumber,
                      settings.listenPortRangeStart,
                    ),
                  })
                }
              />
            </label>
            <label className="field">
              <span>Range end</span>
              <input
                type="number"
                value={settings.listenPortRangeEnd}
                onChange={(event) =>
                  patch({
                    listenPortRangeEnd: readNumber(
                      event.currentTarget.valueAsNumber,
                      settings.listenPortRangeEnd,
                    ),
                  })
                }
              />
            </label>
            <label className="field">
              <span>Port stall threshold (min)</span>
              <input
                type="number"
                value={settings.stallThresholdMinutes}
                onChange={(event) =>
                  patch({
                    stallThresholdMinutes: readNumber(
                      event.currentTarget.valueAsNumber,
                      settings.stallThresholdMinutes,
                    ),
                  })
                }
              />
            </label>
          </div>
          <div className="button-row">
            <button type="button" onClick={onCyclePort}>
              Cycle port now
            </button>
          </div>
        </section>

        <section className="form-panel">
          <div className="form-panel-header">
            <h3>Storage defaults</h3>
            <p>Used when a torrent or category does not override its own save path.</p>
          </div>
          <label className="field">
            <span>Default save path</span>
            <input
              value={settings.defaultSavePath}
              onChange={(event) => patch({ defaultSavePath: event.target.value })}
            />
          </label>
        </section>

        <section className="form-panel">
          <div className="form-panel-header">
            <h3>Seeding policy</h3>
            <p>Global limits apply unless a category overrides them.</p>
          </div>
          <div className="form-grid">
            <label className="field">
              <span>When limit reached</span>
              <select
                value={settings.seedLimitAction}
                onChange={(event) =>
                  patch({ seedLimitAction: event.target.value as SeedLimitAction })
                }
              >
                <option value="pause">Pause</option>
                <option value="remove_keep_files">Remove (keep files)</option>
                <option value="remove_delete_files">Remove (delete files)</option>
              </select>
            </label>

            <OptionalNumberField
              label="Global max ratio"
              value={settings.globalMaxRatio}
              step={0.25}
              min={0}
              onToggle={(enabled) => patch({ globalMaxRatio: enabled ? settings.globalMaxRatio ?? 2 : null })}
              onValueChange={(value) => patch({ globalMaxRatio: value })}
            />

            <OptionalNumberField
              label="Global max seed time (min)"
              value={settings.globalMaxSeedingTimeMinutes}
              step={60}
              min={0}
              onToggle={(enabled) =>
                patch({
                  globalMaxSeedingTimeMinutes: enabled
                    ? settings.globalMaxSeedingTimeMinutes ?? 4_320
                    : null,
                })
              }
              onValueChange={(value) => patch({ globalMaxSeedingTimeMinutes: value })}
            />

            <label className="field">
              <span>Minimum seed time (min)</span>
              <input
                type="number"
                value={settings.minimumSeedTimeMinutes}
                onChange={(event) =>
                  patch({
                    minimumSeedTimeMinutes: readNumber(
                      event.currentTarget.valueAsNumber,
                      settings.minimumSeedTimeMinutes,
                    ),
                  })
                }
              />
            </label>
          </div>
        </section>

        <section className="form-panel">
          <div className="form-panel-header">
            <h3>Health monitor</h3>
            <p>Flag stalled torrents and optionally reannounce when a stall begins.</p>
          </div>
          <div className="form-grid">
            <label className="field">
              <span>Stall threshold (min)</span>
              <input
                type="number"
                value={settings.healthStallMinutes}
                onChange={(event) =>
                  patch({
                    healthStallMinutes: readNumber(
                      event.currentTarget.valueAsNumber,
                      settings.healthStallMinutes,
                    ),
                  })
                }
              />
            </label>
            <label className="toggle-field">
              <span>Reannounce automatically on stall</span>
              <input
                type="checkbox"
                checked={settings.healthReannounceOnStall}
                onChange={(event) =>
                  patch({ healthReannounceOnStall: event.currentTarget.checked })
                }
              />
            </label>
          </div>
        </section>
      </div>

      <DiskSpaceMonitorSection
        diskSpaceMinimumGB={settings.diskSpaceMinimumGB}
        diskSpaceMonitorPath={settings.diskSpaceMonitorPath}
        onMinimumGBChange={(value) => patch({ diskSpaceMinimumGB: value })}
        onMonitorPathChange={(value) => patch({ diskSpaceMonitorPath: value })}
      />

      <ArrIntegrationSection
        arrReSearchAfterHours={settings.arrReSearchAfterHours}
        arrEndpoints={settings.arrEndpoints}
        onReSearchHoursChange={(value) => patch({ arrReSearchAfterHours: value })}
        onEndpointsChange={(endpoints) => patch({ arrEndpoints: endpoints })}
      />

      <BandwidthScheduleSection
        rules={settings.bandwidthSchedule}
        onChange={(rules) => patch({ bandwidthSchedule: rules })}
      />

      <div className="button-row">
        <button className="primary" type="submit">
          Save settings
        </button>
        <button type="button" onClick={onRevert} disabled={!settingsDirty}>
          Revert
        </button>
      </div>
    </form>
  )
}

const DAY_LABELS: Record<number, string> = {
  1: 'Sun', 2: 'Mon', 3: 'Tue', 4: 'Wed', 5: 'Thu', 6: 'Fri', 7: 'Sat',
}

function emptyScheduleRule(): BandwidthScheduleRule {
  return {
    name: '',
    enabled: true,
    daysOfWeek: [2, 3, 4, 5, 6],
    startHour: 9,
    startMinute: 0,
    endHour: 17,
    endMinute: 0,
    maxDownloadKBps: 0,
    maxUploadKBps: 0,
  }
}

function DiskSpaceMonitorSection({
  diskSpaceMinimumGB,
  diskSpaceMonitorPath,
  onMinimumGBChange,
  onMonitorPathChange,
}: {
  diskSpaceMinimumGB: number | null
  diskSpaceMonitorPath: string
  onMinimumGBChange: (value: number | null) => void
  onMonitorPathChange: (value: string) => void
}) {
  const [diskSpace, setDiskSpace] = useState<DiskSpaceStatus | null>(null)

  useEffect(() => {
    let cancelled = false

    async function poll() {
      try {
        const status = await api.diskSpace()
        if (!cancelled) setDiskSpace(status)
      } catch {
        // best-effort — don't block settings UI
      }
    }

    void poll()
    const interval = window.setInterval(poll, 5_000)
    return () => {
      cancelled = true
      window.clearInterval(interval)
    }
  }, [])

  const enabled = diskSpaceMinimumGB !== null

  return (
    <section className="form-panel">
      <div className="form-panel-header">
        <h3>Disk Space Monitor</h3>
        <p>Pause new downloads when free space drops below a threshold on the monitored volume.</p>
      </div>

      <div className="form-grid">
        <label className="toggle-field">
          <span>Enable disk space monitor</span>
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => onMinimumGBChange(e.currentTarget.checked ? 10 : null)}
          />
        </label>

        {enabled && (
          <>
            <label className="field">
              <span>Minimum free space (GB)</span>
              <input
                type="number"
                min={1}
                step={1}
                value={diskSpaceMinimumGB ?? 10}
                onChange={(e) =>
                  onMinimumGBChange(readNumber(e.currentTarget.valueAsNumber, diskSpaceMinimumGB ?? 10))
                }
              />
            </label>

            <label className="field wide">
              <span>Monitor path</span>
              <input
                value={diskSpaceMonitorPath}
                onChange={(e) => onMonitorPathChange(e.target.value)}
                placeholder="/Volumes/Media or /Users/you/Downloads"
              />
            </label>
          </>
        )}
      </div>

      {diskSpace && (
        <div className="form-grid" style={{ marginTop: '0.75rem' }}>
          <div className="field">
            <span style={{ fontSize: '0.88rem', color: 'var(--muted)', display: 'block', marginBottom: '0.25rem' }}>
              Current free space
            </span>
            <strong>{fmtBytes(diskSpace.freeBytes)}</strong>
          </div>
          <div className="field">
            <span style={{ fontSize: '0.88rem', color: 'var(--muted)', display: 'block', marginBottom: '0.25rem' }}>
              Threshold
            </span>
            <strong>{fmtBytes(diskSpace.thresholdBytes)}</strong>
          </div>
          <div className="field">
            <span style={{ fontSize: '0.88rem', color: 'var(--muted)', display: 'block', marginBottom: '0.25rem' }}>
              Status
            </span>
            <span className={`pill ${diskSpace.isPaused ? 'amber' : 'green'}`}>
              {diskSpace.isPaused
                ? `Paused (${diskSpace.pausedCount} torrent${diskSpace.pausedCount !== 1 ? 's' : ''})`
                : 'OK'}
            </span>
          </div>
        </div>
      )}
    </section>
  )
}

function emptyArrEndpoint(): ArrEndpoint {
  return {
    name: '',
    kind: 'sonarr',
    baseURL: '',
    apiKey: '',
  }
}

function ArrIntegrationSection({
  arrReSearchAfterHours,
  arrEndpoints,
  onReSearchHoursChange,
  onEndpointsChange,
}: {
  arrReSearchAfterHours: number
  arrEndpoints: ArrEndpoint[]
  onReSearchHoursChange: (value: number) => void
  onEndpointsChange: (endpoints: ArrEndpoint[]) => void
}) {
  const [notifications, setNotifications] = useState<ArrNotification[]>([])

  useEffect(() => {
    let cancelled = false

    async function poll() {
      try {
        const data = await api.arrNotifications()
        if (!cancelled) setNotifications(data)
      } catch {
        // best-effort
      }
    }

    void poll()
    const interval = window.setInterval(poll, 10_000)
    return () => {
      cancelled = true
      window.clearInterval(interval)
    }
  }, [])

  function updateEndpoint(index: number, updates: Partial<ArrEndpoint>) {
    const next = arrEndpoints.map((ep, i) => (i === index ? { ...ep, ...updates } : ep))
    onEndpointsChange(next)
  }

  function addEndpoint() {
    onEndpointsChange([...arrEndpoints, emptyArrEndpoint()])
  }

  function removeEndpoint(index: number) {
    onEndpointsChange(arrEndpoints.filter((_, i) => i !== index))
  }

  return (
    <section className="form-panel">
      <div className="form-panel-header">
        <h3>*arr Integration</h3>
        <p>Automatically re-search failed grabs in Sonarr/Radarr after a configurable delay.</p>
      </div>

      <div className="form-grid">
        <label className="field">
          <span>Re-search after (hours)</span>
          <input
            type="number"
            min={0}
            step={1}
            value={arrReSearchAfterHours}
            onChange={(e) =>
              onReSearchHoursChange(readNumber(e.currentTarget.valueAsNumber, arrReSearchAfterHours))
            }
          />
        </label>
      </div>

      {arrEndpoints.length === 0 ? (
        <EmptyState
          title="No *arr endpoints"
          body="Add a Sonarr or Radarr endpoint to enable automatic re-search on failed grabs."
        />
      ) : (
        <div className="section-stack">
          {arrEndpoints.map((ep, idx) => (
            <div
              key={idx}
              className="form-panel"
              style={{ background: 'rgba(8, 20, 27, 0.55)' }}
            >
              <div className="form-grid">
                <label className="field">
                  <span>Name</span>
                  <input
                    value={ep.name}
                    onChange={(e) => updateEndpoint(idx, { name: e.target.value })}
                    placeholder="e.g. Sonarr"
                  />
                </label>

                <label className="field">
                  <span>Type</span>
                  <select
                    value={ep.kind}
                    onChange={(e) => updateEndpoint(idx, { kind: e.target.value as 'sonarr' | 'radarr' })}
                  >
                    <option value="sonarr">Sonarr</option>
                    <option value="radarr">Radarr</option>
                  </select>
                </label>

                <label className="field wide">
                  <span>Base URL</span>
                  <input
                    value={ep.baseURL}
                    onChange={(e) => updateEndpoint(idx, { baseURL: e.target.value })}
                    placeholder="http://localhost:8989"
                  />
                </label>

                <label className="field wide">
                  <span>API Key</span>
                  <input
                    type="password"
                    value={ep.apiKey ?? ''}
                    onChange={(e) => updateEndpoint(idx, { apiKey: e.target.value })}
                    placeholder="Leave blank to keep existing key"
                  />
                </label>
              </div>

              <div className="button-row">
                <button type="button" className="danger" onClick={() => removeEndpoint(idx)}>
                  Remove endpoint
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="button-row">
        <button type="button" onClick={addEndpoint}>
          Add endpoint
        </button>
      </div>

      {notifications.length > 0 && (
        <>
          <div className="form-panel-header" style={{ marginTop: '1rem' }}>
            <h3>Recent re-search activity</h3>
            <p>Latest notifications from *arr re-search attempts.</p>
          </div>
          <div className="table-shell">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Torrent</th>
                  <th>Endpoint</th>
                  <th>Result</th>
                  <th>Message</th>
                  <th>When</th>
                </tr>
              </thead>
              <tbody>
                {notifications.map((n, idx) => (
                  <tr key={`${n.infoHash}-${n.timestamp}-${idx}`}>
                    <td className="primary-cell">{n.name}</td>
                    <td>{n.endpoint}</td>
                    <td>
                      <span className={`pill ${n.success ? 'green' : 'red'}`}>
                        {n.success ? 'Success' : 'Failed'}
                      </span>
                    </td>
                    <td>{n.message || '—'}</td>
                    <td title={fmtDateTime(n.timestamp)}>{fmtRelativeTime(n.timestamp)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </section>
  )
}

function BandwidthScheduleSection({
  rules,
  onChange,
}: {
  rules: BandwidthScheduleRule[]
  onChange: (rules: BandwidthScheduleRule[]) => void
}) {
  function updateRule(index: number, updates: Partial<BandwidthScheduleRule>) {
    const next = rules.map((rule, i) => (i === index ? { ...rule, ...updates } : rule))
    onChange(next)
  }

  function addRule() {
    onChange([...rules, emptyScheduleRule()])
  }

  function removeRule(index: number) {
    onChange(rules.filter((_, i) => i !== index))
  }

  function toggleDay(index: number, day: number) {
    const rule = rules[index]
    const days = rule.daysOfWeek.includes(day)
      ? rule.daysOfWeek.filter((d) => d !== day)
      : [...rule.daysOfWeek, day].sort((a, b) => a - b)
    updateRule(index, { daysOfWeek: days })
  }

  return (
    <section className="form-panel">
      <div className="form-panel-header">
        <h3>Bandwidth Schedule</h3>
        <p>Define time-based rules that limit download and upload speeds on specific days.</p>
      </div>

      {rules.length === 0 ? (
        <EmptyState
          title="No bandwidth rules"
          body="Add a schedule rule to throttle speeds during specific windows."
        />
      ) : (
        <div className="section-stack">
          {rules.map((rule, idx) => (
            <div
              key={idx}
              className="form-panel"
              style={{ background: 'rgba(8, 20, 27, 0.55)' }}
            >
              <div className="form-grid">
                <label className="field">
                  <span>Rule name</span>
                  <input
                    value={rule.name}
                    onChange={(e) => updateRule(idx, { name: e.target.value })}
                    placeholder="e.g. Work hours"
                  />
                </label>

                <label className="toggle-field">
                  <span>Enabled</span>
                  <input
                    type="checkbox"
                    checked={rule.enabled}
                    onChange={(e) => updateRule(idx, { enabled: e.currentTarget.checked })}
                  />
                </label>

                <div className="field wide">
                  <span style={{ fontSize: '0.88rem', color: 'var(--muted)', marginBottom: '0.5rem', display: 'block' }}>
                    Days of week
                  </span>
                  <div className="button-row">
                    {([1, 2, 3, 4, 5, 6, 7] as number[]).map((day) => (
                      <button
                        key={day}
                        type="button"
                        className={rule.daysOfWeek.includes(day) ? 'primary' : undefined}
                        style={{ minWidth: '3.2rem', padding: '0.5rem 0.6rem' }}
                        onClick={() => toggleDay(idx, day)}
                      >
                        {DAY_LABELS[day]}
                      </button>
                    ))}
                  </div>
                </div>

                <label className="field">
                  <span>Start hour</span>
                  <input
                    type="number"
                    min={0}
                    max={23}
                    value={rule.startHour}
                    onChange={(e) => updateRule(idx, { startHour: readNumber(e.currentTarget.valueAsNumber, rule.startHour) })}
                  />
                </label>
                <label className="field">
                  <span>Start minute</span>
                  <input
                    type="number"
                    min={0}
                    max={59}
                    value={rule.startMinute}
                    onChange={(e) => updateRule(idx, { startMinute: readNumber(e.currentTarget.valueAsNumber, rule.startMinute) })}
                  />
                </label>
                <label className="field">
                  <span>End hour</span>
                  <input
                    type="number"
                    min={0}
                    max={23}
                    value={rule.endHour}
                    onChange={(e) => updateRule(idx, { endHour: readNumber(e.currentTarget.valueAsNumber, rule.endHour) })}
                  />
                </label>
                <label className="field">
                  <span>End minute</span>
                  <input
                    type="number"
                    min={0}
                    max={59}
                    value={rule.endMinute}
                    onChange={(e) => updateRule(idx, { endMinute: readNumber(e.currentTarget.valueAsNumber, rule.endMinute) })}
                  />
                </label>
                <label className="field">
                  <span>Max download (KB/s)</span>
                  <input
                    type="number"
                    min={0}
                    value={rule.maxDownloadKBps}
                    onChange={(e) => updateRule(idx, { maxDownloadKBps: readNumber(e.currentTarget.valueAsNumber, rule.maxDownloadKBps) })}
                  />
                </label>
                <label className="field">
                  <span>Max upload (KB/s)</span>
                  <input
                    type="number"
                    min={0}
                    value={rule.maxUploadKBps}
                    onChange={(e) => updateRule(idx, { maxUploadKBps: readNumber(e.currentTarget.valueAsNumber, rule.maxUploadKBps) })}
                  />
                </label>
              </div>

              <div className="button-row">
                <button type="button" className="danger" onClick={() => removeRule(idx)}>
                  Remove rule
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="button-row">
        <button type="button" onClick={addRule}>
          Add schedule rule
        </button>
      </div>
    </section>
  )
}

function HealthTab({
  issues,
  onClear,
}: {
  issues: HealthIssue[]
  onClear: (hash: string) => void
}) {
  return (
    <div className="section-stack">
      <header className="section-header">
        <div>
          <h2>Health</h2>
          <p>HealthMonitor snapshots with reason labels and one-click clear actions.</p>
        </div>
        <div className="section-meta">{issues.length} open issues</div>
      </header>

      {issues.length === 0 ? (
        <EmptyState title="All torrents healthy" body="No stalled or flagged torrents right now." />
      ) : (
        <div className="table-shell">
          <table className="data-table">
            <thead>
              <tr>
                <th>Torrent</th>
                <th>Reason</th>
                <th>Progress</th>
                <th>First seen</th>
                <th>Updated</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {issues.map((issue) => (
                <tr key={issue.infoHash}>
                  <td className="primary-cell">{issue.name}</td>
                  <td>
                    <span className="pill amber">{friendlyHealthReason(issue.reason)}</span>
                  </td>
                  <td className="mono-cell">{fmtPercent(issue.lastProgress)}</td>
                  <td title={fmtDateTime(issue.firstSeen)}>{fmtRelativeTime(issue.firstSeen)}</td>
                  <td title={fmtDateTime(issue.lastUpdated)}>{fmtRelativeTime(issue.lastUpdated)}</td>
                  <td>
                    <button type="button" onClick={() => onClear(issue.infoHash)}>
                      Clear
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function PostProcessorTab({ records }: { records: PostProcessorRecord[] }) {
  return (
    <div className="section-stack">
      <header className="section-header">
        <div>
          <h2>Post-Processor</h2>
          <p>Read-only status from the move/extract pipeline behind completed torrents.</p>
        </div>
        <div className="section-meta">{records.length} records</div>
      </header>

      {records.length === 0 ? (
        <EmptyState
          title="No post-processing activity yet"
          body="Finished torrents will show up here once they start moving storage or extracting archives."
        />
      ) : (
        <div className="table-shell">
          <table className="data-table">
            <thead>
              <tr>
                <th>Torrent</th>
                <th>Category</th>
                <th>Stage</th>
                <th>Updated</th>
                <th>Message</th>
              </tr>
            </thead>
            <tbody>
              {records.map((record) => (
                <tr key={`${record.infoHash}-${record.lastUpdated}`}>
                  <td className="primary-cell">{record.name}</td>
                  <td>{record.category || '—'}</td>
                  <td>
                    <span className={`pill ${stageTone(record.stage)}`}>{record.stage}</span>
                  </td>
                  <td title={fmtDateTime(record.lastUpdated)}>{fmtRelativeTime(record.lastUpdated)}</td>
                  <td>{record.message || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function SeedingTab({ records }: { records: SeedingEnforcement[] }) {
  return (
    <div className="section-stack">
      <header className="section-header">
        <div>
          <h2>Seeding</h2>
          <p>Read-only enforcement history for ratio and seed-time limits.</p>
        </div>
        <div className="section-meta">{records.length} actions</div>
      </header>

      {records.length === 0 ? (
        <EmptyState
          title="No seeding-policy actions yet"
          body="Once a torrent crosses a configured ratio or time limit, the action will appear here."
        />
      ) : (
        <div className="table-shell">
          <table className="data-table">
            <thead>
              <tr>
                <th>Torrent</th>
                <th>Action</th>
                <th>Reason</th>
                <th>When</th>
              </tr>
            </thead>
            <tbody>
              {records.map((record) => (
                <tr key={`${record.infoHash}-${record.timestamp}`}>
                  <td className="primary-cell">{record.name}</td>
                  <td>
                    <span className={`pill ${record.action === 'pause' ? 'blue' : 'amber'}`}>
                      {record.action}
                    </span>
                  </td>
                  <td>{record.reason}</td>
                  <td title={fmtDateTime(record.timestamp)}>{fmtRelativeTime(record.timestamp)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function LogTab({
  entries,
  filter,
  deferredFilter,
  onFilterChange,
}: {
  entries: LogEntry[]
  filter: string
  deferredFilter: string
  onFilterChange: (value: string) => void
}) {
  const normalizedFilter = deferredFilter.trim().toLowerCase()
  const visibleEntries = entries.filter((entry) => {
    if (!normalizedFilter) return true
    return (
      entry.message.toLowerCase().includes(normalizedFilter) ||
      entry.source.toLowerCase().includes(normalizedFilter) ||
      entry.level.toLowerCase().includes(normalizedFilter)
    )
  })

  return (
    <div className="section-stack">
      <header className="section-header">
        <div>
          <h2>Log</h2>
          <p>Latest 500 entries from the in-app ring buffer, refreshed every two seconds.</p>
        </div>
        <div className="section-meta">{visibleEntries.length} visible</div>
      </header>

      <div className="toolbar-row">
        <label className="field search-field">
          <span>Filter</span>
          <input
            value={filter}
            onChange={(event) => onFilterChange(event.target.value)}
            placeholder="message, source, or level"
          />
        </label>
      </div>

      {visibleEntries.length === 0 ? (
        <EmptyState title="No matching log entries" body="Try a broader filter or wait for the next refresh." />
      ) : (
        <div className="log-stream">
          {visibleEntries.map((entry) => (
            <div key={entry.id} className="log-row">
              <span className="log-time">{fmtDateTime(entry.timestamp)}</span>
              <span className={`log-level ${entry.level}`}>{entry.level.toUpperCase()}</span>
              <span className="log-source">[{entry.source}]</span>
              <span className="log-message">{entry.message}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function CategoryModal({
  defaultSavePath,
  initialCategory,
  onClose,
  onSave,
}: {
  defaultSavePath: string
  initialCategory?: Category
  onClose: () => void
  onSave: (category: Category) => Promise<void>
}) {
  const isNew = !initialCategory
  const [name, setName] = useState(initialCategory?.name ?? '')
  const [savePath, setSavePath] = useState(initialCategory?.savePath ?? defaultSavePath)
  const [completePath, setCompletePath] = useState(initialCategory?.completePath ?? '')
  const [extractArchives, setExtractArchives] = useState(initialCategory?.extractArchives ?? false)
  const [blockedExtensions, setBlockedExtensions] = useState(
    initialCategory?.blockedExtensions.join(', ') ?? '',
  )
  const [hasMaxRatio, setHasMaxRatio] = useState(initialCategory?.maxRatio != null)
  const [maxRatio, setMaxRatio] = useState(initialCategory?.maxRatio ?? 2)
  const [hasMaxSeedTime, setHasMaxSeedTime] = useState(
    initialCategory?.maxSeedingTimeMinutes != null,
  )
  const [maxSeedTimeMinutes, setMaxSeedTimeMinutes] = useState(
    initialCategory?.maxSeedingTimeMinutes ?? 4_320,
  )
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    const trimmedName = name.trim()
    const trimmedSavePath = savePath.trim()

    if (!trimmedName || !trimmedSavePath) {
      setError('Name and save path are required.')
      return
    }

    try {
      setError(null)
      await onSave({
        name: trimmedName,
        savePath: trimmedSavePath,
        completePath: completePath.trim() || undefined,
        extractArchives,
        blockedExtensions: blockedExtensions
          .split(',')
          .map((entry) => entry.trim())
          .filter(Boolean),
        maxRatio: hasMaxRatio ? maxRatio : null,
        maxSeedingTimeMinutes: hasMaxSeedTime ? maxSeedTimeMinutes : null,
      })
    } catch (saveError: unknown) {
      setError(saveError instanceof Error ? saveError.message : String(saveError))
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <form className="modal-card" onSubmit={handleSubmit} onClick={(event) => event.stopPropagation()}>
        <div className="modal-header">
          <div>
            <div className="brand-kicker">{isNew ? 'New category' : 'Edit category'}</div>
            <h2>{isNew ? 'Create a routing profile' : initialCategory.name}</h2>
          </div>
          <button type="button" onClick={onClose}>
            Close
          </button>
        </div>

        <div className="form-grid">
          <label className="field">
            <span>Name</span>
            <input value={name} onChange={(event) => setName(event.target.value)} disabled={!isNew} />
          </label>
          <label className="field">
            <span>Save path</span>
            <input value={savePath} onChange={(event) => setSavePath(event.target.value)} />
          </label>
          <label className="field wide">
            <span>Complete path (optional)</span>
            <input value={completePath} onChange={(event) => setCompletePath(event.target.value)} />
          </label>
          <label className="toggle-field">
            <span>Extract archives (.rar/.zip/.7z)</span>
            <input
              type="checkbox"
              checked={extractArchives}
              onChange={(event) => setExtractArchives(event.currentTarget.checked)}
            />
          </label>
          <label className="field wide">
            <span>Blocked extensions (comma separated)</span>
            <input
              value={blockedExtensions}
              onChange={(event) => setBlockedExtensions(event.target.value)}
              placeholder=".nfo, .txt, sample.mkv"
            />
          </label>

          <label className="toggle-field">
            <span>Override max ratio</span>
            <input
              type="checkbox"
              checked={hasMaxRatio}
              onChange={(event) => {
                setHasMaxRatio(event.currentTarget.checked)
                if (event.currentTarget.checked && maxRatio <= 0) setMaxRatio(2)
              }}
            />
          </label>

          {hasMaxRatio && (
            <label className="field">
              <span>Max ratio</span>
              <input
                type="number"
                step="0.25"
                min="0"
                value={maxRatio}
                onChange={(event) => setMaxRatio(readNumber(event.currentTarget.valueAsNumber, maxRatio))}
              />
            </label>
          )}

          <label className="toggle-field">
            <span>Override max seed time</span>
            <input
              type="checkbox"
              checked={hasMaxSeedTime}
              onChange={(event) => {
                setHasMaxSeedTime(event.currentTarget.checked)
                if (event.currentTarget.checked && maxSeedTimeMinutes < 0) {
                  setMaxSeedTimeMinutes(4_320)
                }
              }}
            />
          </label>

          {hasMaxSeedTime && (
            <label className="field">
              <span>Max seed time (min)</span>
              <input
                type="number"
                step="60"
                min="0"
                value={maxSeedTimeMinutes}
                onChange={(event) =>
                  setMaxSeedTimeMinutes(
                    readNumber(event.currentTarget.valueAsNumber, maxSeedTimeMinutes),
                  )
                }
              />
            </label>
          )}
        </div>

        {error && <Banner tone="error" message={error} />}

        <div className="button-row">
          <button type="button" onClick={onClose}>
            Cancel
          </button>
          <button className="primary" type="submit">
            Save category
          </button>
        </div>
      </form>
    </div>
  )
}

function OptionalNumberField({
  label,
  value,
  step,
  min,
  onToggle,
  onValueChange,
}: {
  label: string
  value: number | null
  step: number
  min: number
  onToggle: (enabled: boolean) => void
  onValueChange: (value: number | null) => void
}) {
  return (
    <div className="optional-field">
      <label className="toggle-field">
        <span>{label}</span>
        <input
          type="checkbox"
          checked={value !== null}
          onChange={(event) => onToggle(event.currentTarget.checked)}
        />
      </label>
      {value !== null && (
        <label className="field">
          <span>Value</span>
          <input
            type="number"
            step={step}
            min={min}
            value={value}
            onChange={(event) =>
              onValueChange(readNumber(event.currentTarget.valueAsNumber, value))
            }
          />
        </label>
      )}
    </div>
  )
}

function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="empty-state">
      <h2>{title}</h2>
      <p>{body}</p>
    </div>
  )
}

function Banner({ tone, message }: { tone: 'error' | 'success'; message: string }) {
  return <div className={`banner ${tone}`}>{message}</div>
}

function countForTab(tab: TabId, snapshot: LiveSnapshot): number {
  switch (tab) {
    case 'torrents':
      return snapshot.torrents.length
    case 'categories':
      return snapshot.categories.length
    case 'settings':
      return 1
    case 'health':
      return snapshot.health.length
    case 'postprocessor':
      return snapshot.postProcessor.length
    case 'seeding':
      return snapshot.seeding.length
    case 'log':
      return snapshot.log.length
  }
}

function normalizeSettings(settings: Settings): Settings {
  return {
    ...settings,
    webUIPassword: settings.webUIPassword ?? '',
    globalMaxRatio: settings.globalMaxRatio ?? null,
    globalMaxSeedingTimeMinutes: settings.globalMaxSeedingTimeMinutes ?? null,
    bandwidthSchedule: settings.bandwidthSchedule ?? [],
    diskSpaceMinimumGB: settings.diskSpaceMinimumGB ?? null,
    diskSpaceMonitorPath: settings.diskSpaceMonitorPath ?? '',
    arrReSearchAfterHours: settings.arrReSearchAfterHours ?? 6,
    arrEndpoints: settings.arrEndpoints ?? [],
  }
}

function friendlyHealthReason(reason: HealthIssue['reason']): string {
  switch (reason) {
    case 'metadataTimeout':
      return 'Metadata timeout'
    case 'noPeers':
      return 'No peers'
    case 'stalledWithPeers':
      return 'Stalled (with peers)'
    case 'awaitingRecheck':
      return 'Awaiting recheck'
  }
}

function statusPillClass(stats: SessionStats | null): string {
  if (!stats) return 'pill neutral'
  if (stats.hasIncoming) return 'pill green'
  if (stats.numTorrents > 0) return 'pill amber'
  return 'pill neutral'
}

function trackerStatusText(status: number | undefined): string {
  switch (status) {
    case 0: return 'Disabled'
    case 1: return 'Not contacted'
    case 2: return 'Working'
    case 3: return 'Updating'
    case 4: return 'Error'
    default: return 'Unknown'
  }
}

function trackerStatusTone(status: number | undefined): string {
  switch (status) {
    case 2: return 'green'
    case 4: return 'red'
    default: return 'neutral'
  }
}

function stateTone(state: string): string {
  if (state.startsWith('paused')) return 'neutral'
  if (state === 'uploading' || state === 'stalledUP') return 'green'
  if (state === 'error') return 'red'
  return 'blue'
}

function stageTone(stage: string): string {
  if (stage.startsWith('failed')) return 'red'
  if (stage === 'done') return 'green'
  if (stage === 'extracting') return 'amber'
  return 'blue'
}

function readNumber(value: number, fallback: number): number {
  return Number.isFinite(value) ? value : fallback
}

function sortedCopy<T>(values: T[], compare: (a: T, b: T) => number): T[] {
  return [...values].sort(compare)
}
