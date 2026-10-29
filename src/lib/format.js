// Fechas y moneda. Todo se muestra en la zona horaria de la barbería.
export const DEFAULT_TZ = 'America/Bogota'
let currentTz = DEFAULT_TZ

export function setTimezone(tz) { if (tz) currentTz = tz }
export function getTimezone() { return currentTz }

const cop = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 })
export const money = (v) => cop.format(Number(v || 0))

export function fmtTime(iso, tz = currentTz) {
  return new Intl.DateTimeFormat('es-CO', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: tz })
    .format(new Date(iso))
}

// 'YYYY-MM-DD' → "lunes, 2 de noviembre"
export function fmtDay(dateStr, opts = {}) {
  return new Intl.DateTimeFormat('es-CO', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC', ...opts })
    .format(new Date(`${dateStr}T12:00:00Z`))
}

export function fmtDateTime(iso, tz = currentTz) {
  return new Intl.DateTimeFormat('es-CO', {
    weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true, timeZone: tz
  }).format(new Date(iso))
}

// Fecha local (YYYY-MM-DD) de un instante en la zona de la barbería
export function localDate(iso = new Date(), tz = currentTz) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(new Date(iso))
}
export const today = () => localDate(new Date())

export function localTime(iso, tz = currentTz) {
  return new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false })
    .format(new Date(iso))
}

export function addDays(dateStr, n) {
  const d = new Date(`${dateStr}T12:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

// 1 = lunes … 7 = domingo
export function isoWeekday(dateStr) {
  const d = new Date(`${dateStr}T12:00:00Z`).getUTCDay()
  return d === 0 ? 7 : d
}

export function startOfWeek(dateStr) { return addDays(dateStr, 1 - isoWeekday(dateStr)) }

// Diferencia (minutos) entre la hora local de `tz` y UTC en un instante dado
function tzOffsetMinutes(utcMs, tz) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit'
    }).formatToParts(new Date(utcMs)).map((p) => [p.type, p.value])
  )
  const asUtc = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second)
  return (asUtc - utcMs) / 60000
}

// ('2026-11-02', '14:30') en la zona de la barbería → ISO UTC
export function localToIso(dateStr, timeStr, tz = currentTz) {
  const [y, m, d] = dateStr.split('-').map(Number)
  const [hh, mm] = timeStr.split(':').map(Number)
  const guess = Date.UTC(y, m - 1, d, hh, mm)
  const offset = tzOffsetMinutes(guess, tz)
  let result = guess - offset * 60000
  const offset2 = tzOffsetMinutes(result, tz)
  if (offset2 !== offset) result = guess - offset2 * 60000
  return new Date(result).toISOString()
}

export const WEEKDAYS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']

export const STATUS_LABELS = {
  pendiente: 'Pendiente',
  confirmada: 'Confirmada',
  completada: 'Completada',
  cancelada: 'Cancelada',
  no_asistio: 'No asistió'
}

export function minutesLabel(n) {
  const h = Math.floor(n / 60)
  const m = n % 60
  if (!h) return `${m} min`
  return m ? `${h} h ${m} min` : `${h} h`
}
