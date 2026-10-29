<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { TriangleAlert, Check, ChevronLeft } from '@lucide/vue'
import { api, guestStore } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { fmtDay, fmtTime, money, minutesLabel, addDays } from '@/lib/format'
import { useAvailability } from '@/composables/useAvailability'
import { useUiStore } from '@/stores/ui'
import { useAuthStore } from '@/stores/auth'
import ServiceCard from '@/components/ServiceCard.vue'
import CalendarPicker from '@/components/booking/CalendarPicker.vue'
import ChairFloor from '@/components/booking/ChairFloor.vue'
import SlotGrid from '@/components/booking/SlotGrid.vue'
import LiveIndicator from '@/components/booking/LiveIndicator.vue'
import StateBlock from '@/components/ui/StateBlock.vue'

const router = useRouter()
const ui = useUiStore()
const auth = useAuthStore()

const STEPS = ['Servicio', 'Fecha', 'Silla', 'Hora', 'Tus datos', 'Confirmar']
const step = ref(1)

// ---------- Paso 1: servicio ----------
const services = ref([])
const svcState = ref('loading')
const svcError = ref('')
const service = ref(null)

async function loadServices() {
  svcState.value = 'loading'
  try {
    services.value = await api.activeServices()
    svcState.value = services.value.length ? 'ready' : 'empty'
  } catch (e) { svcError.value = errorMessage(e); svcState.value = 'error' }
}
onMounted(loadServices)

function pickService(s) {
  service.value = s
  date.value = null
  chairId.value = null
  slot.value = null
  step.value = 2
}

// ---------- Paso 2: fecha ----------
const date = ref(null)
const summary = ref(null)
const summaryLoading = ref(false)
const maxDays = computed(() => ui.info?.max_days_ahead ?? 30)

async function loadSummary(month) {
  if (!service.value) return
  summaryLoading.value = true
  try {
    const from = `${month}-01`
    const to = addDays(addDays(from, 32).slice(0, 7) + '-01', -1)
    const rows = await api.calendarSummary(from, to, service.value.id)
    const map = new Map((summary.value || []).map((r) => [r.date, r]))
    rows.forEach((r) => map.set(r.date, r))
    summary.value = [...map.values()]
  } catch { /* el calendario sigue funcionando sin el resumen */ }
  finally { summaryLoading.value = false }
}
watch(service, () => { summary.value = null })
function pickDate(d) {
  date.value = d
  chairId.value = null
  slot.value = null
  focusTime.value = ''
  notice.value = ''
  step.value = 3
}

// ---------- Pasos 3 y 4: sillas y hora ----------
const chairId = ref(null)
const slot = ref(null)
const focusTime = ref('')
const availEnabled = computed(() => Boolean(service.value && date.value))
const { status, data, error, live, changed, reload } = useAvailability(
  date, (d) => api.availability(d, service.value.id), { enabled: availEnabled }
)
const chairs = computed(() => data.value?.chairs || [])
const chair = computed(() => chairs.value.find((c) => c.chair_id === chairId.value))
const allTimes = computed(() => [...new Set(chairs.value.flatMap((c) => c.slots || []))].sort())
const notice = ref('')

function pickChair(id) {
  chairId.value = id
  slot.value = focusTime.value && chair.value?.slots.includes(focusTime.value) ? focusTime.value : null
  step.value = 4
}
function pickSlot(s) { slot.value = s; step.value = 5 }

// Si la disponibilidad cambia mientras el cliente elige, revisamos su selección
watch(changed, () => {
  if (!slot.value || !chair.value) return
  if (!chair.value.slots.includes(slot.value)) {
    notice.value = `El horario de las ${fmtTime(slot.value)} acaba de ocuparse. Elige otro.`
    slot.value = null
    if (step.value > 4) step.value = 4
  }
})

// ---------- Paso 5: datos ----------
const form = reactive({ full_name: auth.profile?.full_name || '', phone: '', email: auth.user?.email || '', notes: '' })
const touched = ref(false)
const formErrors = computed(() => {
  const e = {}
  const name = form.full_name.trim()
  if (name.length < 3) e.full_name = 'Escribe tu nombre completo.'
  const digits = form.phone.replace(/[^0-9]/g, '')
  if (digits.length < 7 || digits.length > 15) e.phone = 'Escribe un teléfono de 7 a 15 dígitos.'
  if (form.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.email.trim())) e.email = 'Revisa el correo.'
  if (form.notes.length > 500) e.notes = 'Máximo 500 caracteres.'
  return e
})
function submitData() {
  touched.value = true
  if (Object.keys(formErrors.value).length) return
  step.value = 6
}

// ---------- Paso 6: confirmar ----------
const submitting = ref(false)
const submitError = ref('')

async function confirm() {
  submitting.value = true
  submitError.value = ''
  try {
    const appt = await api.book({
      service_id: service.value.id,
      chair_id: chairId.value,
      starts_at: slot.value,
      full_name: form.full_name.trim(),
      phone: form.phone.trim(),
      email: form.email.trim() || null,
      notes: form.notes.trim() || null
    })
    guestStore.add({ ref: appt.booking_reference, token: appt.access_token, starts_at: appt.starts_at, service: appt.service_name })
    router.replace({ path: `/cita/${appt.booking_reference}`, query: { nueva: '1' }, hash: `#t=${appt.access_token}` })
  } catch (e) {
    submitError.value = errorMessage(e)
    if (['SLOT_TAKEN', 'SLOT_UNAVAILABLE', 'SLOT_IN_PAST'].includes(e.error)) {
      slot.value = null
      await reload({ silent: false })
      step.value = 4
      notice.value = submitError.value
    }
  } finally {
    submitting.value = false
  }
}

function goTo(n) { if (n < step.value) step.value = n }
const endTime = computed(() => slot.value && service.value
  ? new Date(new Date(slot.value).getTime() + service.value.duration_minutes * 60000).toISOString() : null)
</script>

<template>
  <div class="container booking">
    <h1>Agendar cita</h1>

    <ol class="stepper" aria-label="Pasos de la reserva">
      <li v-for="(s, i) in STEPS" :key="s" :class="{ 'is-done': step > i + 1, 'is-current': step === i + 1 }" :aria-current="step === i + 1 ? 'step' : undefined">
        <button v-if="step > i + 1" class="stepper__btn" @click="goTo(i + 1)">
          <span class="stepper__n"><Check :size="14" /></span><span class="stepper__label">{{ s }}</span>
        </button>
        <span v-else class="stepper__btn"><span class="stepper__n">{{ i + 1 }}</span><span class="stepper__label">{{ s }}</span></span>
      </li>
    </ol>

    <!-- Resumen lateral de lo elegido -->
    <div class="layout">
      <div class="main">
        <!-- 1. Servicio -->
        <section v-if="step === 1" aria-labelledby="h-step1">
          <h2 id="h-step1">¿Qué te vas a hacer?</h2>
          <StateBlock v-if="svcState !== 'ready'" :state="svcState" :message="svcState === 'empty' ? 'No hay servicios disponibles en este momento.' : svcError" @retry="loadServices" />
          <div v-else class="services" role="radiogroup" aria-label="Servicios">
            <ServiceCard v-for="s in services" :key="s.id" :service="s" selectable :selected="service?.id === s.id" @select="pickService" />
          </div>
        </section>

        <!-- 2. Fecha -->
        <section v-else-if="step === 2" aria-labelledby="h-step2">
          <h2 id="h-step2">Escoge el día</h2>
          <p class="muted">Los días tachados no tienen horarios libres para {{ service.name.toLowerCase() }}.</p>
          <CalendarPicker :model-value="date" @update:model-value="pickDate" :max-days-ahead="maxDays" :summary="summary" :loading="summaryLoading" @month="loadSummary" />
        </section>

        <!-- 3. Silla -->
        <section v-else-if="step === 3" aria-labelledby="h-step3">
          <div class="head-row">
            <h2 id="h-step3">Escoge la silla</h2>
            <LiveIndicator :live="live" />
          </div>
          <p class="muted">{{ fmtDay(date) }}. Cada silla tiene su barbero asignado.</p>

          <div v-if="notice" class="alert alert--warn" role="alert"><TriangleAlert :size="18" /><p>{{ notice }}</p></div>

          <StateBlock v-if="status === 'loading'" state="loading" message="Consultando sillas disponibles…" />
          <StateBlock v-else-if="status === 'error'" state="error" :message="errorMessage(error)" @retry="reload()" />
          <template v-else-if="chairs.length">
            <div v-if="allTimes.length" class="field focus">
              <label for="focus-time">¿Tienes una hora en mente? (opcional)</label>
              <select id="focus-time" v-model="focusTime" class="select">
                <option value="">Ver todo el día</option>
                <option v-for="t in allTimes" :key="t" :value="t">{{ fmtTime(t) }}</option>
              </select>
            </div>
            <StateBlock v-if="status === 'empty'" state="empty" message="Este día ya no tiene horarios libres. Prueba con otra fecha.">
              <button class="btn btn--sm" @click="step = 2">Cambiar fecha</button>
            </StateBlock>
            <ChairFloor :chairs="chairs" :model-value="chairId" :focus-time="focusTime || null"
                        :duration="service.duration_minutes" :buffer="service.buffer_minutes" @update:model-value="pickChair" />
          </template>
          <StateBlock v-else state="empty" message="No hay sillas habilitadas por ahora." />
        </section>

        <!-- 4. Hora -->
        <section v-else-if="step === 4" aria-labelledby="h-step4">
          <div class="head-row">
            <h2 id="h-step4">Escoge la hora</h2>
            <LiveIndicator :live="live" />
          </div>
          <p class="muted">{{ chair?.chair_name }} con {{ chair?.barber_name }}, {{ fmtDay(date) }}. El servicio dura {{ minutesLabel(service.duration_minutes) }}.</p>
          <div v-if="notice" class="alert alert--warn" role="alert"><TriangleAlert :size="18" /><p>{{ notice }}</p></div>
          <StateBlock v-if="status === 'loading'" state="loading" message="Actualizando horarios…" />
          <SlotGrid v-else-if="chair?.slots?.length" :slots="chair.slots" :model-value="slot" @update:model-value="pickSlot" />
          <StateBlock v-else state="empty" message="Esta silla ya no tiene horarios libres este día.">
            <button class="btn btn--sm" @click="step = 3">Ver otras sillas</button>
          </StateBlock>
        </section>

        <!-- 5. Datos -->
        <section v-else-if="step === 5" aria-labelledby="h-step5">
          <h2 id="h-step5">Tus datos</h2>
          <p class="muted">Solo los usamos para tu cita. <template v-if="!auth.isLoggedIn">No necesitas crear cuenta.</template></p>
          <form class="form" novalidate @submit.prevent="submitData">
            <div class="field">
              <label for="f-name">Nombre completo</label>
              <input id="f-name" v-model="form.full_name" class="input" autocomplete="name" maxlength="100" :aria-invalid="touched && !!formErrors.full_name" />
              <p v-if="touched && formErrors.full_name" class="field-error">{{ formErrors.full_name }}</p>
            </div>
            <div class="field">
              <label for="f-phone">Teléfono / WhatsApp</label>
              <input id="f-phone" v-model="form.phone" class="input" type="tel" inputmode="tel" autocomplete="tel" maxlength="20" placeholder="300 123 4567" :aria-invalid="touched && !!formErrors.phone" />
              <p v-if="touched && formErrors.phone" class="field-error">{{ formErrors.phone }}</p>
            </div>
            <div class="field">
              <label for="f-email">Correo (opcional)</label>
              <input id="f-email" v-model="form.email" class="input" type="email" autocomplete="email" maxlength="160" :aria-invalid="touched && !!formErrors.email" />
              <p v-if="touched && formErrors.email" class="field-error">{{ formErrors.email }}</p>
            </div>
            <div class="field">
              <label for="f-notes">Observaciones (opcional)</label>
              <textarea id="f-notes" v-model="form.notes" class="textarea" maxlength="500" placeholder="Por ejemplo: quiero el mismo corte de la vez pasada" />
              <p v-if="touched && formErrors.notes" class="field-error">{{ formErrors.notes }}</p>
            </div>
            <button class="btn btn--gold" type="submit">Revisar reserva</button>
          </form>
        </section>

        <!-- 6. Confirmar -->
        <section v-else-if="step === 6" aria-labelledby="h-step6">
          <h2 id="h-step6">Revisa y confirma</h2>
          <dl class="summary panel">
            <div><dt>Servicio</dt><dd>{{ service.name }}</dd></div>
            <div><dt>Fecha</dt><dd class="cap">{{ fmtDay(date) }}</dd></div>
            <div><dt>Hora</dt><dd>{{ fmtTime(slot) }} a {{ fmtTime(endTime) }}</dd></div>
            <div><dt>Silla</dt><dd>{{ chair?.chair_name }}</dd></div>
            <div><dt>Barbero</dt><dd>{{ chair?.barber_name }}</dd></div>
            <div><dt>Precio</dt><dd>{{ money(service.price) }}</dd></div>
            <div><dt>A nombre de</dt><dd>{{ form.full_name }}<br /><span class="muted">{{ form.phone }}<template v-if="form.email">, {{ form.email }}</template></span></dd></div>
            <div v-if="form.notes"><dt>Observaciones</dt><dd>{{ form.notes }}</dd></div>
          </dl>
          <div v-if="submitError" class="alert alert--error" role="alert"><TriangleAlert :size="18" /><p>{{ submitError }}</p></div>
          <p v-if="ui.info && !ui.info.auto_confirm" class="muted small">La barbería revisará tu reserva y la confirmará. Mientras tanto el horario queda apartado para ti.</p>
          <div class="actions">
            <button class="btn" :disabled="submitting" @click="step = 5"><ChevronLeft :size="16" /> Editar datos</button>
            <button class="btn btn--gold" :disabled="submitting" @click="confirm">{{ submitting ? 'Reservando…' : 'Confirmar reserva' }}</button>
          </div>
        </section>
      </div>

      <aside v-if="step > 1" class="side panel" aria-label="Tu selección">
        <h3>Tu cita</h3>
        <dl class="side__list">
          <div><dt>Servicio</dt><dd>{{ service?.name }} <span class="muted">({{ money(service?.price) }})</span></dd></div>
          <div v-if="date"><dt>Fecha</dt><dd class="cap">{{ fmtDay(date) }}</dd></div>
          <div v-if="chair"><dt>Silla</dt><dd>{{ chair.chair_name }}, {{ chair.barber_name }}</dd></div>
          <div v-if="slot"><dt>Hora</dt><dd>{{ fmtTime(slot) }}</dd></div>
        </dl>
        <button class="btn btn--sm btn--ghost" @click="step = 1">Cambiar servicio</button>
      </aside>
    </div>
  </div>
</template>

<style scoped>
.booking { padding-top: var(--space-6); }
.stepper { list-style: none; padding: 0; margin: var(--space-4) 0 var(--space-6); display: flex; gap: var(--space-2); overflow-x: auto; }
.stepper li { flex: 1; min-width: max-content; }
.stepper__btn {
  display: flex; align-items: center; gap: var(--space-2); width: 100%; padding: var(--space-2) 0;
  background: none; border: 0; border-top: 2px solid var(--line); color: var(--steel); font-size: var(--step--1); text-align: left;
}
button.stepper__btn { cursor: pointer; }
button.stepper__btn:hover { color: var(--gold-soft); }
.stepper__n {
  display: inline-grid; place-items: center; width: 22px; height: 22px; border-radius: 50%;
  border: 1px solid currentColor; font-size: 11px; font-weight: 700; flex-shrink: 0;
}
.is-done .stepper__btn { border-top-color: var(--gold-deep); color: var(--bone); }
.is-done .stepper__n { background: var(--gold-deep); border-color: var(--gold-deep); color: var(--on-gold); }
.is-current .stepper__btn { border-top-color: var(--gold); color: var(--gold); font-weight: 600; }
@media (max-width: 640px) { .stepper li:not(.is-current) .stepper__label { display: none; } }

.layout { display: grid; gap: var(--space-6); }
@media (min-width: 1000px) { .layout { grid-template-columns: 1fr 300px; align-items: start; } .side { position: sticky; top: 96px; } }
.services { display: grid; gap: var(--space-3); grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); }
.head-row { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: baseline; gap: var(--space-2); }
.focus { max-width: 320px; }
.form { max-width: 520px; }
.summary { display: grid; gap: 0; padding: 0; margin: 0 0 var(--space-4); }
.summary div { display: grid; grid-template-columns: 130px 1fr; gap: var(--space-3); padding: var(--space-3) var(--space-5); border-bottom: 1px solid var(--line); }
.summary div:last-child { border-bottom: 0; }
.summary dt, .side__list dt { color: var(--steel); font-size: var(--step--1); }
.summary dd, .side__list dd { margin: 0; }
.cap::first-letter { text-transform: uppercase; }
.actions { display: flex; flex-wrap: wrap; gap: var(--space-3); }
.side h3 { margin-bottom: var(--space-3); }
.side__list { margin: 0 0 var(--space-3); display: grid; gap: var(--space-3); }
</style>
