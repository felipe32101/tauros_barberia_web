<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { Plus, Wrench } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { api } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { today, fmtDateTime, localToIso, fmtTime } from '@/lib/format'
import { useUiStore } from '@/stores/ui'
import { useRealtimeRefresh } from '@/composables/useRealtimeRefresh'
import PageHeader from '@/components/admin/PageHeader.vue'
import BaseModal from '@/components/ui/BaseModal.vue'
import StateBlock from '@/components/ui/StateBlock.vue'
import ChairFloor from '@/components/booking/ChairFloor.vue'
import SlotGrid from '@/components/booking/SlotGrid.vue'

const ui = useUiStore()
const chairs = ref([])
const barbers = ref([])
const assignments = ref([])
const blocks = ref([])
const state = ref('loading')
const err = ref('')
const t = today()

async function load() {
  try {
    const nowIso = new Date().toISOString()
    const [c, b, a, x] = await Promise.all([
      supabase.from('chairs').select('*').order('sort_order').order('name'),
      supabase.from('barbers').select('id, full_name, is_active').order('full_name'),
      supabase.from('barber_chair_assignments').select('*').or(`valid_until.is.null,valid_until.gt.${t}`),
      supabase.from('schedule_exceptions').select('*').not('chair_id', 'is', null).gt('ends_at', nowIso).order('starts_at')
    ])
    for (const r of [c, b, a, x]) if (r.error) throw r.error
    chairs.value = c.data; barbers.value = b.data; assignments.value = a.data; blocks.value = x.data
    state.value = 'ready'
  } catch (e) { err.value = errorMessage(e); state.value = 'error' }
}
onMounted(() => { load(); loadServices() })

function barberOf(chairId) {
  const a = assignments.value.find((x) => x.chair_id === chairId && x.valid_from <= t)
  return a ? barbers.value.find((b) => b.id === a.barber_id) : null
}

// ---------- Crear / editar ----------
const editing = ref(null)
const form = reactive({ name: '', description: '', sort_order: 0 })
const formError = ref('')
function openForm(c = null) {
  editing.value = c || {}
  Object.assign(form, { name: c?.name || `Silla ${chairs.value.length + 1}`, description: c?.description || '', sort_order: c?.sort_order ?? chairs.value.length + 1 })
  formError.value = ''
}
async function saveForm() {
  const payload = { name: form.name.trim(), description: form.description.trim() || null, sort_order: Number(form.sort_order) || 0 }
  if (!payload.name) { formError.value = 'Escribe un nombre.'; return }
  const { error } = editing.value.id
    ? await supabase.from('chairs').update(payload).eq('id', editing.value.id)
    : await supabase.from('chairs').insert(payload)
  if (error) { formError.value = errorMessage(error); return }
  ui.toast('Silla guardada.')
  editing.value = null
  load()
}

async function toggle(c) {
  try {
    const res = await ui.withConflicts(
      (confirm) => api.rpc('admin_set_chair_active', { p_id: c.id, p_active: !c.is_active, p_confirm: confirm }),
      `Deshabilitar ${c.name}`)
    if (res?.saved) { ui.toast(c.is_active ? 'Silla deshabilitada.' : 'Silla habilitada.'); load() }
  } catch (e) { ui.toast(errorMessage(e), 'error') }
}

// ---------- Asignar barbero ----------
const assigning = ref(null)
const assignBarber = ref('')
function openAssign(c) { assigning.value = c; assignBarber.value = barberOf(c.id)?.id || '' }
async function saveAssign() {
  try {
    let res
    if (!assignBarber.value) {
      const current = barberOf(assigning.value.id)
      if (!current) { assigning.value = null; return }
      res = await ui.withConflicts((confirm) => api.rpc('admin_assign_barber', { p_barber_id: current.id, p_chair_id: null, p_valid_from: t, p_confirm: confirm }), 'Dejar la silla sin barbero')
    } else {
      res = await ui.withConflicts((confirm) => api.rpc('admin_assign_barber', { p_barber_id: assignBarber.value, p_chair_id: assigning.value.id, p_valid_from: t, p_confirm: confirm }), 'Cambiar el barbero')
    }
    if (res?.saved) { ui.toast('Asignación guardada.'); assigning.value = null; load() }
  } catch (e) { ui.toast(errorMessage(e), 'error') }
}

// ---------- Bloqueo por mantenimiento ----------
const blocking = ref(null)
const blockForm = reactive({ from_date: t, from_time: '09:00', to_date: t, to_time: '19:00', reason: '' })
function openBlock(c) { blocking.value = c; Object.assign(blockForm, { from_date: t, from_time: '09:00', to_date: t, to_time: '19:00', reason: '' }) }
async function saveBlock() {
  try {
    const p = {
      p_barber_id: null, p_chair_id: blocking.value.id,
      p_starts_at: localToIso(blockForm.from_date, blockForm.from_time),
      p_ends_at: localToIso(blockForm.to_date, blockForm.to_time),
      p_type: 'mantenimiento', p_reason: blockForm.reason || null
    }
    const res = await ui.withConflicts((confirm) => api.rpc('admin_create_exception', { ...p, p_confirm: confirm }), 'Este bloqueo')
    if (res?.saved) { ui.toast('Silla bloqueada en ese periodo.'); blocking.value = null; load() }
  } catch (e) { ui.toast(errorMessage(e), 'error') }
}
async function removeBlock(x) {
  const ok = await ui.confirm({ title: 'Quitar bloqueo', message: 'El horario volverá a estar disponible para reservas.', confirmText: 'Quitar bloqueo' })
  if (!ok) return
  const { error } = await supabase.from('schedule_exceptions').delete().eq('id', x.id)
  if (error) ui.toast(errorMessage(error), 'error'); else { ui.toast('Bloqueo eliminado.'); load() }
}

// ---------- Ocupación y franjas libres ----------
const services = ref([])
const avDate = ref(t)
const avService = ref('')
const av = ref(null)
const avChair = ref(null)
const avState = ref('idle')
async function loadServices() {
  const { data } = await supabase.from('services').select('id, name, duration_minutes').eq('is_active', true).order('sort_order')
  services.value = data || []
  avService.value = services.value[0]?.id || ''
  loadAv()
}
async function loadAv() {
  if (!avService.value) return
  avState.value = 'loading'
  try {
    av.value = await api.rpc('admin_availability', { p_date: avDate.value, p_service_id: avService.value, p_exclude_appointment: null })
    avState.value = 'ready'
  } catch (e) { avState.value = 'error' }
}
useRealtimeRefresh(loadAv)
const avDuration = computed(() => services.value.find((s) => s.id === avService.value)?.duration_minutes || 30)
const avSelected = computed(() => av.value?.chairs?.find((c) => c.chair_id === avChair.value))
</script>

<template>
  <PageHeader title="Sillas" subtitle="La cantidad de sillas es la que ven los clientes al reservar.">
    <button class="btn btn--gold btn--sm" @click="openForm()"><Plus :size="16" /> Agregar silla</button>
  </PageHeader>

  <StateBlock v-if="state !== 'ready'" :state="state" :message="err" @retry="load" />
  <div v-else class="cards">
    <article v-for="c in chairs" :key="c.id" class="card panel" :class="{ off: !c.is_active }">
      <div class="card__top">
        <h2>{{ c.name }}</h2>
        <span :class="c.is_active ? 'on-txt' : 'muted'" class="small">{{ c.is_active ? 'Habilitada' : 'Deshabilitada' }}</span>
      </div>
      <p class="muted small">{{ c.description || 'Sin descripción' }}</p>
      <p><span class="muted small">Barbero:</span> {{ barberOf(c.id)?.full_name || 'Sin barbero' }}</p>
      <ul v-if="blocks.some((b) => b.chair_id === c.id)" class="blocks">
        <li v-for="b in blocks.filter((b) => b.chair_id === c.id)" :key="b.id" class="small">
          <Wrench :size="14" aria-hidden="true" /> {{ fmtDateTime(b.starts_at) }} a {{ fmtDateTime(b.ends_at) }}<template v-if="b.reason">: {{ b.reason }}</template>
          <button class="btn btn--ghost btn--sm" @click="removeBlock(b)">Quitar</button>
        </li>
      </ul>
      <div class="card__actions">
        <button class="btn btn--sm" @click="openForm(c)">Editar</button>
        <button class="btn btn--sm" :disabled="!c.is_active" @click="openAssign(c)">Barbero</button>
        <button class="btn btn--sm" :disabled="!c.is_active" @click="openBlock(c)">Bloquear</button>
        <button class="btn btn--sm" :class="c.is_active ? 'btn--danger' : ''" @click="toggle(c)">{{ c.is_active ? 'Deshabilitar' : 'Habilitar' }}</button>
      </div>
    </article>
  </div>

  <section class="avail">
    <h2>Ocupación y franjas libres</h2>
    <div class="avail__bar">
      <div class="field"><label for="av-date">Fecha</label><input id="av-date" v-model="avDate" type="date" class="input" @change="loadAv" /></div>
      <div class="field"><label for="av-svc">Para el servicio</label>
        <select id="av-svc" v-model="avService" class="select" @change="loadAv"><option v-for="s in services" :key="s.id" :value="s.id">{{ s.name }}</option></select>
      </div>
    </div>
    <StateBlock v-if="avState === 'loading'" state="loading" />
    <StateBlock v-else-if="avState === 'error'" state="error" @retry="loadAv" />
    <template v-else-if="av">
      <ChairFloor v-model="avChair" :chairs="av.chairs" :duration="avDuration" />
      <div v-if="avSelected" class="avail__slots">
        <h3>{{ avSelected.chair_name }}: {{ avSelected.slots.length }} franjas libres</h3>
        <SlotGrid :slots="avSelected.slots" :model-value="null" label="Franjas libres" />
        <p v-if="avSelected.busy.length" class="muted small">Ocupada: {{ avSelected.busy.map(([s, e]) => `${fmtTime(s)} a ${fmtTime(e)}`).join('; ') }}</p>
      </div>
    </template>
  </section>

  <BaseModal v-if="editing" :title="editing.id ? 'Editar silla' : 'Agregar silla'" @close="editing = null">
    <form id="chair-form" @submit.prevent="saveForm">
      <div class="field"><label for="ch-name">Nombre o número</label><input id="ch-name" v-model="form.name" class="input" maxlength="50" /></div>
      <div class="field"><label for="ch-desc">Descripción (opcional)</label><input id="ch-desc" v-model="form.description" class="input" maxlength="200" /></div>
      <div class="field"><label for="ch-order">Orden en pantalla</label><input id="ch-order" v-model="form.sort_order" type="number" class="input" min="0" /></div>
      <p v-if="formError" class="field-error">{{ formError }}</p>
    </form>
    <template #footer>
      <button class="btn" @click="editing = null">Cancelar</button>
      <button class="btn btn--gold" type="submit" form="chair-form">Guardar</button>
    </template>
  </BaseModal>

  <BaseModal v-if="assigning" :title="`Barbero de ${assigning.name}`" @close="assigning = null">
    <p class="muted small">El cambio aplica desde hoy. Si el barbero tenía otra silla, la deja.</p>
    <div class="field">
      <label for="ch-barber">Barbero</label>
      <select id="ch-barber" v-model="assignBarber" class="select">
        <option value="">Sin barbero</option>
        <option v-for="b in barbers.filter((b) => b.is_active)" :key="b.id" :value="b.id">{{ b.full_name }}</option>
      </select>
    </div>
    <template #footer>
      <button class="btn" @click="assigning = null">Cancelar</button>
      <button class="btn btn--gold" @click="saveAssign">Guardar</button>
    </template>
  </BaseModal>

  <BaseModal v-if="blocking" :title="`Bloquear ${blocking.name}`" @close="blocking = null">
    <p class="muted small">Durante este periodo nadie podrá reservar en esta silla (mantenimiento u otra razón).</p>
    <div class="two">
      <div class="field"><label for="bl-fd">Desde</label><input id="bl-fd" v-model="blockForm.from_date" type="date" class="input" /></div>
      <div class="field"><label for="bl-ft">Hora</label><input id="bl-ft" v-model="blockForm.from_time" type="time" class="input" /></div>
      <div class="field"><label for="bl-td">Hasta</label><input id="bl-td" v-model="blockForm.to_date" type="date" class="input" /></div>
      <div class="field"><label for="bl-tt">Hora</label><input id="bl-tt" v-model="blockForm.to_time" type="time" class="input" /></div>
    </div>
    <div class="field"><label for="bl-r">Motivo</label><input id="bl-r" v-model="blockForm.reason" class="input" maxlength="200" placeholder="Cambio de tapicería" /></div>
    <template #footer>
      <button class="btn" @click="blocking = null">Cancelar</button>
      <button class="btn btn--gold" @click="saveBlock">Bloquear silla</button>
    </template>
  </BaseModal>
</template>

<style scoped>
.cards { display: grid; gap: var(--space-3); grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); }
.card h2 { font-size: var(--step-2); margin: 0; }
.card__top { display: flex; justify-content: space-between; align-items: baseline; gap: var(--space-2); margin-bottom: var(--space-2); }
.card__actions { display: flex; flex-wrap: wrap; gap: 6px; }
.card.off { opacity: .6; }
.on-txt { color: var(--ok); }
.blocks { list-style: none; padding: 0; margin: 0 0 var(--space-3); display: grid; gap: 4px; }
.blocks li { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; color: var(--busy); }
.avail { margin-top: var(--space-7); }
.avail h2 { font-size: var(--step-2); }
.avail__bar { display: flex; flex-wrap: wrap; gap: var(--space-4); }
.avail__bar .field { min-width: 200px; }
.avail__slots { margin-top: var(--space-4); }
.avail__slots h3 { font-size: var(--step-1); }
.two { display: grid; grid-template-columns: 1fr 1fr; gap: 0 var(--space-3); }
</style>
