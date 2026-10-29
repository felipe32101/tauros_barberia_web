<script setup>
import { computed, onMounted, ref } from 'vue'
import { UserPlus, CalendarDays, Armchair } from '@lucide/vue'
import { api } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { fmtDay, fmtTime, fmtDateTime, today } from '@/lib/format'
import { useRealtimeRefresh } from '@/composables/useRealtimeRefresh'
import PageHeader from '@/components/admin/PageHeader.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import StateBlock from '@/components/ui/StateBlock.vue'

const d = ref(null)
const state = ref('loading')
const err = ref('')

async function load(silent = false) {
  if (!silent) state.value = 'loading'
  try {
    d.value = await api.rpc('admin_dashboard', { p_date: today() })
    state.value = 'ready'
  } catch (e) { err.value = errorMessage(e); state.value = 'error' }
}
onMounted(load)
useRealtimeRefresh(() => load(true))

const tiles = computed(() => d.value ? [
  { label: 'Citas hoy', value: d.value.today_total, to: '/admin/citas' },
  { label: 'Pendientes por confirmar', value: d.value.pending, to: '/admin/citas?estado=pendiente', warn: d.value.pending > 0 },
  { label: 'Confirmadas hoy', value: d.value.today_confirmed },
  { label: 'Completadas hoy', value: d.value.today_completed },
  { label: 'Canceladas hoy', value: d.value.today_cancelled },
  { label: 'Barberos activos', value: d.value.active_barbers, to: '/admin/barberos' },
  { label: 'Sillas habilitadas', value: d.value.active_chairs, to: '/admin/sillas' }
] : [])

const pct = (o) => (o.available_minutes ? Math.min(100, Math.round((o.booked_minutes / o.available_minutes) * 100)) : 0)
</script>

<template>
  <PageHeader title="Resumen" :subtitle="d ? fmtDay(d.date) : ''">
    <RouterLink to="/admin/barberos?nuevo=1" class="btn btn--sm"><UserPlus :size="16" /> Registrar barbero</RouterLink>
    <RouterLink to="/admin/citas" class="btn btn--sm"><CalendarDays :size="16" /> Calendario</RouterLink>
    <RouterLink to="/admin/sillas" class="btn btn--sm"><Armchair :size="16" /> Sillas</RouterLink>
  </PageHeader>

  <StateBlock v-if="state !== 'ready'" :state="state" :message="err" @retry="load()" />
  <template v-else>
    <div class="tiles">
      <component :is="t.to ? 'RouterLink' : 'div'" v-for="t in tiles" :key="t.label" :to="t.to" class="tile" :class="{ 'tile--warn': t.warn }">
        <span class="tile__value">{{ t.value }}</span>
        <span class="tile__label">{{ t.label }}</span>
      </component>
    </div>

    <div class="cols">
      <section class="panel">
        <h2>Ocupación de las sillas hoy</h2>
        <ul class="occ">
          <li v-for="o in d.occupancy" :key="o.chair_id">
            <div class="occ__top">
              <strong>{{ o.chair_name }}</strong>
              <span class="muted small">{{ o.barber_name || 'Sin barbero' }}</span>
              <span class="occ__pct">{{ o.available_minutes ? `${pct(o)} %` : 'Sin turno' }}</span>
            </div>
            <div class="bar" role="progressbar" :aria-valuenow="pct(o)" aria-valuemin="0" aria-valuemax="100" :aria-label="`Ocupación de ${o.chair_name}`">
              <span :style="{ width: pct(o) + '%' }" />
            </div>
            <span class="muted small">{{ o.appointments }} {{ o.appointments === 1 ? 'cita' : 'citas' }}, {{ o.booked_minutes }} de {{ o.available_minutes }} min</span>
          </li>
        </ul>
      </section>

      <section class="panel">
        <h2>Próximas citas</h2>
        <p v-if="!d.upcoming.length" class="muted">No hay citas próximas.</p>
        <ul v-else class="next">
          <li v-for="a in d.upcoming" :key="a.id">
            <div>
              <strong>{{ fmtDateTime(a.starts_at) }}</strong>
              <span class="muted small">{{ a.customer_name }}, {{ a.service_name }}. {{ a.chair_name }} con {{ a.barber_name }}</span>
            </div>
            <StatusBadge :status="a.status" />
          </li>
        </ul>
        <RouterLink to="/admin/citas" class="small">Ver calendario completo</RouterLink>
      </section>
    </div>
  </template>
</template>

<style scoped>
.tiles { display: grid; gap: var(--space-3); grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); margin-bottom: var(--space-5); }
.tile {
  display: grid; gap: var(--space-1); padding: var(--space-4); background: var(--carbon);
  border: 1px solid var(--line); border-radius: var(--radius-m); color: var(--bone); text-decoration: none;
}
a.tile:hover { border-color: var(--gold); color: var(--bone); }
.tile__value { font-family: var(--font-display); font-size: var(--step-3); line-height: 1; }
.tile__label { color: var(--steel); font-size: var(--step--1); }
.tile--warn { border-color: color-mix(in srgb, var(--busy) 60%, transparent); }
.tile--warn .tile__value { color: var(--busy); }
.cols { display: grid; gap: var(--space-4); }
@media (min-width: 1100px) { .cols { grid-template-columns: 1fr 1fr; } }
.cols h2 { font-size: var(--step-1); }
.occ, .next { list-style: none; padding: 0; margin: 0 0 var(--space-3); display: grid; gap: var(--space-4); }
.occ__top { display: flex; align-items: baseline; gap: var(--space-3); margin-bottom: 6px; }
.occ__pct { margin-left: auto; font-variant-numeric: tabular-nums; }
.bar { height: 8px; background: var(--graphite); border-radius: 99px; overflow: hidden; margin-bottom: 4px; }
.bar span { display: block; height: 100%; background: var(--gold); border-radius: inherit; transition: width .4s var(--ease); }
.next li { display: flex; justify-content: space-between; align-items: center; gap: var(--space-3); padding-bottom: var(--space-3); border-bottom: 1px solid var(--line); }
.next li div { display: grid; }
</style>
