// Traduce los códigos que devuelve la base de datos o /api a mensajes claros.
const MESSAGES = {
  INVALID_NAME: 'Escribe el nombre completo (mínimo 3 letras).',
  INVALID_PHONE: 'Revisa el teléfono: debe tener entre 7 y 15 dígitos.',
  INVALID_EMAIL: 'El correo no parece válido.',
  INVALID_NOTES: 'Las observaciones pueden tener máximo 500 caracteres.',
  SERVICE_UNAVAILABLE: 'Ese servicio no está disponible.',
  SLOT_IN_PAST: 'Esa hora ya pasó. Elige otra.',
  DATE_TOO_FAR: 'Esa fecha todavía no está abierta para reservas.',
  DATE_OUT_OF_RANGE: 'Esa fecha no está disponible para reservas.',
  SLOT_UNAVAILABLE: 'Ese horario ya no está disponible. Elige otro.',
  SLOT_TAKEN: 'Alguien acaba de reservar ese horario. Elige otro.',
  TOO_MANY_BOOKINGS: 'Este teléfono ya tiene el máximo de citas activas.',
  NOT_FOUND: 'No encontramos ese registro.',
  NOT_MODIFIABLE: 'Esta cita ya no se puede cambiar ni cancelar.',
  RATE_LIMIT: 'Demasiados intentos. Espera unos minutos.',
  FORBIDDEN: 'No tienes permiso para hacer esto.',
  INVALID_TRANSITION: 'Ese cambio de estado no está permitido.',
  NOT_STARTED_YET: 'La cita aún no ha empezado; no se puede marcar así todavía.',
  HOURS_OUTSIDE_BUSINESS: 'El horario del barbero debe quedar dentro del horario de la barbería.',
  HOURS_OVERLAP: 'Hay franjas del barbero que se cruzan entre sí.',
  INVALID_RANGE: 'La fecha de fin debe ser posterior a la de inicio.',
  RANGE_TOO_LARGE: 'El rango de fechas es demasiado grande.',
  INVALID_STATUS: 'Estado no válido.',
  BAD_REQUEST: 'Faltan datos o no son válidos.'
}

export function errorMessage(err, fallback = 'No pudimos completar la operación. Intenta de nuevo.') {
  if (!err) return fallback
  if (err.serverMessage) return err.serverMessage
  const raw = err.error || err.message || ''
  if (MESSAGES[raw]) return MESSAGES[raw]
  if (err.code === '23505') return 'Ya existe un registro con ese nombre o dato.'
  if (err.code === '23503') return 'No se puede borrar porque tiene citas u otros datos asociados. Desactívalo en su lugar.'
  if (err.code === '23P01') return 'Se cruza con otro registro en el mismo periodo.'
  if (err.code === '42501') return MESSAGES.FORBIDDEN
  if (err.message === 'Failed to fetch' || err.name === 'TypeError') return 'Sin conexión. Revisa tu internet e intenta de nuevo.'
  if (typeof err.message === 'string' && err.message && !/[A-Z_]{6,}/.test(err.message) && err.message.length < 140) return err.message
  return fallback
}
