// Llamadas a las funciones de servidor (/api) y a las funciones públicas de Supabase.
import { supabase } from './supabase'

async function post(path, body) {
  const headers = { 'Content-Type': 'application/json' }
  const { data } = await supabase.auth.getSession()
  if (data?.session?.access_token) headers.Authorization = `Bearer ${data.session.access_token}`

  const res = await fetch(path, { method: 'POST', headers, body: JSON.stringify(body) })
  let json = {}
  try { json = await res.json() } catch { /* respuesta vacía */ }
  if (!res.ok) throw Object.assign(new Error(json.error || 'SERVER_ERROR'), { error: json.error, serverMessage: json.message, status: res.status })
  return json
}

async function rpc(name, params) {
  const { data, error } = await supabase.rpc(name, params)
  if (error) throw error
  return data
}

export const api = {
  publicInfo: () => rpc('get_public_info'),
  availability: (date, serviceId) => rpc('get_availability', { p_date: date, p_service_id: serviceId }),
  calendarSummary: (from, to, serviceId) => rpc('get_calendar_summary', { p_from: from, p_to: to, p_service_id: serviceId }),
  activeServices: async () => {
    const { data, error } = await supabase
      .from('services')
      .select('id, name, description, price, duration_minutes, buffer_minutes, is_sample')
      .eq('is_active', true)
      .order('sort_order').order('name')
    if (error) throw error
    return data
  },

  book: (payload) => post('/api/reservas', payload).then((r) => r.appointment),

  guest: {
    get: (ref, token) => post('/api/cita', { action: 'get', ref, token }).then((r) => r.data),
    cancel: (ref, token) => post('/api/cita', { action: 'cancel', ref, token }).then((r) => r.data),
    availability: (ref, token, date) => post('/api/cita', { action: 'availability', ref, token, date }).then((r) => r.data),
    reschedule: (ref, token, chairId, startsAt) =>
      post('/api/cita', { action: 'reschedule', ref, token, chair_id: chairId, starts_at: startsAt }).then((r) => r.data)
  },

  myAppointments: () => rpc('my_appointments'),
  cancelMine: (id) => rpc('cancel_my_appointment', { p_id: id }),

  rpc
}

// Reservas de invitado guardadas en este navegador (solo comodidad, no es la fuente de verdad)
const KEY = 'tauros.guestBookings'
export const guestStore = {
  list() {
    try { return JSON.parse(localStorage.getItem(KEY) || '[]') } catch { return [] }
  },
  add(entry) {
    try {
      const list = guestStore.list().filter((e) => e.ref !== entry.ref)
      list.unshift(entry)
      localStorage.setItem(KEY, JSON.stringify(list.slice(0, 10)))
    } catch { /* almacenamiento no disponible */ }
  },
  remove(ref) {
    try { localStorage.setItem(KEY, JSON.stringify(guestStore.list().filter((e) => e.ref !== ref))) } catch { /* */ }
  }
}

export function appointmentLink(ref, token) {
  return `${window.location.origin}/cita/${encodeURIComponent(ref)}#t=${token}`
}
