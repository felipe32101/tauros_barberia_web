<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { CircleCheck, Copy, TriangleAlert } from '@lucide/vue'
import { api, guestStore, appointmentLink } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { fmtDay, fmtTime, fmtDateTime, money, localDate, addDays } from '@/lib/format'
import { useAvailability } from '@/composables/useAvailability'
import { useUiStore } from '@/stores/ui'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import StateBlock from '@/components/ui/StateBlock.vue'
import CalendarPicker from '@/components/booking/CalendarPicker.vue'
import ChairFloor from '@/components/booking/ChairFloor.vue'
import SlotGrid from '@/components/booking/SlotGrid.vue'
import LiveIndicator from '@/components/booking/LiveIndicator.vue'

const route = useRoute()
const router = useRouter()
const ui = useUiStore()

const ref_ = computed(() => (route.params.ref || '').toString().toUpperCase())
const token = computed(() => {
  const m = /t=([0-9a-f]{48})/i.exec(route.hash || '')
  return m ? m[1] : guestStore.list().find((e) => e.ref === ref_.value)?.token || ''
})
const isNew = computed(() => route.query.nueva === '1')

const appt = ref(null)
const state = ref('idle')
const loadError = ref('')

async function load() {
  if (!ref_.value || !token.value) { state.value = 'idle'; appt.value = null; return }
  state.value = 'loading'
  try {
    appt.value = await api.guest.get(ref_.value, token.value)
    guestStore.add({ ref: appt.value.booking_reference, token: token.value, starts_at: appt.value.starts_at, service: appt.value.service_name })
    state.value = 'ready'
  } catch (e) {
    loadError.value = errorMessage(e)
    state.value = 'error'
  }
}
watch([ref_, token], load, { immediate: true })

// ---------- Búsqueda manual ----------
const lookup = ref('')
const saved = computed(() => guestStore.list())
function openLookup() {
  const v = lookup.value.trim()
  const m = /cita\/(TAU-[A-Z0-9]{6})#t=([0-9a-f]{48})/i.exec(v)
  if (m) router.push({ path: `/cita/${m[1].toUpperCase()}`, hash: `#t=${m[2]}` })
  else ui.toast('Pega el enlace completo que recibiste al reservar.', 'warn')
}

// ---------- Copiar enlace ----------
const link = computed(() => (appt.value ? appointmentLink(appt.value.booking_reference, token.value) : ''))
async function copyLink() {
  try { await navigator.clipboard.writeText(link.value); ui.toast('Enlace copiado.') }
  catch { ui.toast('No se pudo copiar. Selecciona el enlace y cópialo a mano.', 'warn') }
}

// ---------- Cancelar ----------
const busy = ref(false)
async function cancel() {
  const ok = await ui.confirm({
    title: 'Cancelar cita',
    message: `¿Seguro que quieres cancelar tu cita del ${fmtDateTime(appt.value.starts_at)}? El horario quedará libre para otra persona.`,
    confirmText: 'Sí, cancelar cita', cancelText: 'No, mantenerla', danger: true
  })
  if (!ok) return
  busy.value = true
  try {
    appt.value = await api.guest.cancel(ref_.value, token.value)
    ui.toast('Cita cancelada.')
  } catch (e) { ui.toast(errorMessage(e), 'error') }
  finally { busy.value = false }
}

// ---------- Reprogramar ----------
const rescheduling = ref(false)
const newDate = ref(null)
const newChair = ref(null)
const newSlot = ref(null)
const summary = ref(null)
const resEnabled = computed(() => rescheduling.value && Boolean(newDate.value))
const av = useAvailability(newDate, (d) => api.guest.availability(ref_.value, token.value, d), { enabled: resEnabled })
const resChairs = computed(() => av.data.value?.chairs || [])
const resChair = computed(() => resChairs.value.find((c) => c.chair_id === newChair.value))

watch(() => av.changed.value, () => {
  if (newSlot.value && !resChair.value?.slots.includes(newSlot.value)) {
    newSlot.value = null
    ui.toast('El horario que elegiste se acaba de ocupar. Elige otro.', 'warn')
  }
})

async function loadSummary(month) {
  try {
    const from = `${month}-01`
    const to = addDays(addDays(from, 32).slice(0, 7) + '-01', -1)
    const rows = await api.calendarSummary(from, to, appt.value.service_id)
    summary.value = [...(summary.value || []).filter((r) => !r.date.startsWith(month)), ...rows]
  } catch { summary.value = null }
}

function startReschedule() {
  rescheduling.value = true
  newDate.value = localDate(appt.value.starts_at)
  newChair.value = null
  newSlot.value = null
}
async function saveReschedule() {
  busy.value = true
  try {
    appt.value = await api.guest.reschedule(ref_.value, token.value, newChair.value, newSlot.value)
    rescheduling.value = false
    ui.toast('Listo, cambiamos tu cita.')
  } catch (e) {
    ui.toast(errorMessage(e), 'error')
    newSlot.value = null
    av.reload()
  } finally { busy.value = false }
}
</script>

<template>
  <div class="container page">
    <!-- Sin referencia: buscar cita -->
    <template v-if="state === 'idle'">
      <h1>Consultar mi cita</h1>
      <p class="muted">Al reservar te dimos un enlace privado. Pégalo aquí para ver, cambiar o cancelar tu cita.</p>
      <form class="lookup" @submit.prevent="openLookup">
        <div class="field">
          <label for="lookup">Enlace de tu cita</label>
          <input id="lookup" v-model="lookup" class="input" placeholder="https://…/cita/TAU-XXXXXX#t=…" />
        </div>
        <button class="btn btn--gold" type="submit">Ver mi cita</button>
      </form>

      <section v-if="saved.length" class="saved">
        <h2>Reservas hechas desde este dispositivo</h2>
        <ul>
          <li v-for="s in saved" :key="s.ref">
            <RouterLink :to="{ path: `/cita/${s.ref}`, hash: `#t=${s.token}` }">{{ s.ref }}</RouterLink>
            <span class="muted small">{{ s.service }}, {{ fmtDateTime(s.starts_at) }}</span>
          </li>
        </ul>
      </section>
      <p class="small muted">¿Perdiste el enlace? Comunícate con la barbería con tu nombre y teléfono. Si creas una cuenta, tus próximas reservas aparecerán en <RouterLink to="/mis-citas">Mis citas</RouterLink>.</p>
    </template>

    <StateBlock v-else-if="state === 'loading'" state="loading" message="Buscando tu cita…" />
    <template v-else-if="state === 'error'">
      <h1>Tu cita</h1>
      <StateBlock state="error" :message="loadError" @retry="load" />
    </template>

    <!-- Cita encontrada -->
    <template v-else-if="appt">
      <div v-if="isNew && appt.status !== 'cancelada'" class="alert alert--ok success" role="status">
        <CircleCheck :size="22" />
        <div>
          <p><strong>{{ appt.status === 'pendiente' ? 'Reserva recibida. La barbería la confirmará pronto.' : '¡Listo! Tu cita quedó reservada.' }}</strong></p>
          <p class="small">Guarda este enlace: con él puedes ver, cambiar o cancelar tu cita. Por ahora no enviamos confirmaciones por correo ni WhatsApp.</p>
        </div>
      </div>

      <div class="head">
        <div>
          <p class="ref">Reserva {{ appt.booking_reference }}</p>
          <h1 class="cap">{{ fmtDay(localDate(appt.starts_at)) }}</h1>
          <p class="time">{{ fmtTime(appt.starts_at) }} a {{ fmtTime(appt.ends_at) }}</p>
        </div>
        <StatusBadge :status="appt.status" />
      </div>

      <dl class="details panel">
        <div><dt>Servicio</dt><dd>{{ appt.service_name }}</dd></div>
        <div><dt>Precio</dt><dd>{{ money(appt.price) }}</dd></div>
        <div><dt>Silla</dt><dd>{{ appt.chair_name }}</dd></div>
        <div><dt>Barbero</dt><dd>{{ appt.barber_name }}</dd></div>
        <div><dt>A nombre de</dt><dd>{{ appt.customer_name }}, {{ appt.customer_phone }}</dd></div>
        <div v-if="appt.customer_notes"><dt>Observaciones</dt><dd>{{ appt.customer_notes }}</dd></div>
        <div v-if="appt.status === 'pendiente' && appt.pending_expires_at"><dt>Apartada hasta</dt><dd>{{ fmtDateTime(appt.pending_expires_at) }}</dd></div>
      </dl>

      <div class="linkbox">
        <label for="appt-link" class="small muted">Tu enlace privado</label>
        <div class="linkbox__row">
          <input id="appt-link" class="input" :value="link" readonly @focus="$event.target.select()" />
          <button class="btn" @click="copyLink"><Copy :size="16" /> Copiar</button>
        </div>
      </div>

      <div v-if="appt.can_modify && !rescheduling" class="actions">
        <button class="btn btn--gold" :disabled="busy" @click="startReschedule">Cambiar fecha u hora</button>
        <button class="btn btn--danger" :disabled="busy" @click="cancel">Cancelar cita</button>
      </div>
      <p v-else-if="!appt.can_modify && ['pendiente', 'confirmada'].includes(appt.status)" class="alert alert--warn">
        <TriangleAlert :size="18" /> Ya no se puede cambiar en línea (faltan menos de {{ ui.info?.cancel_min_hours ?? 2 }} horas). Comunícate con la barbería.
      </p>

      <!-- Panel de reprogramación -->
      <section v-if="rescheduling" class="resched panel" aria-labelledby="h-res">
        <div class="head-row">
          <h2 id="h-res">Nueva fecha y hora</h2>
          <LiveIndicator :live="av.live.value" />
        </div>
        <div class="resched__grid">
          <CalendarPicker :model-value="newDate" :max-days-ahead="ui.info?.max_days_ahead ?? 30" :summary="summary"
                          @update:model-value="(d) => { newDate = d; newChair = null; newSlot = null }" @month="loadSummary" />
          <div>
            <StateBlock v-if="av.status.value === 'loading'" state="loading" message="Consultando sillas…" />
            <StateBlock v-else-if="av.status.value === 'error'" state="error" :message="errorMessage(av.error.value)" @retry="av.reload()" />
            <StateBlock v-else-if="av.status.value === 'empty'" state="empty" message="Ese día no tiene horarios libres." />
            <template v-else-if="resChairs.length">
              <ChairFloor v-model="newChair" :chairs="resChairs" :duration="appt.duration_minutes" @update:model-value="newSlot = null" />
              <div v-if="resChair" class="res-slots">
                <h3>Horas en {{ resChair.chair_name }}</h3>
                <SlotGrid v-model="newSlot" :slots="resChair.slots" />
              </div>
            </template>
          </div>
        </div>
        <div class="actions">
          <button class="btn" :disabled="busy" @click="rescheduling = false">Volver</button>
          <button class="btn btn--gold" :disabled="busy || !newSlot" @click="saveReschedule">
            {{ newSlot ? `Cambiar a las ${fmtTime(newSlot)}` : 'Elige una hora' }}
          </button>
        </div>
      </section>

      <p class="small"><RouterLink to="/reservar">Hacer otra reserva</RouterLink></p>
    </template>
  </div>
</template>

<style scoped>
.page { padding-top: var(--space-6); max-width: 960px; }
.lookup { max-width: 560px; margin-bottom: var(--space-6); }
.saved ul { list-style: none; padding: 0; display: grid; gap: var(--space-2); }
.saved li { display: flex; flex-wrap: wrap; gap: var(--space-3); align-items: baseline; padding: var(--space-3) var(--space-4); background: var(--carbon); border: 1px solid var(--line); border-radius: var(--radius-s); }
.saved h2 { font-size: var(--step-1); }
.success { align-items: flex-start; }
.success svg { color: var(--ok); flex-shrink: 0; }
.head { display: flex; justify-content: space-between; align-items: flex-start; gap: var(--space-4); flex-wrap: wrap; margin: var(--space-5) 0; }
.ref { color: var(--gold); font-weight: 600; margin-bottom: var(--space-2); letter-spacing: .02em; }
.head h1 { margin-bottom: var(--space-1); }
.time { font-size: var(--step-1); margin: 0; }
.cap::first-letter { text-transform: uppercase; }
.details { padding: 0; margin: 0 0 var(--space-5); }
.details div { display: grid; grid-template-columns: 140px 1fr; gap: var(--space-3); padding: var(--space-3) var(--space-5); border-bottom: 1px solid var(--line); }
.details div:last-child { border-bottom: 0; }
.details dt { color: var(--steel); font-size: var(--step--1); }
.details dd { margin: 0; }
.linkbox { margin-bottom: var(--space-5); }
.linkbox__row { display: flex; gap: var(--space-2); margin-top: var(--space-2); }
.linkbox__row .input { font-size: var(--step--1); }
.actions { display: flex; flex-wrap: wrap; gap: var(--space-3); margin-bottom: var(--space-5); }
.resched { margin-bottom: var(--space-5); }
.head-row { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: baseline; gap: var(--space-2); }
.resched__grid { display: grid; gap: var(--space-5); margin-bottom: var(--space-5); }
@media (min-width: 860px) { .resched__grid { grid-template-columns: 340px 1fr; } }
.res-slots { margin-top: var(--space-5); }
</style>
