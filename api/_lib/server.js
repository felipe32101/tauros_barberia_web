// Utilidades compartidas por las funciones de /api (Vercel). Los archivos que
// empiezan por "_" no se publican como rutas.
import { createClient } from '@supabase/supabase-js'
import { createHash } from 'node:crypto'

let admin = null

export function getAdminClient() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) {
    throw Object.assign(new Error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en el servidor'), { code: 'CONFIG' })
  }
  if (!admin) {
    admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  }
  return admin
}

export function send(res, status, body) {
  res.statusCode = status
  res.setHeader('Content-Type', 'application/json; charset=utf-8')
  res.setHeader('Cache-Control', 'no-store')
  res.end(JSON.stringify(body))
}

export async function readJson(req) {
  if (req.body && typeof req.body === 'object') return req.body
  if (typeof req.body === 'string') return JSON.parse(req.body || '{}')
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > 20_000) throw Object.assign(new Error('Body too large'), { code: 'BAD_REQUEST' })
    chunks.push(chunk)
  }
  const raw = Buffer.concat(chunks).toString('utf8')
  return raw ? JSON.parse(raw) : {}
}

// Identificador anónimo del cliente para limitar solicitudes (nunca se guarda la IP).
export function clientKey(req) {
  const fwd = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim()
  const ip = fwd || req.headers['x-real-ip'] || req.socket?.remoteAddress || 'unknown'
  const salt = process.env.RATE_LIMIT_SALT || 'tauros'
  return createHash('sha256').update(`${salt}:${ip}`).digest('hex').slice(0, 32)
}

export async function rateLimit(bucket, limit, windowMinutes) {
  const { data, error } = await getAdminClient().rpc('register_rate_hit', {
    p_bucket: bucket, p_limit: limit, p_window_minutes: windowMinutes
  })
  if (error) throw error
  return data === true
}

// Si el cliente inició sesión, enlazamos la cita a su cuenta.
export async function userFromRequest(req) {
  const auth = String(req.headers.authorization || '')
  if (!auth.startsWith('Bearer ')) return null
  const { data, error } = await getAdminClient().auth.getUser(auth.slice(7))
  if (error) return null
  return data?.user ?? null
}

const MESSAGES = {
  INVALID_NAME:        [400, 'Escribe tu nombre completo (mínimo 3 letras).'],
  INVALID_PHONE:       [400, 'Revisa el número de teléfono: debe tener entre 7 y 15 dígitos.'],
  INVALID_EMAIL:       [400, 'El correo no parece válido.'],
  INVALID_NOTES:       [400, 'Las observaciones pueden tener máximo 500 caracteres.'],
  SERVICE_UNAVAILABLE: [409, 'Ese servicio ya no está disponible. Elige otro.'],
  SLOT_IN_PAST:        [409, 'Esa hora ya pasó. Elige otra.'],
  DATE_TOO_FAR:        [409, 'Esa fecha todavía no está abierta para reservas.'],
  DATE_OUT_OF_RANGE:   [409, 'Esa fecha no está disponible para reservas.'],
  SLOT_UNAVAILABLE:    [409, 'Ese horario ya no está disponible. Elige otro.'],
  SLOT_TAKEN:          [409, 'Alguien acaba de reservar ese horario. Elige otro.'],
  TOO_MANY_BOOKINGS:   [409, 'Este teléfono ya tiene el máximo de citas activas.'],
  NOT_FOUND:           [404, 'No encontramos una cita con esos datos.'],
  NOT_MODIFIABLE:      [409, 'Esta cita ya no se puede cambiar ni cancelar en línea. Comunícate con la barbería.'],
  RATE_LIMIT:          [429, 'Demasiados intentos. Espera unos minutos y vuelve a intentar.'],
  BAD_REQUEST:         [400, 'Solicitud inválida.']
}

export function sendError(res, err) {
  const code = Object.keys(MESSAGES).find((k) => err?.message === k || err?.code === k)
  if (code) {
    const [status, message] = MESSAGES[code]
    return send(res, status, { error: code, message })
  }
  // No exponemos detalles internos al cliente
  console.error('[api]', err?.code || '', err?.message || err)
  return send(res, 500, { error: 'SERVER_ERROR', message: 'No pudimos completar la operación. Intenta de nuevo.' })
}

export const isUuid = (v) => typeof v === 'string' && /^[0-9a-f-]{36}$/i.test(v)
export const isIsoDate = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)
export const isTimestamp = (v) => typeof v === 'string' && !Number.isNaN(Date.parse(v))
export const isRef = (v) => typeof v === 'string' && /^TAU-[A-Z0-9]{6}$/i.test(v.trim())
export const isToken = (v) => typeof v === 'string' && /^[0-9a-f]{48}$/i.test(v)
