export function fmtBytes(n: number): string {
  if (n < 1024) return `${n} B`
  const kb = n / 1024
  if (kb < 1024) return `${kb.toFixed(1)} KiB`
  const mb = kb / 1024
  if (mb < 1024) return `${mb.toFixed(1)} MiB`
  const gb = mb / 1024
  return `${gb.toFixed(2)} GiB`
}

export function fmtRate(bps: number): string {
  return `${fmtBytes(bps)}/s`
}

export function fmtETA(s: number): string {
  if (s < 0 || !isFinite(s)) return '∞'
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`
  if (s < 86400) return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`
  return `${Math.floor(s / 86400)}d`
}
