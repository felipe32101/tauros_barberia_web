<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Plus, Trash2 } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { api } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { WEEKDAYS, today, addDays, localToIso, fmtDateTime } from '@/lib/format'
import { useUiStore } from '@/stores/ui'
import PageHeader from '@/components/admin/PageHeader.vue'
import StateBlock from '@/components/ui/StateBlock.vue'

const ui = useUiStore()
const route = useRoute()
const tab = ref(route.query.barbero ? 'barbero' : 'general')
const hhmm = (t) => (t ? t.slice(0, 5) : '')

const barbers = ref([])
const chairs = ref([])
onMounted(async () => {
  const [b, c] = await Promise.all([
    supabase.from('barbers').select('id, full_name, is_active').order('full_name'),
    supabase.from('chairs').select('id, name').order('sort_order')
  ])
  barbers.value = b.data || []
  chairs.value = c.data || []
  loadGeneral()
  loadExceptions()
})

// ================= Horario general =================
const general = ref([])
const genState = ref('loading')
async function loadGeneral() {
  const { data, error } = await supabase.from('business_hours').select('*').order('weekday')
  if (error) { genState.value = 'error'; return }
  general.value = WEEKDAYS.map((_, i) => {
    const r = data.find((x) => x.weekday === i + 1)
    return { weekday: i + 1, is_closed: r ? r.is_closed : true, opens_at: hhmm(r?.opens_at) || '09:00', closes_at: hhmm(r?.closes_at) || '19:00' }
  })
  genState.value = 'ready'
}
async function saveGeneral() {
  for (const d of general.value) {
    if (!d.is_closed && d.closes_at <= d.opens_at) { ui.toast(`${WEEKDAYS[d.weekday - 1]}: el cierre debe ser después de la apertura.`, 'error'); return }
  }
  const payload = general.value.map((d) => ({ weekday: d.weekday, is_closed: d.is_closed, opens_at: d.is_closed ? null : d.opens_at, closes_at: d.is_closed ? null : d.closes_at }))
  try {
    const res = await ui.withConflicts((confirm) => api.rpc('admin_save_business_hours', { p_hours: payload, p_confirm: confirm }), 'El nuevo horario')
    if (res?.saved) { ui.toast('Horario de la barbería guardado.'); ui.info = null; ui.loadInfo() }
  } catch (e) { ui.toast(errorMessage(e), 'error') }
}

// ================= Horario por barbero =================
const barberId = ref(route.query.barbero || '')
const windows = ref([]) // [{ weekday, starts_at, ends_at }]
const bState = ref('idle')
watch(barberId, loadBarber, { immediate: true })
async function loadBarber() {
  if (!barberId.value) { bState.value = 'idle'; return }
  bState.value = 'loading'
  const { data, error } = await supabase.from('barber_working_hours').select('weekday, starts_at, ends_at').eq('barber_id', barberId.value).eq('is_active', true).order('weekday').order('starts_at')
  if (error) { bState.value = 'error'; return }
  windows.value = data.map((w) => ({ weekday: w.weekday, starts_at: hhmm(w.starts_at), ends_at: hhmm(w.ends_at) }))
  bState.value = 'ready'
}
const byDay = computed(() => WEEKDAYS.map((name, i) => ({ name, weekday: i + 1, items: windows.value.filter((w) => w.weekday === i + 1) })))
function businessFor(wd) { return general.value.find((g) => g.weekday === wd) }
function addWindow(wd) {
  const g = businessFor(wd)
  windows.value.push({ weekday: wd, starts_at: g && !g.is_closed ? g.opens_at : '09:00', ends_at: g && !g.is_closed ? g.closes_at : '18:00' })
}
function removeWindow(w) { windows.value = windows.value.filter((x) => x !== w) }
function copyMondayToWeek() {
  const mon = windows.value.filter((w) => w.weekday === 1)
  windows.value = [...windows.value.filter((w) => w.weekday === 1 || w.weekday > 5), ...[2, 3, 4, 5].flatMap((wd) => mon.map((m) => ({ ...m, weekday: wd })))]
}
async function saveBarber() {
  for (const w of windows.value) {
    if (w.ends_at <= w.starts_at) { ui.toast(`${WEEKDAYS[w.weekday - 1]}: cada franja debe terminar después de empezar.`, 'error'); return }
    const g = businessFor(w.weekday)
    if (!g || g.is_closed || w.starts_at < g.opens_at || w.ends_at > g.closes_at) {
      ui.toast(`${WEEKDAYS[w.weekday - 1]}: la franja debe estar dentro del horario de la barbería.`, 'error'); return
    }
  }
  try {
    const res = await ui.withConflicts((confirm) => api.rpc('admin_save_barber_hours', { p_barber_id: barberId.value, p_hours: windows.value, p_confirm: confirm }), 'El nuevo horario del barbero')
    if (res?.saved) { ui.toast('Horario del barbero guardado.'); loadBarber() }
  } catch (e) { ui.toast(errorMessage(e), 'error') }
}

// ================= Excepciones =================
const TYPES = { cierre: 'Cierre', festivo: 'Festivo', descanso: 'Descanso', vacaciones: 'Vacaciones', mantenimiento: 'Mantenimiento', otro: 'Otro' }
const exceptions = ref([])
const exState = ref('loading')
async function loadExceptions() {
  const { data, error } = await supabase.from('schedule_exceptions').select('*').gt('ends_at', new Date().toISOString()).order('starts_at')
  if (error) { exState.value = 'error'; return }
  exceptions.value = data
  exState.value = 'ready'
}
const ex = reactive({ scope: 'general', barber_id: '', chair_id: '', type: 'festivo', allDay: true, from_date: today(), from_time: '09:00', to_date: today(), to_time: '19:00', reason: '' })
function scopeLabel(x) {
  if (x.barber_id) return barbers.value.find((b) => b.id === x.barber_id)?.full_name || 'Barbero'
  if (x.chair_id) return chairs.value.find((c) => c.id === x.chair_id)?.name || 'Silla'
  return 'Toda la barbería'
}
async function createException() {
  const starts = ex.allDay ? localToIso(ex.from_date, '00:00') : localToIso(ex.from_date, ex.from_time)
  const ends = ex.allDay ? localToIso(addDays(ex.to_date, 1), '00:00') : localToIso(ex.to_date, ex.to_time)
  if (new Date(ends) <= new Date(starts)) { ui.toast('La fecha final debe ser posterior a la inicial.', 'error'); return }
  if (ex.scope === 'barbero' && !ex.barber_id) { ui.toast('Elige el barbero.', 'error'); return }
  if (ex.scope === 'silla' && !ex.chair_id) { ui.toast('Elige la silla.', 'error'); return }
  const p = {
    p_barber_id: ex.scope === 'barbero' ? ex.barber_id : null,
    p_chair_id: ex.scope === 'silla' ? ex.chair_id : null,
    p_starts_at: starts, p_ends_at: ends, p_type: ex.type, p_reason: ex.reason || null
  }
  try {
    const res = await ui.withConflicts((confirm) => api.rpc('admin_create_exception', { ...p, p_confirm: confirm }), 'Este bloqueo')
    if (res?.saved) { ui.toast('Bloqueo guardado.'); ex.reason = ''; loadExceptions() }
  } catch (e) { ui.toast(errorMessage(e), 'error') }
}
async function removeException(x) {
  const ok = await ui.confirm({ title: 'Eliminar bloqueo', message: 'Ese periodo volverá a estar disponible para reservas.', confirmText: 'Eliminar' })
  if (!ok) return
  const { error } = await supabase.from('schedule_exceptions').delete().eq('id', x.id)
  if (error) ui.toast(errorMessage(error), 'error'); else { ui.toast('Bloqueo eliminado.'); loadExceptions() }
}
</script>

<template>
  <PageHeader title="Horarios" subtitle="Si un cambio deja citas por fuera, te mostramos cuáles antes de aplicarlo." />

  <div class="tabs" role="tablist">
    <button role="tab" :aria-selected="tab === 'general'" :class="{ 'is-on': tab === 'general' }" @click="tab = 'general'">Barbería</button>
    <button role="tab" :aria-selected="tab === 'barbero'" :class="{ 'is-on': tab === 'barbero' }" @click="tab = 'barbero'">Por barbero</button>
    <button role="tab" :aria-selected="tab === 'excepciones'" :class="{ 'is-on': tab === 'excepciones' }" @click="tab = 'excepciones'">Cierres y bloqueos</button>
  </div>

  <!-- General -->
  <section v-if="tab === 'general'" class="panel">
    <StateBlock v-if="genState !== 'ready'" :state="genState" @retry="loadGeneral" />
    <template v-else>
      <div v-for="d in general" :key="d.weekday" class="dayrow">
        <span class="dayrow__name">{{ WEEKDAYS[d.weekday - 1] }}</span>
        <label class="check small"><input v-model="d.is_closed" type="checkbox" /> Cerrado</label>
        <template v-if="!d.is_closed">
          <input v-model="d.opens_at" type="time" class="input time" :aria-label="`Apertura ${WEEKDAYS[d.weekday - 1]}`" />
          <span class="muted">a</span>
          <input v-model="d.closes_at" type="time" class="input time" :aria-label="`Cierre ${WEEKDAYS[d.weekday - 1]}`" />
        </template>
      </div>
      <button class="btn btn--gold save" @click="saveGeneral">Guardar horario</button>
    </template>
  </section>

  <!-- Por barbero -->
  <section v-else-if="tab === 'barbero'" class="panel">
    <div class="field pick">
      <label for="s-barber">Barbero</label>
      <select id="s-barber" v-model="barberId" class="select">
        <option value="">Elige un barbero</option>
        <option v-for="b in barbers" :key="b.id" :value="b.id">{{ b.full_name }}{{ b.is_active ? '' : ' (inactivo)' }}</option>
      </select>
    </div>
    <StateBlock v-if="bState === 'idle'" state="empty" message="Elige un barbero para ver y editar su horario." />
    <StateBlock v-else-if="bState !== 'ready'" :state="bState" @retry="loadBarber" />
    <template v-else>
      <p class="muted small">Para una pausa (almuerzo), crea dos franjas el mismo día: por ejemplo 9:00 a 13:00 y 14:00 a 19:00.</p>
      <div v-for="d in byDay" :key="d.weekday" class="dayrow dayrow--wrap">
        <span class="dayrow__name">{{ d.name }}</span>
        <span v-if="businessFor(d.weekday)?.is_closed" class="muted small">La barbería cierra</span>
        <template v-else>
          <span v-if="!d.items.length" class="muted small">No trabaja</span>
          <span v-for="(w, i) in d.items" :key="i" class="win">
            <input v-model="w.starts_at" type="time" class="input time" :aria-label="`Inicio franja ${d.name}`" />
            <span class="muted">a</span>
            <input v-model="w.ends_at" type="time" class="input time" :aria-label="`Fin franja ${d.name}`" />
            <button class="btn btn--ghost btn--icon" :aria-label="`Quitar franja del ${d.name}`" @click="removeWindow(w)"><Trash2 :size="16" /></button>
          </span>
          <button class="btn btn--sm" @click="addWindow(d.weekday)"><Plus :size="14" /> Franja</button>
        </template>
      </div>
      <div class="save-row">
        <button class="btn btn--sm" @click="copyMondayToWeek">Copiar lunes a martes–viernes</button>
        <button class="btn btn--gold" @click="saveBarber">Guardar horario del barbero</button>
      </div>
    </template>
  </section>

  <!-- Excepciones -->
  <section v-else class="ex">
    <form class="panel" @submit.prevent="createException">
      <h2>Nuevo cierre o bloqueo</h2>
      <div class="ex__grid">
        <div class="field">
          <label for="ex-scope">Aplica a</label>
          <select id="ex-scope" v-model="ex.scope" class="select">
            <option value="general">Toda la barbería</option>
            <option value="barbero">Un barbero</option>
            <option value="silla">Una silla</option>
          </select>
        </div>
        <div v-if="ex.scope === 'barbero'" class="field">
          <label for="ex-b">Barbero</label>
          <select id="ex-b" v-model="ex.barber_id" class="select"><option value="" disabled>Elige</option><option v-for="b in barbers" :key="b.id" :value="b.id">{{ b.full_name }}</option></select>
        </div>
        <div v-if="ex.scope === 'silla'" class="field">
          <label for="ex-c">Silla</label>
          <select id="ex-c" v-model="ex.chair_id" class="select"><option value="" disabled>Elige</option><option v-for="c in chairs" :key="c.id" :value="c.id">{{ c.name }}</option></select>
        </div>
        <div class="field">
          <label for="ex-type">Tipo</label>
          <select id="ex-type" v-model="ex.type" class="select"><option v-for="(l, k) in TYPES" :key="k" :value="k">{{ l }}</option></select>
        </div>
      </div>
      <label class="check small allday"><input v-model="ex.allDay" type="checkbox" /> Días completos</label>
      <div class="ex__grid">
        <div class="field"><label for="ex-fd">Desde</label><input id="ex-fd" v-model="ex.from_date" type="date" class="input" /></div>
        <div v-if="!ex.allDay" class="field"><label for="ex-ft">Hora</label><input id="ex-ft" v-model="ex.from_time" type="time" class="input" /></div>
        <div class="field"><label for="ex-td">Hasta</label><input id="ex-td" v-model="ex.to_date" type="date" class="input" /></div>
        <div v-if="!ex.allDay" class="field"><label for="ex-tt">Hora</label><input id="ex-tt" v-model="ex.to_time" type="time" class="input" /></div>
      </div>
      <div class="field"><label for="ex-r">Motivo</label><input id="ex-r" v-model="ex.reason" class="input" maxlength="200" placeholder="Festivo, vacaciones, capacitación…" /></div>
      <button class="btn btn--gold" type="submit">Guardar bloqueo</button>
    </form>

    <h2 class="ex__title">Próximos cierres y bloqueos</h2>
    <StateBlock v-if="exState !== 'ready'" :state="exState" @retry="loadExceptions" />
    <StateBlock v-else-if="!exceptions.length" state="empty" message="No hay cierres ni bloqueos programados." />
    <div v-else class="table-wrap">
      <table class="table">
        <thead><tr><th>Desde</th><th>Hasta</th><th>Aplica a</th><th>Tipo</th><th>Motivo</th><th><span class="sr-only">Acciones</span></th></tr></thead>
        <tbody>
          <tr v-for="x in exceptions" :key="x.id">
            <td>{{ fmtDateTime(x.starts_at) }}</td>
            <td>{{ fmtDateTime(x.ends_at) }}</td>
            <td>{{ scopeLabel(x) }}</td>
            <td>{{ TYPES[x.type] }}</td>
            <td class="muted">{{ x.reason || '—' }}</td>
            <td><button class="btn btn--sm btn--danger" @click="removeException(x)">Eliminar</button></td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<style scoped>
.tabs { display: inline-flex; border: 1px solid var(--line); border-radius: 999px; padding: 3px; margin-bottom: var(--space-4); flex-wrap: wrap; }
.tabs button { border: 0; background: none; color: var(--steel); padding: 6px 16px; border-radius: 999px; cursor: pointer; }
.tabs button.is-on { background: var(--gold); color: var(--on-gold); font-weight: 600; }
.dayrow { display: flex; align-items: center; gap: var(--space-3); padding: var(--space-3) 0; border-bottom: 1px solid var(--line); flex-wrap: wrap; }
.dayrow__name { width: 96px; font-weight: 600; }
.time { width: 130px; min-height: 38px; }
.win { display: inline-flex; align-items: center; gap: var(--space-2); }
.save { margin-top: var(--space-4); }
.save-row { display: flex; flex-wrap: wrap; justify-content: space-between; gap: var(--space-3); margin-top: var(--space-4); }
.pick { max-width: 360px; }
.ex h2 { font-size: var(--step-1); }
.ex__grid { display: grid; gap: 0 var(--space-3); grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); }
.allday { margin-bottom: var(--space-3); }
.ex__title { margin-top: var(--space-6); }
</style>
