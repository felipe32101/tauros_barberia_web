<script setup>
import { computed, ref } from 'vue'
import { api } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/errors'
import { fmtDay, fmtTime, fmtDateTime, money, localDate } from '@/lib/format'
import { useUiStore } from '@/stores/ui'
import BaseModal from '@/components/ui/BaseModal.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import SlotPicker from './SlotPicker.vue'

const props = defineProps({ appointment: { type: Object, required: true } })
const emit = defineEmits(['close', 'changed'])
const ui = useUiStore()

const a = ref({ ...props.appointment })
const busy = ref(false)
const notes = ref(a.value.admin_notes || '')
const rescheduling = ref(false)
const pick = ref(null)

const started = computed(() => new Date(a.value.starts_at).getTime() <= Date.now())
const active = computed(() => ['pendiente', 'confirmada'].includes(a.value.status))

async function setStatus(status, confirmOpts) {
  let reason = null
  if (confirmOpts) {
    const res = await ui.confirm(confirmOpts)
    if (res === false) return
    if (typeof res === 'string') reason = res
  }
  busy.value = true
  try {
    a.value = { ...a.value, ...(await api.rpc('admin_set_appointment_status', { p_id: a.value.id, p_status: status, p_reason: reason })) }
    ui.toast('Estado actualizado.')
    emit('changed')
  } catch (e) { ui.toast(errorMessage(e), 'error') }
  finally { busy.value = false }
}

const cancel = () => setStatus('cancelada', {
  title: 'Cancelar cita', message: `Se cancelará la cita de ${a.value.customer_name} del ${fmtDateTime(a.value.starts_at)} y el horario quedará libre.`,
  confirmText: 'Cancelar cita', cancelText: 'Volver', danger: true, input: true, inputLabel: 'Motivo (opcional, solo interno)'
})

async function saveReschedule() {
  const ok = await ui.confirm({
    title: 'Reprogramar cita',
    message: `La cita pasará al ${fmtDateTime(pick.value.starts_at)}. Avísale al cliente: el sistema todavía no envía notificaciones.`,
    confirmText: 'Reprogramar'
  })
  if (!ok) return
  busy.value = true
  try {
    a.value = { ...a.value, ...(await api.rpc('admin_reschedule_appointment', { p_id: a.value.id, p_chair_id: pick.value.chair_id, p_starts_at: pick.value.starts_at })) }
    rescheduling.value = false
    ui.toast('Cita reprogramada.')
    emit('changed')
  } catch (e) { ui.toast(errorMessage(e), 'error') }
  finally { busy.value = false }
}

async function saveNotes() {
  const { error } = await supabase.from('appointments').update({ admin_notes: notes.value || null }).eq('id', a.value.id)
  if (error) ui.toast(errorMessage(error), 'error')
  else { ui.toast('Nota guardada.'); a.value.admin_notes = notes.value }
}
</script>

<template>
  <BaseModal :title="`Cita ${a.booking_reference}`" :wide="rescheduling" @close="emit('close')">
    <div class="top">
      <div>
        <p class="when cap">{{ fmtDay(localDate(a.starts_at)) }}</p>
        <p class="time">{{ fmtTime(a.starts_at) }} a {{ fmtTime(a.ends_at) }}</p>
      </div>
      <StatusBadge :status="a.status" />
    </div>
    <dl class="dl">
      <div><dt>Cliente</dt><dd>{{ a.customer_name }}<br /><a :href="`tel:${a.customer_phone}`">{{ a.customer_phone }}</a><template v-if="a.customer_email">, {{ a.customer_email }}</template></dd></div>
      <div><dt>Servicio</dt><dd>{{ a.service_name }}, {{ money(a.price) }}</dd></div>
      <div><dt>Silla y barbero</dt><dd>{{ a.chair_name }}, {{ a.barber_name }}</dd></div>
      <div v-if="a.customer_notes"><dt>Nota del cliente</dt><dd>{{ a.customer_notes }}</dd></div>
      <div v-if="a.cancel_reason"><dt>Motivo de cancelación</dt><dd>{{ a.cancel_reason }}</dd></div>
      <div><dt>Creada por</dt><dd>{{ a.created_by === 'admin' ? 'Administración' : 'El cliente en la web' }}, {{ fmtDateTime(a.created_at) }}</dd></div>
    </dl>

    <div class="field">
      <label for="d-notes">Nota interna</label>
      <textarea id="d-notes" v-model="notes" class="textarea" maxlength="1000" />
      <button class="btn btn--sm notes-btn" :disabled="notes === (a.admin_notes || '')" @click="saveNotes">Guardar nota</button>
    </div>

    <section v-if="rescheduling" class="resched">
      <h3>Nueva fecha y hora</h3>
      <SlotPicker :exclude-appointment="a.id" :duration="a.duration_minutes" :initial-date="localDate(a.starts_at)" @change="pick = $event" />
    </section>

    <template #footer>
      <template v-if="rescheduling">
        <button class="btn" @click="rescheduling = false">Volver</button>
        <button class="btn btn--gold" :disabled="busy || !pick" @click="saveReschedule">Guardar nuevo horario</button>
      </template>
      <template v-else>
        <button v-if="a.status === 'pendiente'" class="btn btn--gold" :disabled="busy" @click="setStatus('confirmada')">Confirmar</button>
        <button v-if="a.status === 'confirmada' && started" class="btn btn--gold" :disabled="busy" @click="setStatus('completada')">Marcar completada</button>
        <button v-if="a.status === 'confirmada' && started" class="btn" :disabled="busy"
                @click="setStatus('no_asistio', { title: 'Marcar como no asistió', message: `¿${a.customer_name} no llegó a la cita?`, confirmText: 'Sí, no asistió' })">No asistió</button>
        <button v-if="active" class="btn" :disabled="busy" @click="rescheduling = true">Reprogramar</button>
        <button v-if="active" class="btn btn--danger" :disabled="busy" @click="cancel">Cancelar cita</button>
      </template>
    </template>
  </BaseModal>
</template>

<style scoped>
.top { display: flex; justify-content: space-between; align-items: flex-start; gap: var(--space-3); margin-bottom: var(--space-4); }
.when { font-family: var(--font-display); font-size: var(--step-2); margin: 0; }
.time { margin: 0; color: var(--gold); font-weight: 600; }
.cap::first-letter { text-transform: uppercase; }
.dl { margin: 0 0 var(--space-4); display: grid; gap: var(--space-3); }
.dl div { display: grid; grid-template-columns: 130px 1fr; gap: var(--space-3); }
.dl dt { color: var(--steel); font-size: var(--step--1); }
.dl dd { margin: 0; }
.notes-btn { justify-self: start; }
.resched { border-top: 1px solid var(--line); padding-top: var(--space-4); }
.resched h3 { font-size: var(--step-1); }
</style>
