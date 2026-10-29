<script setup>
// Selector de silla + hora para el admin (crear o reprogramar). No aplica la
// anticipación mínima ni el límite de días, pero sí todas las demás reglas.
import { computed, ref, watch } from 'vue'
import { api } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { useAvailability } from '@/composables/useAvailability'
import ChairFloor from '@/components/booking/ChairFloor.vue'
import SlotGrid from '@/components/booking/SlotGrid.vue'
import StateBlock from '@/components/ui/StateBlock.vue'

const props = defineProps({
  serviceId: { type: String, default: null },
  excludeAppointment: { type: String, default: null },
  duration: { type: Number, default: 30 },
  initialDate: { type: String, required: true }
})
const emit = defineEmits(['change'])

const date = ref(props.initialDate)
const chairId = ref(null)
const slot = ref(null)
const enabled = computed(() => Boolean(props.serviceId || props.excludeAppointment))

const { status, data, error, reload, changed } = useAvailability(date, (d) =>
  api.rpc('admin_availability', { p_date: d, p_service_id: props.serviceId, p_exclude_appointment: props.excludeAppointment }),
  { enabled })

watch(() => props.serviceId, () => { chairId.value = null; slot.value = null; reload() })
watch(date, () => { chairId.value = null; slot.value = null })
const chair = computed(() => data.value?.chairs?.find((c) => c.chair_id === chairId.value))
watch(changed, () => { if (slot.value && !chair.value?.slots.includes(slot.value)) slot.value = null })
watch([chairId, slot], () => emit('change', chairId.value && slot.value ? { chair_id: chairId.value, starts_at: slot.value } : null))
</script>

<template>
  <div class="sp">
    <div class="field date">
      <label for="sp-date">Fecha</label>
      <input id="sp-date" v-model="date" type="date" class="input" />
    </div>
    <StateBlock v-if="!enabled" state="empty" message="Elige primero el servicio." />
    <StateBlock v-else-if="status === 'loading'" state="loading" message="Consultando disponibilidad…" />
    <StateBlock v-else-if="status === 'error'" state="error" :message="errorMessage(error)" @retry="reload()" />
    <template v-else-if="data">
      <StateBlock v-if="status === 'empty'" state="empty" message="Ese día no hay horarios libres." />
      <ChairFloor v-model="chairId" :chairs="data.chairs" :duration="duration" @update:model-value="slot = null" />
      <div v-if="chair" class="sp__slots">
        <h3>Horas libres en {{ chair.chair_name }}</h3>
        <SlotGrid v-model="slot" :slots="chair.slots" />
      </div>
    </template>
  </div>
</template>

<style scoped>
.date { max-width: 220px; }
.sp__slots { margin-top: var(--space-4); }
.sp__slots h3 { font-size: var(--step-0); font-family: var(--font-body); font-weight: 600; }
</style>
