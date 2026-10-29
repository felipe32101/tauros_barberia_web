<script setup>
import { onMounted, reactive, ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/errors'
import { useUiStore } from '@/stores/ui'
import PageHeader from '@/components/admin/PageHeader.vue'
import StateBlock from '@/components/ui/StateBlock.vue'

const ui = useUiStore()
const s = reactive({})
const state = ref('loading')
const saving = ref(false)

onMounted(async () => {
  const { data, error } = await supabase.from('business_settings').select('*').eq('id', 1).maybeSingle()
  if (error || !data) { state.value = 'error'; return }
  Object.assign(s, data)
  state.value = 'ready'
})

async function save() {
  saving.value = true
  const { id, updated_at, ...payload } = s
  for (const k of ['slot_interval_minutes', 'min_advance_minutes', 'max_days_ahead', 'pending_hold_minutes', 'cancel_min_hours', 'max_active_bookings_per_phone']) payload[k] = Number(payload[k])
  const { error } = await supabase.from('business_settings').update(payload).eq('id', 1)
  saving.value = false
  if (error) ui.toast(errorMessage(error, 'Revisa los valores: alguno está fuera del rango permitido.'), 'error')
  else { ui.toast('Ajustes guardados.'); ui.info = null; ui.loadInfo() }
}
</script>

<template>
  <PageHeader title="Ajustes de reservas" subtitle="Reglas que aplica el sistema al calcular los horarios disponibles." />
  <StateBlock v-if="state !== 'ready'" :state="state" />
  <form v-else class="panel form" @submit.prevent="save">
    <div class="grid">
      <div class="field"><label for="st-name">Nombre del negocio</label><input id="st-name" v-model="s.business_name" class="input" /></div>
      <div class="field"><label for="st-tz">Zona horaria</label><input id="st-tz" v-model="s.timezone" class="input" /><span class="small muted">Para Colombia: America/Bogota</span></div>
      <div class="field">
        <label for="st-int">Intervalo entre horarios</label>
        <select id="st-int" v-model.number="s.slot_interval_minutes" class="select">
          <option v-for="n in [10, 15, 20, 30, 45, 60]" :key="n" :value="n">Cada {{ n }} minutos</option>
        </select>
      </div>
      <div class="field"><label for="st-adv">Anticipación mínima (minutos)</label><input id="st-adv" v-model="s.min_advance_minutes" type="number" min="0" class="input" /><span class="small muted">No se puede reservar con menos tiempo que esto.</span></div>
      <div class="field"><label for="st-max">Días hacia adelante</label><input id="st-max" v-model="s.max_days_ahead" type="number" min="1" max="365" class="input" /></div>
      <div class="field"><label for="st-cancel">Horas mínimas para cancelar o cambiar en línea</label><input id="st-cancel" v-model="s.cancel_min_hours" type="number" min="0" max="168" class="input" /></div>
      <div class="field"><label for="st-phone">Citas activas máximas por teléfono</label><input id="st-phone" v-model="s.max_active_bookings_per_phone" type="number" min="1" max="20" class="input" /></div>
    </div>
    <fieldset class="fs">
      <legend>Confirmación de reservas web</legend>
      <label class="check"><input v-model="s.auto_confirm" type="checkbox" /> Confirmar automáticamente</label>
      <p class="small muted">Si lo desactivas, las reservas llegan como pendientes y apartan el horario mientras las confirmas.</p>
      <div v-if="!s.auto_confirm" class="field hold">
        <label for="st-hold">Minutos que una reserva pendiente aparta el horario (0 = sin límite)</label>
        <input id="st-hold" v-model="s.pending_hold_minutes" type="number" min="0" class="input" />
      </div>
    </fieldset>
    <button class="btn btn--gold" :disabled="saving">{{ saving ? 'Guardando…' : 'Guardar ajustes' }}</button>
  </form>
</template>

<style scoped>
.form { max-width: 860px; }
.grid { display: grid; gap: 0 var(--space-4); grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); }
.fs { border: 1px solid var(--line); border-radius: var(--radius-m); padding: var(--space-4); margin: var(--space-2) 0 var(--space-5); }
.fs legend { padding: 0 var(--space-2); color: var(--steel); font-size: var(--step--1); }
.hold { max-width: 420px; margin-top: var(--space-3); }
</style>
