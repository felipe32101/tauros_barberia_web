// POST /api/reservas — crea una cita (cliente invitado o con sesión).
import {
  getAdminClient, send, sendError, readJson, clientKey, rateLimit, userFromRequest,
  isUuid, isTimestamp
} from './_lib/server.js'

export default async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'METHOD_NOT_ALLOWED' })

  try {
    const body = await readJson(req)
    const { service_id, chair_id, starts_at, full_name, phone, email, notes } = body

    if (!isUuid(service_id) || !isUuid(chair_id) || !isTimestamp(starts_at)) {
      throw Object.assign(new Error('BAD_REQUEST'), { code: 'BAD_REQUEST' })
    }

    const allowed = await rateLimit(`book:${clientKey(req)}`, 8, 60)
    if (!allowed) throw new Error('RATE_LIMIT')

    const user = await userFromRequest(req)

    const { data, error } = await getAdminClient().rpc('book_appointment', {
      p_service_id: service_id,
      p_chair_id: chair_id,
      p_starts_at: starts_at,
      p_full_name: String(full_name ?? '').slice(0, 120),
      p_phone: String(phone ?? '').slice(0, 30),
      p_email: email ? String(email).slice(0, 160) : null,
      p_notes: notes ? String(notes).slice(0, 600) : null,
      p_user_id: user?.id ?? null
    })
    if (error) throw error

    // TODO notificaciones: aquí se puede enviar correo/WhatsApp cuando exista el servicio.
    return send(res, 201, { appointment: data })
  } catch (err) {
    return sendError(res, err)
  }
}
