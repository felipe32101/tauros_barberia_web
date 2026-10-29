// POST /api/cita — consultar, cancelar o reprogramar una cita con referencia + token.
// Se usa POST incluso para consultar, para que el token no quede en logs de URLs.
import {
  getAdminClient, send, sendError, readJson, clientKey, rateLimit,
  isUuid, isTimestamp, isIsoDate, isRef, isToken
} from './_lib/server.js'

export default async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'METHOD_NOT_ALLOWED' })

  try {
    const { action, ref, token, date, chair_id, starts_at } = await readJson(req)

    if (!isRef(ref) || !isToken(token)) throw new Error('NOT_FOUND')

    const allowed = await rateLimit(`cita:${clientKey(req)}`, 60, 60)
    if (!allowed) throw new Error('RATE_LIMIT')

    const db = getAdminClient()
    const base = { p_ref: ref.trim().toUpperCase(), p_token: token }
    let result

    switch (action) {
      case 'get':
        result = await db.rpc('get_appointment_by_token', base)
        break
      case 'cancel':
        result = await db.rpc('cancel_appointment_by_token', base)
        break
      case 'availability':
        if (!isIsoDate(date)) throw new Error('BAD_REQUEST')
        result = await db.rpc('get_reschedule_availability', { ...base, p_date: date })
        break
      case 'reschedule':
        if (!isUuid(chair_id) || !isTimestamp(starts_at)) throw new Error('BAD_REQUEST')
        result = await db.rpc('reschedule_appointment_by_token', {
          ...base, p_chair_id: chair_id, p_starts_at: starts_at
        })
        break
      default:
        throw new Error('BAD_REQUEST')
    }

    if (result.error) throw result.error
    return send(res, 200, { data: result.data })
  } catch (err) {
    return sendError(res, err)
  }
}
