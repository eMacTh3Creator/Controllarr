import { useEffect, useState, useCallback } from 'react'
import { api, type Torrent, type SessionStats } from './api'
import { fmtBytes, fmtRate, fmtETA } from './format'

export function App() {
  const [torrents, setTorrents] = useState<Torrent[]>([])
  const [stats, setStats] = useState<SessionStats | null>(null)
  const [magnet, setMagnet] = useState('')
  const [category, setCategory] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [authed, setAuthed] = useState(false)
  const [user, setUser] = useState('admin')
  const [pass, setPass] = useState('adminadmin')

  const refresh = useCallback(async () => {
    try {
      const [t, s] = await Promise.all([api.torrents(), api.stats()])
      setTorrents(t)
      setStats(s)
      setError(null)
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    if (!authed) return
    refresh()
    const id = setInterval(refresh, 2000)
    return () => clearInterval(id)
  }, [authed, refresh])

  async function onLogin(ev: React.FormEvent) {
    ev.preventDefault()
    try {
      await api.login(user, pass)
      setAuthed(true)
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  async function onAdd(ev: React.FormEvent) {
    ev.preventDefault()
    if (!magnet.trim()) return
    try {
      await api.addMagnet(magnet.trim(), category.trim() || undefined)
      setMagnet('')
      await refresh()
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  async function onCyclePort() {
    try { await api.cyclePort() } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  if (!authed) {
    return (
      <div className="app">
        <div className="header">
          <h1>Controllarr</h1>
          <span className="subtitle">sign in</span>
        </div>
        <form className="add-form" onSubmit={onLogin}>
          <label>Username</label>
          <input value={user} onChange={e => setUser(e.target.value)} />
          <label>Password</label>
          <input type="password" value={pass} onChange={e => setPass(e.target.value)} />
          <div className="row">
            <button className="primary" type="submit">Sign in</button>
          </div>
          {error && <div style={{ color: 'var(--danger)' }}>{error}</div>}
        </form>
      </div>
    )
  }

  const listenState = stats?.hasIncoming ? 'good' : (stats && stats.numTorrents > 0 ? 'warn' : '')

  return (
    <div className="app">
      <div className="header">
        <h1>Controllarr</h1>
        <span className="subtitle">v0.1 · {torrents.length} torrent{torrents.length === 1 ? '' : 's'}</span>
      </div>

      <div className="stats">
        <div className="stat">
          <div className="label">Download</div>
          <div className="value">{stats ? fmtRate(stats.downloadRate) : '—'}</div>
        </div>
        <div className="stat">
          <div className="label">Upload</div>
          <div className="value">{stats ? fmtRate(stats.uploadRate) : '—'}</div>
        </div>
        <div className={`stat ${listenState}`}>
          <div className="label">Listen port</div>
          <div className="value">{stats ? stats.listenPort : '—'}</div>
        </div>
        <div className="stat">
          <div className="label">Peers</div>
          <div className="value">{stats ? stats.numPeers : '—'}</div>
        </div>
        <div className="stat">
          <div className="label">Total downloaded</div>
          <div className="value">{stats ? fmtBytes(stats.totalDownloaded) : '—'}</div>
        </div>
        <div className="stat">
          <div className="label">Total uploaded</div>
          <div className="value">{stats ? fmtBytes(stats.totalUploaded) : '—'}</div>
        </div>
      </div>

      <div className="actions">
        <button onClick={onCyclePort}>Cycle listen port</button>
        <button onClick={refresh}>Refresh</button>
      </div>

      <form className="add-form" onSubmit={onAdd}>
        <label>Add magnet link</label>
        <div className="row">
          <input
            placeholder="magnet:?xt=urn:btih:…"
            value={magnet}
            onChange={e => setMagnet(e.target.value)}
          />
          <input
            placeholder="category (optional)"
            value={category}
            onChange={e => setCategory(e.target.value)}
            style={{ maxWidth: 220 }}
          />
          <button className="primary" type="submit">Add</button>
        </div>
      </form>

      <div className="torrents">
        {torrents.length === 0 ? (
          <div className="empty">No torrents yet. Add a magnet above to get started.</div>
        ) : (
          torrents.map(t => <TorrentRow key={t.hash} t={t} onAction={refresh} setError={setError} />)
        )}
      </div>

      {error && (
        <div style={{ marginTop: 16, color: 'var(--danger)' }}>
          {error}
        </div>
      )}
    </div>
  )
}

function TorrentRow({
  t,
  onAction,
  setError,
}: {
  t: Torrent
  onAction: () => void | Promise<void>
  setError: (m: string | null) => void
}) {
  const paused = t.state.startsWith('paused')
  const seeding = t.state === 'uploading' || t.state === 'stalledUP'
  const cls = seeding ? 'seeding' : paused ? 'paused' : ''

  async function run(fn: () => Promise<unknown>) {
    try { await fn(); await onAction() } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  return (
    <div className={`torrent ${cls}`}>
      <div>
        <div className="name">{t.name || '(fetching metadata…)'}</div>
        <div className="meta">
          {(t.progress * 100).toFixed(1)}% · {fmtBytes(t.completed)} / {fmtBytes(t.size)} ·
          ↓{fmtRate(t.dlspeed)} ↑{fmtRate(t.upspeed)} ·
          {t.num_seeds}S/{t.num_leechs}P · ETA {fmtETA(t.eta)} · {t.state}
          {t.category && ` · ${t.category}`}
        </div>
        <div className="bar"><div style={{ width: `${Math.min(100, t.progress * 100)}%` }} /></div>
      </div>
      <div className="controls">
        {paused
          ? <button onClick={() => run(() => api.resume(t.hash))}>Resume</button>
          : <button onClick={() => run(() => api.pause(t.hash))}>Pause</button>}
        <button className="danger" onClick={() => run(() => api.remove(t.hash, false))}>Remove</button>
      </div>
    </div>
  )
}
