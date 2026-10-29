<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ChevronLeft, ChevronRight, Plus } from '@lucide/vue'
import { api } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/errors'
import { fmtDay, fmtTime, fmtDateTime, today, addDays, startOfWeek, localDate, localTime, money, STATUS_LABELS } from '@/lib/format'
import { useRealtimeRefresh } from '@/composables/useRealtimeRefresh'
import { useUiStore } from '@/stores/ui'
import PageHeader from '@/components/admin/PageHeader.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import StateBlock from '@/components/ui/StateBlock.vue'
import AppointmentDetail from '@/components/admin/AppointmentDetail.vue'
import AppointmentCreate from '@/components/admin/AppointmentCreate.vue'

const route = useRoute()
const ui = useUiStore()

const view = ref('dia') // dia | semana | lista
const anchor = ref(today())
const listFrom = ref(today())
const listTo = ref(addDays(today(), 14))
const statusFilter = ref(route.query.estado || '')
if (statusFilter.value) view.value = 'lista'

const range = computed(() => {
  if (view.value === 'dia') return [anchor.value, anchor.value]
  if (view.value === 'semana') { const s = startOfWeek(anchor.value); return [s, addDays(s, 6)] }
  return [listFrom.value, listTo.value]
})

const items = ref([])
const chairs = ref([])
const state = ref('loading')
const err = ref('')

async function load(silent = false) {
  if (!silent) state.value = 'loading'
  try {
    const [from, to] = range.value
    items.value = await api.rpc('admin_list_appointments', { p_from: from, p_to: to })
    state.value = 'ready'
  } catch (e) { err.value = errorMessage(e); state.value = 'error' }
}
onMounted(async () => {
  const { data } = await supabase.from('chairs').select('id, name').eq('is_active', true).order('sort_order').order('name')
  chairs.value = data || []
  await ui.loadInfo()
  load()
})
watch(range, () => load())
useRealtimeRefresh(() => load(true))

function move(n) { anchor.value = addDays(anchor.value, view.value === 'semana' ? n * 7 : n) }

const filtered = computed(() => items.value.filter((a) => !statusFilter.value || a.status === statusFilter.value))
const visible = computed(() => filtered.value.filter((a) => view.value === 'lista' || a.status !== 'cancelada' || showCancelled.value))
const showCancelled = ref(false)

// ---------- Vista día: línea de tiempo por silla ----------
const PX_PER_MIN = 1.3
const dayBounds = computed(() => {
  const h = ui.info?.hours || []
  const opens = h.filter((x) => !x.is_closed).map((x) => x.opens_at.slice(0, 5)).sort()[0] || '08:00'
  const closes = h.filter((x) => !x.is_closed).map((x) => x.closes_at.slice(0, 5)).sort().at(-1) || '20:00'
  const toMin = (t) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5))
  return { start: Math.floor(toMin(opens) / 60) * 60, end: Math.ceil(toMin(closes) / 60) * 60 }
})
const hours = computed(() => {
  const out = []
  for (let m = dayBounds.value.start; m <= dayBounds.value.end; m += 60) out.push(m)
  return out
})
const dayColumns = computed(() => {
  const ids = new Set(chairs.value.map((c) => c.id))
  const extra = visible.value.filter((a) => !ids.has(a.chair_id)).map((a) => ({ id: a.chair_id, name: a.chair_name }))
  const cols = [...chairs.value, ...extra.filter((c, i, arr) => arr.findIndex((x) => x.id === c.id) === i)]
  return cols.map((c) => ({ ...c, items: visible.value.filter((a) => a.chair_id === c.id) }))
})
function blockStyle(a) {
  const toMin = (iso) => { const t = localTime(iso); return Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5)) }
  const top = (toMin(a.starts_at) - dayBounds.value.start) * PX_PER_MIN
  const height = Math.max(26, (new Date(a.ends_at) - new Date(a.starts_at)) / 60000 * PX_PER_MIN - 2)
  return { top: `${top}px`, height: `${height}px` }
}
const timelineHeight = computed(() => (dayBounds.value.end - dayBounds.value.start) * PX_PER_MIN)
const hhmm = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:00`

// ---------- Vista semana ----------
const weekDays = computed(() => {
  const s = startOfWeek(anchor.value)
  return Array.from({ length: 7 }, (_, i) => {
    const d = addDays(s, i)
    return { date: d, items: visible.value.filter((a) => localDate(a.starts_at) === d) }
  })
})

const title = computed(() => {
  if (view.value === 'dia') return fmtDay(anchor.value)
  if (view.value === 'semana') { const [a, b] = range.value; return `${fmtDay(a, { weekday: undefined })} al ${fmtDay(b, { weekday: undefined })}` }
  return 'Lista de citas'
})

const selected = ref(null)
const creating = ref(false)
</script>

<template>
  <PageHeader title="Citas">
    <button class="btn btn--gold btn--sm" @click="creating = true"><Plus :size="16" /> Nueva cita</button>
  </PageHeader>

  <div class="toolbar">
    <div class="seg" role="tablist" aria-label="Vista">
      <button v-for="v in [['dia', 'Día'], ['semana', 'Semana'], ['lista', 'Lista']]" :key="v[0]" role="tab"
              :aria-selected="view === v[0]" :class="{ 'is-on': view === v[0] }" @click="view = v[0]">{{ v[1] }}</button>
    </div>

    <div v-if="view !== 'lista'" class="nav">
      <button class="btn btn--icon btn--ghost" aria-label="Anterior" @click="move(-1)"><ChevronLeft :size="20" /></button>
      <button class="btn btn--sm" @click="anchor = today()">Hoy</button>
      <button class="btn btn--icon btn--ghost" aria-label="Siguiente" @click="move(1)"><ChevronRight :size="20" /></button>
      <input v-model="anchor" type="date" class="input date" aria-label="Ir a fecha" />
    </div>
    <div v-else class="nav">
      <label class="small muted" for="l-from">Desde</label><input id="l-from" v-model="listFrom" type="date" class="input date" />
      <label class="small muted" for="l-to">Hasta</label><input id="l-to" v-model="listTo" type="date" class="input date" />
    </div>

    <div class="filters">
      <select v-model="statusFilter" class="select" aria-label="Filtrar por estado">
        <option value="">Todos los estados</option>
        <option v-for="(l, k) in STATUS_LABELS" :key="k" :value="k">{{ l }}</option>
      </select>
      <label v-if="view !== 'lista'" class="check small"><input v-model="showCancelled" type="checkbox" /> Ver canceladas</label>
    </div>
  </div>

  <h2 class="range-title cap">{{ title }}</h2>

  <StateBlock v-if="state !== 'ready'" :state="state" :message="err" @retry="load()" />

  <!-- Día -->
  <div v-else-if="view === 'dia'" class="day">
    <div class="day__scroll">
      <div class="day__grid" :style="{ '--cols': dayColumns.length }">
        <div class="day__axis" :style="{ height: timelineHeight + 'px' }">
          <span v-for="m in hours" :key="m" :style="{ top: (m - dayBounds.start) * PX_PER_MIN + 'px' }">{{ hhmm(m) }}</span>
        </div>
        <div v-for="c in dayColumns" :key="c.id" class="day__col">
          <div class="day__head">{{ c.name }}</div>
          <div class="day__lane" :style="{ height: timelineHeight + 'px' }">
            <span v-for="m in hours" :key="m" class="day__line" :style="{ top: (m - dayBounds.start) * PX_PER_MIN + 'px' }" />
            <button v-for="a in c.items" :key="a.id" class="block" :class="`block--${a.status}`" :style="blockStyle(a)" @click="selected = a">
              <strong>{{ fmtTime(a.starts_at) }}</strong> {{ a.customer_name }}
              <span class="block__sub">{{ a.service_name }}, {{ a.barber_name }}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
    <p v-if="!visible.length" class="muted small">No hay citas este día.</p>
  </div>

  <!-- Semana -->
  <div v-else-if="view === 'semana'" class="week">
    <section v-for="d in weekDays" :key="d.date" class="week__day" :class="{ 'is-today': d.date === today() }">
      <button class="week__head" @click="anchor = d.date; view = 'dia'">{{ fmtDay(d.date, { month: undefined }) }}</button>
      <p v-if="!d.items.length" class="muted small">Sin citas</p>
      <button v-for="a in d.items" :key="a.id" class="chip" :class="`block--${a.status}`" @click="selected = a">
        <strong>{{ fmtTime(a.starts_at) }}</strong> {{ a.customer_name }}
        <span class="block__sub">{{ a.chair_name }}, {{ a.barber_name }}</span>
      </button>
    </section>
  </div>

  <!-- Lista -->
  <div v-else class="table-wrap">
    <table class="table">
      <thead><tr><th>Fecha y hora</th><th>Cliente</th><th>Servicio</th><th>Barbero</th><th>Silla</th><th>Estado</th><th><span class="sr-only">Acciones</span></th></tr></thead>
      <tbody>
        <tr v-if="!visible.length"><td colspan="7" class="muted">No hay citas en este rango.</td></tr>
        <tr v-for="a in visible" :key="a.id">
          <td>{{ fmtDateTime(a.starts_at) }}</td>
          <td>{{ a.customer_name }}<br /><span class="muted small">{{ a.customer_phone }}</span></td>
          <td>{{ a.service_name }}<br /><span class="muted small">{{ money(a.price) }}</span></td>
          <td>{{ a.barber_name }}</td>
          <td>{{ a.chair_name }}</td>
          <td><StatusBadge :status="a.status" /></td>
          <td><button class="btn btn--sm" @click="selected = a">Ver</button></td>
        </tr>
      </tbody>
    </table>
  </div>

  <AppointmentDetail v-if="selected" :appointment="selected" @close="selected = null" @changed="load(true)" />
  <AppointmentCreate v-if="creating" :date="view === 'lista' ? today() : anchor" @close="creating = false" @saved="creating = false; load(true)" />
</template>

<style scoped>
.toolbar { display: flex; flex-wrap: wrap; gap: var(--space-3); align-items: center; margin-bottom: var(--space-4); }
.seg { display: inline-flex; border: 1px solid var(--line); border-radius: 999px; padding: 3px; }
.seg button { border: 0; background: none; color: var(--steel); padding: 6px 16px; border-radius: 999px; cursor: pointer; }
.seg button.is-on { background: var(--gold); color: var(--on-gold); font-weight: 600; }
.nav, .filters { display: flex; align-items: center; gap: var(--space-2); flex-wrap: wrap; }
.date { width: auto; min-height: 38px; }
.filters .select { width: auto; min-height: 38px; }
.range-title { font-size: var(--step-2); }
.cap::first-letter { text-transform: uppercase; }

.day__scroll { overflow-x: auto; border: 1px solid var(--line); border-radius: var(--radius-m); background: var(--carbon); }
.day__grid { display: grid; grid-template-columns: 56px repeat(var(--cols), minmax(170px, 1fr)); min-width: max-content; padding: 0 var(--space-3) var(--space-4) 0; }
.day__axis { position: relative; margin-top: 44px; }
.day__axis span { position: absolute; right: 8px; transform: translateY(-50%); font-size: 11px; color: var(--steel); font-variant-numeric: tabular-nums; }
.day__head { height: 44px; display: flex; align-items: center; padding: 0 var(--space-3); font-family: var(--font-display); font-size: var(--step-1); border-bottom: 1px solid var(--line); }
.day__lane { position: relative; border-left: 1px solid var(--line); }
.day__line { position: absolute; left: 0; right: 0; border-top: 1px dashed #262626; }
.block {
  position: absolute; left: 6px; right: 6px; overflow: hidden; text-align: left; cursor: pointer;
  padding: 4px 8px; border-radius: var(--radius-s); font-size: 12.5px; line-height: 1.3; color: var(--bone);
  background: var(--graphite); border: 1px solid var(--line); border-left: 3px solid var(--ok);
}
.block:hover { border-color: var(--gold); }
.block__sub { display: block; color: var(--steel); font-size: 11.5px; }
.block--pendiente { border-left-color: var(--busy); }
.block--completada { border-left-color: var(--gold); }
.block--cancelada { border-left-color: var(--off); opacity: .55; text-decoration: line-through; }
.block--no_asistio { border-left-color: var(--danger); }

.week { display: grid; gap: var(--space-3); grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); }
.week__day { background: var(--carbon); border: 1px solid var(--line); border-radius: var(--radius-m); padding: var(--space-3); display: grid; gap: var(--space-2); align-content: start; min-height: 140px; }
.week__day.is-today { border-color: var(--gold-deep); }
.week__head { background: none; border: 0; color: var(--bone); font-family: var(--font-display); font-size: var(--step-1); text-align: left; cursor: pointer; padding: 0; }
.week__head::first-letter { text-transform: uppercase; }
.week__head:hover { color: var(--gold-soft); }
.chip { position: static; text-align: left; cursor: pointer; padding: 6px 8px; border-radius: var(--radius-s); font-size: 12.5px; color: var(--bone); background: var(--graphite); border: 1px solid var(--line); border-left: 3px solid var(--ok); }
.chip:hover { border-color: var(--gold); }
</style>
