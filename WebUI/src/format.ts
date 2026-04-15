const dateFormatter = new Intl.DateTimeFormat(undefined, {
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
  second: '2-digit',
})

const relativeFormatter = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' })

export function fmtBytes(n: number): string {
  if (!Number.isFinite(n)) return '0 B'
  if (n < 1024) return `${n} B`
  const kb = n / 1024
  if (kb < 1024) return `${kb.toFixed(1)} KiB`
  const mb = kb / 1024
  if (mb < 1024) return `${mb.toFixed(1)} MiB`
  const gb = mb / 1024
  if (gb < 1024) return `${gb.toFixed(2)} GiB`
  return `${(gb / 1024).toFixed(2)} TiB`
}

export function fmtRate(bps: number): string {
  return `${fmtBytes(bps)}/s`
}

export function fmtETA(s: number): string {
  if (s < 0 || !Number.isFinite(s)) return '∞'
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`
  if (s < 86400) return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`
  return `${Math.floor(s / 86400)}d ${Math.floor((s % 86400) / 3600)}h`
}

export function fmtPercent(value: number): string {
  return `${(value * 100).toFixed(1)}%`
}

export function fmtDateTime(epochSeconds: number): string {
  return dateFormatter.format(new Date(epochSeconds * 1000))
}

export function fmtRelativeTime(epochSeconds: number): string {
  const now = Date.now()
  const deltaSeconds = Math.round((epochSeconds * 1000 - now) / 1000)
  const units: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ['day', 86_400],
    ['hour', 3_600],
    ['minute', 60],
    ['second', 1],
  ]

  for (const [unit, size] of units) {
    if (Math.abs(deltaSeconds) >= size || unit === 'second') {
      return relativeFormatter.format(Math.round(deltaSeconds / size), unit)
    }
  }

  return 'now'
}

export function fmtOptionalNumber(value: number | null | undefined, suffix = ''): string {
  if (value == null) return 'Inherit'
  return `${value}${suffix}`
}
