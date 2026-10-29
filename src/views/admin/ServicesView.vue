<script setup>
import { onMounted, reactive, ref } from 'vue'
import { Plus } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/errors'
import { money, minutesLabel } from '@/lib/format'
import { useUiStore } from '@/stores/ui'
import PageHeader from '@/components/admin/PageHeader.vue'
import BaseModal from '@/components/ui/BaseModal.vue'
import StateBlock from '@/components/ui/StateBlock.vue'

const ui = useUiStore()
const items = ref([])
const state = ref('loading')
const err = ref('')

async function load() {
  const { data, error } = await supabase.from('services').select('*').order('sort_order').order('name')
  if (error) { err.value = errorMessage(error); state.value = 'error'; return }
  items.value = data
  state.value = 'ready'
}
onMounted(load)

const editing = ref(null)
const form = reactive({ name: '', description: '', price: 0, duration_minutes: 30, buffer_minutes: 0, sort_order: 0, is_active: true })
const formError = ref('')
function openForm(s = null) {
  editing.value = s || {}
  Object.assign(form, s
    ? { name: s.name, description: s.description || '', price: Number(s.price), duration_minutes: s.duration_minutes, buffer_minutes: s.buffer_minutes, sort_order: s.sort_order, is_active: s.is_active }
    : { name: '', description: '', price: 0, duration_minutes: 30, buffer_minutes: 5, sort_order: items.value.length + 1, is_active: true })
  formError.value = ''
}
async function save() {
  const payload = {
    name: form.name.trim(), description: form.description.trim() || null,
    price: Math.round(Number(form.price)), duration_minutes: Number(form.duration_minutes),
    buffer_minutes: Number(form.buffer_minutes), sort_order: Number(form.sort_order) || 0,
    is_active: form.is_active, is_sample: false
  }
  if (payload.name.length < 2) { formError.value = 'Escribe el nombre.'; return }
  if (!(payload.price >= 0)) { formError.value = 'El precio no es válido.'; return }
  if (!(payload.duration_minutes >= 5 && payload.duration_minutes <= 480)) { formError.value = 'La duración debe estar entre 5 y 480 minutos.'; return }
  if (!(payload.buffer_minutes >= 0 && payload.buffer_minutes <= 120)) { formError.value = 'La preparación debe estar entre 0 y 120 minutos.'; return }
  const { error } = editing.value.id
    ? await supabase.from('services').update(payload).eq('id', editing.value.id)
    : await supabase.from('services').insert(payload)
  if (error) { formError.value = errorMessage(error); return }
  ui.toast('Servicio guardado. Las citas ya reservadas conservan su precio y duración.')
  editing.value = null
  load()
}
async function toggle(s) {
  const { error } = await supabase.from('services').update({ is_active: !s.is_active }).eq('id', s.id)
  if (error) ui.toast(errorMessage(error), 'error'); else { ui.toast(s.is_active ? 'Servicio oculto para nuevas reservas.' : 'Servicio activado.'); load() }
}
async function remove(s) {
  const ok = await ui.confirm({ title: 'Eliminar servicio', message: `¿Eliminar "${s.name}"? Si ya tiene citas no se podrá borrar; en ese caso desactívalo.`, confirmText: 'Eliminar', danger: true })
  if (!ok) return
  const { error } = await supabase.from('services').delete().eq('id', s.id)
  if (error) ui.toast(errorMessage(error), 'error'); else { ui.toast('Servicio eliminado.'); load() }
}
</script>

<template>
  <PageHeader title="Servicios" subtitle="Precios en pesos colombianos. Cambiar un precio no afecta las citas ya reservadas.">
    <button class="btn btn--gold btn--sm" @click="openForm()"><Plus :size="16" /> Nuevo servicio</button>
  </PageHeader>

  <div v-if="items.some((s) => s.is_sample)" class="alert alert--warn small">
    <p>Hay servicios de ejemplo (marcados). Edítalos con los nombres y precios reales de Tauros o elimínalos.</p>
  </div>

  <StateBlock v-if="state !== 'ready'" :state="state" :message="err" @retry="load" />
  <div v-else class="table-wrap">
    <table class="table">
      <thead><tr><th>Servicio</th><th>Precio</th><th>Duración</th><th>Preparación</th><th>Estado</th><th><span class="sr-only">Acciones</span></th></tr></thead>
      <tbody>
        <tr v-if="!items.length"><td colspan="6" class="muted">Aún no hay servicios.</td></tr>
        <tr v-for="s in items" :key="s.id" :class="{ off: !s.is_active }">
          <td>{{ s.name }} <span v-if="s.is_sample" class="sample small">ejemplo</span><br /><span class="muted small">{{ s.description }}</span></td>
          <td>{{ money(s.price) }}</td>
          <td>{{ minutesLabel(s.duration_minutes) }}</td>
          <td>{{ s.buffer_minutes ? `${s.buffer_minutes} min` : '—' }}</td>
          <td><span :class="s.is_active ? 'on-txt' : 'muted'">{{ s.is_active ? 'Activo' : 'Inactivo' }}</span></td>
          <td class="actions">
            <button class="btn btn--sm" @click="openForm(s)">Editar</button>
            <button class="btn btn--sm" @click="toggle(s)">{{ s.is_active ? 'Desactivar' : 'Activar' }}</button>
            <button class="btn btn--sm btn--danger" @click="remove(s)">Eliminar</button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>

  <BaseModal v-if="editing" :title="editing.id ? 'Editar servicio' : 'Nuevo servicio'" @close="editing = null">
    <form id="svc-form" @submit.prevent="save">
      <div class="field"><label for="s-name">Nombre</label><input id="s-name" v-model="form.name" class="input" maxlength="80" /></div>
      <div class="field"><label for="s-desc">Descripción</label><textarea id="s-desc" v-model="form.description" class="textarea" maxlength="300" /></div>
      <div class="two">
        <div class="field"><label for="s-price">Precio (COP)</label><input id="s-price" v-model="form.price" type="number" min="0" step="500" class="input" /></div>
        <div class="field"><label for="s-dur">Duración (min)</label><input id="s-dur" v-model="form.duration_minutes" type="number" min="5" max="480" step="5" class="input" /></div>
        <div class="field"><label for="s-buf">Preparación después (min)</label><input id="s-buf" v-model="form.buffer_minutes" type="number" min="0" max="120" step="5" class="input" /></div>
        <div class="field"><label for="s-ord">Orden</label><input id="s-ord" v-model="form.sort_order" type="number" min="0" class="input" /></div>
      </div>
      <label class="check"><input v-model="form.is_active" type="checkbox" /> Visible para reservas</label>
      <p v-if="formError" class="field-error">{{ formError }}</p>
    </form>
    <template #footer>
      <button class="btn" @click="editing = null">Cancelar</button>
      <button class="btn btn--gold" type="submit" form="svc-form">Guardar</button>
    </template>
  </BaseModal>
</template>

<style scoped>
.two { display: grid; grid-template-columns: 1fr 1fr; gap: 0 var(--space-3); }
.actions { display: flex; flex-wrap: wrap; gap: 6px; }
.off td { opacity: .6; }
.on-txt { color: var(--ok); }
.sample { color: var(--busy); border: 1px solid currentColor; border-radius: 99px; padding: 0 8px; margin-left: 6px; }
</style>
