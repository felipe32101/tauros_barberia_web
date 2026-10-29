<script setup>
import { computed } from 'vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import { chairStatusAt } from '@/composables/useAvailability'
import { fmtTime } from '@/lib/format'

/**
 * Plano de sillas. Cada silla es una "estación" con su espejo.
 * Si se pasa `focusTime`, el estado se calcula para esa hora.
 */
const props = defineProps({
  chairs: { type: Array, required: true },
  modelValue: { type: String, default: null },
  focusTime: { type: String, default: null },
  duration: { type: Number, default: 30 },
  buffer: { type: Number, default: 0 }
})
const emit = defineEmits(['update:modelValue'])

const items = computed(() =>
  props.chairs.map((c) => {
    const status = chairStatusAt(c, props.focusTime, props.duration, props.buffer)
    return { ...c, viewStatus: status, selectable: status === 'disponible' || (!props.focusTime && c.slots?.length > 0) }
  })
)

function caption(c) {
  if (props.focusTime) {
    if (c.viewStatus === 'disponible') return `Libre a las ${fmtTime(props.focusTime)}`
    if (c.viewStatus === 'ocupada') return `Ocupada a las ${fmtTime(props.focusTime)}`
    return c.reason || 'Fuera de horario a esa hora'
  }
  if (c.slots?.length) return `${c.slots.length} ${c.slots.length === 1 ? 'horario libre' : 'horarios libres'}, desde ${fmtTime(c.next_slot)}`
  return c.reason || 'Sin horarios'
}
</script>

<template>
  <div class="floor" role="radiogroup" aria-label="Sillas de la barbería">
    <button
      v-for="c in items"
      :key="c.chair_id"
      class="station"
      :class="[`station--${c.viewStatus}`, { 'is-selected': modelValue === c.chair_id }]"
      role="radio"
      :aria-checked="modelValue === c.chair_id"
      :disabled="!c.selectable"
      @click="emit('update:modelValue', c.chair_id)"
    >
      <svg class="station__mirror" viewBox="0 0 120 70" aria-hidden="true">
        <path d="M10 68V40C10 18 32 4 60 4s50 14 50 36v28" fill="none" stroke="currentColor" stroke-width="3" />
        <path d="M22 68V42c0-15 16-26 38-26s38 11 38 26v26" fill="currentColor" opacity=".08" />
      </svg>
      <span class="station__name">{{ c.chair_name }}</span>
      <span class="station__barber">
        <img v-if="c.barber_photo" :src="c.barber_photo" alt="" class="station__photo" />
        {{ c.barber_name || 'Sin barbero' }}
      </span>
      <StatusBadge :status="c.viewStatus" kind="chair" />
      <span class="station__caption small">{{ caption(c) }}</span>
    </button>
  </div>
</template>

<style scoped>
.floor {
  display: grid; gap: var(--space-3);
  grid-template-columns: repeat(auto-fill, minmax(190px, 1fr));
}
.station {
  position: relative; display: grid; justify-items: start; gap: var(--space-2);
  padding: var(--space-4); text-align: left; cursor: pointer;
  background: linear-gradient(180deg, var(--graphite), var(--carbon));
  border: 1px solid var(--line); border-radius: var(--radius-l) var(--radius-l) var(--radius-m) var(--radius-m);
  color: var(--bone); transition: border-color .15s var(--ease), transform .15s var(--ease);
}
.station:hover:not(:disabled) { border-color: var(--gold); }
.station:disabled { cursor: not-allowed; }
.station__mirror { width: 100%; height: 54px; color: var(--steel); margin-bottom: var(--space-1); }
.station--disponible .station__mirror { color: var(--gold); }
.station--ocupada .station__mirror { color: var(--busy); opacity: .7; }
.station--no_disponible { opacity: .62; }
.station__name { font-family: var(--font-display); font-size: var(--step-2); line-height: 1; }
.station__barber { display: flex; align-items: center; gap: var(--space-2); color: var(--steel); font-size: .925rem; }
.station__photo { width: 24px; height: 24px; border-radius: 50%; object-fit: cover; }
.station__caption { color: var(--steel); }
.station.is-selected {
  border-color: var(--gold); box-shadow: 0 0 0 1px var(--gold), 0 12px 30px rgba(201, 162, 77, .12);
  transform: translateY(-2px);
}
.station.is-selected .station__mirror { color: var(--gold-soft); }
</style>
