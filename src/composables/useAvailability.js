import { ref, watch, onBeforeUnmount, unref } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * Carga la disponibilidad de un día y la mantiene al día con Supabase Realtime.
 *
 * loader(date) → Promise<{ chairs: [...] }>
 * Estados: idle | loading | ready | empty | error
 * `changed` se activa cuando llega una actualización mientras el cliente está eligiendo.
 */
export function useAvailability(dateRef, loader, { enabled = ref(true) } = {}) {
  const status = ref('idle')
  const data = ref(null)
  const error = ref(null)
  const live = ref('connecting') // connecting | live | offline
  const changed = ref(0)
  let reqId = 0
  let timer = null

  async function load({ silent = false } = {}) {
    const date = unref(dateRef)
    if (!date || !unref(enabled)) { status.value = 'idle'; data.value = null; return }
    const id = ++reqId
    if (!silent) status.value = 'loading'
    error.value = null
    try {
      const result = await loader(date)
      if (id !== reqId) return
      data.value = result
      const anySlot = (result?.chairs || []).some((c) => c.slots?.length)
      status.value = anySlot ? 'ready' : 'empty'
      if (silent) changed.value++
    } catch (e) {
      if (id !== reqId) return
      error.value = e
      status.value = 'error'
    }
  }

  watch([() => unref(dateRef), () => unref(enabled)], () => load(), { immediate: true })

  // Realtime: escuchamos la tabla pública availability_events (sin datos personales)
  const channel = supabase
    .channel(`availability-${Math.random().toString(36).slice(2)}`)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'availability_events' }, (payload) => {
      const day = payload.new?.day
      if (day && day !== unref(dateRef)) return
      clearTimeout(timer)
      timer = setTimeout(() => load({ silent: true }), 350)
    })
    .subscribe((s) => {
      if (s === 'SUBSCRIBED') live.value = 'live'
      else if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT' || s === 'CLOSED') live.value = 'offline'
    })

  // Respaldo: si Realtime no está conectado, refresca cada 45 s
  const poll = setInterval(() => { if (live.value !== 'live' && status.value !== 'loading') load({ silent: true }) }, 45000)

  onBeforeUnmount(() => {
    clearTimeout(timer)
    clearInterval(poll)
    supabase.removeChannel(channel)
  })

  return { status, data, error, live, changed, reload: load }
}

// Estado de una silla en una hora concreta (para el filtro "¿tienes una hora en mente?")
export function chairStatusAt(chair, iso, durationMin, bufferMin = 0) {
  if (!iso) return chair.status
  if (chair.slots?.includes(iso)) return 'disponible'
  if (chair.status === 'no_disponible') return 'no_disponible'
  const s = new Date(iso).getTime()
  const e = s + (durationMin + bufferMin) * 60000
  const busy = (chair.busy || []).some(([bs, be]) => new Date(bs).getTime() < e && new Date(be).getTime() > s)
  return busy ? 'ocupada' : 'no_disponible'
}
