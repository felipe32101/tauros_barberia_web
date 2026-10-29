<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute } from 'vue-router'
import { Plus } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { api } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { today, fmtDateTime, money } from '@/lib/format'
import { useUiStore } from '@/stores/ui'
import PageHeader from '@/components/admin/PageHeader.vue'
import BaseModal from '@/components/ui/BaseModal.vue'
import StateBlock from '@/components/ui/StateBlock.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'

const ui = useUiStore()
const route = useRoute()

const barbers = ref([])
const chairs = ref([])
const assignments = ref([])
const state = ref('loading')
const err = ref('')

async function load() {
  try {
    const t = today()
    const [b, c, a] = await Promise.all([
      supabase.from('barbers').select('*').order('is_active', { ascending: false }).order('full_name'),
      supabase.from('chairs').select('id, name, is_active').order('sort_order').order('name'),
      supabase.from('barber_chair_assignments').select('id, barber_id, chair_id, valid_from, valid_until')
        .or(`valid_until.is.null,valid_until.gt.${t}`)
    ])
    for (const r of [b, c, a]) if (r.error) throw r.error
    barbers.value = b.data
    chairs.value = c.data
    assignments.value = a.data
    state.value = 'ready'
  } catch (e) { err.value = errorMessage(e); state.value = 'error' }
}
onMounted(() => { load(); if (route.query.nuevo) openForm() })

const t = today()
function currentChair(barberId) {
  const a = assignments.value.find((x) => x.barber_id === barberId && x.valid_from <= t)
  return a ? chairs.value.find((c) => c.id === a.chair_id) : null
}
function upcomingAssignment(barberId) {
  return assignments.value.find((x) => x.barber_id === barberId && x.valid_from > t)
}

// ---------- Crear / editar ----------
const editing = ref(null)
const form = reactive({ full_name: '', phone: '', email: '', photo_url: '' })
const formError = ref('')
function openForm(b = null) {
  editing.value = b || {}
  Object.assign(form, { full_name: b?.full_name || '', phone: b?.phone || '', email: b?.email || '', photo_url: b?.photo_url || '' })
  formError.value = ''
}
async function saveForm() {
  formError.value = ''
  const payload = {
    full_name: form.full_name.trim(),
    phone: form.phone.replace(/[^0-9+]/g, '') || null,
    email: form.email.trim().toLowerCase() || null,
    photo_url: form.photo_url.trim() || null
  }
  if (payload.full_name.length < 2) { formError.value = 'Escribe el nombre.'; return }
  if (payload.phone && !/^\+?[0-9]{7,15}$/.test(payload.phone)) { formError.value = 'El teléfono debe tener entre 7 y 15 dígitos.'; return }
  if (payload.photo_url && !/^https:\/\//.test(payload.photo_url)) { formError.value = 'La foto debe ser un enlace https.'; return }
  const q = editing.value.id
    ? supabase.from('barbers').update(payload).eq('id', editing.value.id)
    : supabase.from('barbers').insert(payload)
  const { error } = await q
  if (error) { formError.value = errorMessage(error); return }
  ui.toast(editing.value.id ? 'Barbero actualizado.' : 'Barbero registrado. Ahora asígnale una silla y un horario.')
  editing.value = null
  load()
}

// ---------- Activar / desactivar ----------
async function toggleActive(b) {
  try {
    const res = await ui.withConflicts(
      (confirm) => api.rpc('admin_set_barber_active', { p_id: b.id, p_active: !b.is_active, p_confirm: confirm }),
      `Desactivar a ${b.full_name}`
    )
    if (res?.saved) { ui.toast(b.is_active ? 'Barbero desactivado.' : 'Barbero activado.'); load() }
  } catch (e) { ui.toast(errorMessage(e), 'error') }
}

// ---------- Asignar silla ----------
const assigning = ref(null)
const assignForm = reactive({ chair_id: '', valid_from: today() })
function openAssign(b) {
  assigning.value = b
  assignForm.chair_id = currentChair(b.id)?.id || ''
  assignForm.valid_from = today()
}
const chairOwner = computed(() => {
  if (!assignForm.chair_id) return null
  const a = assignments.value.find((x) => x.chair_id === assignForm.chair_id && x.barber_id !== assigning.value?.id)
  return a ? barbers.value.find((b) => b.id === a.barber_id) : null
})
async function saveAssign() {
  try {
    const res = await ui.withConflicts(
      (confirm) => api.rpc('admin_assign_barber', {
        p_barber_id: assigning.value.id, p_chair_id: assignForm.chair_id || null, p_valid_from: assignForm.valid_from, p_confirm: confirm
      }),
      'Cambiar la silla'
    )
    if (res?.saved) { ui.toast('Asignación guardada.'); assigning.value = null; load() }
  } catch (e) { ui.toast(errorMessage(e), 'error') }
}

// ---------- Citas del barbero ----------
const history = ref(null)
async function openHistory(b) {
  history.value = { barber: b, items: null }
  const { data, error } = await supabase.from('appointments')
    .select('id, booking_reference, starts_at, status, service_name_snapshot, service_price_snapshot, customers(full_name), chairs(name)')
    .eq('barber_id', b.id).order('starts_at', { ascending: false }).limit(100)
  if (error) { ui.toast(errorMessage(error), 'error'); history.value = null; return }
  history.value.items = data
}
const now = Date.now()
</script>

<template>
  <PageHeader title="Barberos" subtitle="Los barberos con citas no se borran: se desactivan para conservar el historial.">
    <button class="btn btn--gold btn--sm" @click="openForm()"><Plus :size="16" /> Registrar barbero</button>
  </PageHeader>

  <StateBlock v-if="state !== 'ready'" :state="state" :message="err" @retry="load" />
  <StateBlock v-else-if="!barbers.length" state="empty" message="Todavía no hay barberos registrados.">
    <button class="btn btn--gold btn--sm" @click="openForm()">Registrar el primero</button>
  </StateBlock>
  <div v-else class="table-wrap">
    <table class="table">
      <thead><tr><th>Barbero</th><th>Contacto</th><th>Silla</th><th>Estado</th><th>Registrado</th><th><span class="sr-only">Acciones</span></th></tr></thead>
      <tbody>
        <tr v-for="b in barbers" :key="b.id" :class="{ off: !b.is_active }">
          <td>
            <div class="who">
              <img v-if="b.photo_url" :src="b.photo_url" alt="" class="avatar" />
              <span v-else class="avatar avatar--empty" aria-hidden="true">{{ b.full_name.charAt(0) }}</span>
              {{ b.full_name }}
            </div>
          </td>
          <td class="small">{{ b.phone || '—' }}<br /><span class="muted">{{ b.email || '' }}</span></td>
          <td>
            {{ currentChair(b.id)?.name || 'Sin silla' }}
            <span v-if="upcomingAssignment(b.id)" class="muted small"><br />Cambia el {{ upcomingAssignment(b.id).valid_from }}</span>
          </td>
          <td><span :class="b.is_active ? 'on-txt' : 'muted'">{{ b.is_active ? 'Activo' : 'Inactivo' }}</span></td>
          <td class="small muted">{{ new Date(b.created_at).toLocaleDateString('es-CO') }}</td>
          <td class="actions">
            <button class="btn btn--sm" @click="openForm(b)">Editar</button>
            <button class="btn btn--sm" @click="openAssign(b)">Silla</button>
            <RouterLink class="btn btn--sm" :to="`/admin/horarios?barbero=${b.id}`">Horario</RouterLink>
            <button class="btn btn--sm" @click="openHistory(b)">Citas</button>
            <button class="btn btn--sm" :class="b.is_active ? 'btn--danger' : ''" @click="toggleActive(b)">{{ b.is_active ? 'Desactivar' : 'Activar' }}</button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>

  <BaseModal v-if="editing" :title="editing.id ? 'Editar barbero' : 'Registrar barbero'" @close="editing = null">
    <form id="barber-form" @submit.prevent="saveForm">
      <div class="field"><label for="b-name">Nombre completo</label><input id="b-name" v-model="form.full_name" class="input" maxlength="100" /></div>
      <div class="field"><label for="b-phone">Teléfono (opcional)</label><input id="b-phone" v-model="form.phone" class="input" type="tel" maxlength="20" /></div>
      <div class="field"><label for="b-email">Correo (opcional)</label><input id="b-email" v-model="form.email" class="input" type="email" maxlength="160" /></div>
      <div class="field"><label for="b-photo">Enlace de la foto (opcional)</label><input id="b-photo" v-model="form.photo_url" class="input" placeholder="https://…" /></div>
      <p v-if="formError" class="field-error" role="alert">{{ formError }}</p>
    </form>
    <template #footer>
      <button class="btn" @click="editing = null">Cancelar</button>
      <button class="btn btn--gold" type="submit" form="barber-form">Guardar</button>
    </template>
  </BaseModal>

  <BaseModal v-if="assigning" :title="`Silla de ${assigning.full_name}`" @close="assigning = null">
    <p class="muted small">Cada barbero tiene una silla principal a la vez. Si la silla ya tiene barbero, él quedará sin silla desde esa fecha.</p>
    <div class="field">
      <label for="as-chair">Silla</label>
      <select id="as-chair" v-model="assignForm.chair_id" class="select">
        <option value="">Sin silla</option>
        <option v-for="c in chairs.filter((c) => c.is_active)" :key="c.id" :value="c.id">{{ c.name }}</option>
      </select>
    </div>
    <p v-if="chairOwner" class="alert alert--warn small">Esta silla ahora es de {{ chairOwner.full_name }}.</p>
    <div class="field"><label for="as-from">Desde</label><input id="as-from" v-model="assignForm.valid_from" type="date" class="input" :min="today()" /></div>
    <template #footer>
      <button class="btn" @click="assigning = null">Cancelar</button>
      <button class="btn btn--gold" @click="saveAssign">Guardar asignación</button>
    </template>
  </BaseModal>

  <BaseModal v-if="history" :title="`Citas de ${history.barber.full_name}`" wide @close="history = null">
    <StateBlock v-if="!history.items" state="loading" />
    <StateBlock v-else-if="!history.items.length" state="empty" message="Este barbero no tiene citas." />
    <div v-else class="table-wrap">
      <table class="table">
        <thead><tr><th>Fecha</th><th>Cliente</th><th>Servicio</th><th>Silla</th><th>Estado</th></tr></thead>
        <tbody>
          <tr v-for="a in history.items" :key="a.id" :class="{ future: new Date(a.starts_at).getTime() > now }">
            <td>{{ fmtDateTime(a.starts_at) }}</td>
            <td>{{ a.customers?.full_name }}</td>
            <td>{{ a.service_name_snapshot }} <span class="muted small">{{ money(a.service_price_snapshot) }}</span></td>
            <td>{{ a.chairs?.name }}</td>
            <td><StatusBadge :status="a.status" /></td>
          </tr>
        </tbody>
      </table>
    </div>
  </BaseModal>
</template>

<style scoped>
.who { display: flex; align-items: center; gap: var(--space-3); }
.avatar { width: 34px; height: 34px; border-radius: 50%; object-fit: cover; flex-shrink: 0; }
.avatar--empty { display: grid; place-items: center; background: var(--graphite); color: var(--gold); font-family: var(--font-display); }
.actions { display: flex; flex-wrap: wrap; gap: 6px; }
.off td { opacity: .6; }
.on-txt { color: var(--ok); }
.future td:first-child { color: var(--gold); }
</style>
