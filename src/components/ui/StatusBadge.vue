<script setup>
import { computed } from 'vue'
import { CircleCheck, CircleX, Clock3, Ban, Check, UserX } from '@lucide/vue'
import { STATUS_LABELS } from '@/lib/format'

// kind="chair": disponible | ocupada | no_disponible
// kind="appointment": pendiente | confirmada | completada | cancelada | no_asistio
const props = defineProps({ status: { type: String, required: true }, kind: { type: String, default: 'appointment' } })

const MAP = {
  chair: {
    disponible: { label: 'Disponible', icon: CircleCheck, tone: 'ok' },
    ocupada: { label: 'Ocupada', icon: Clock3, tone: 'busy' },
    no_disponible: { label: 'No disponible', icon: Ban, tone: 'off' }
  },
  appointment: {
    pendiente: { icon: Clock3, tone: 'busy' },
    confirmada: { icon: CircleCheck, tone: 'ok' },
    completada: { icon: Check, tone: 'gold' },
    cancelada: { icon: CircleX, tone: 'off' },
    no_asistio: { icon: UserX, tone: 'danger' }
  }
}

const info = computed(() => {
  const m = MAP[props.kind][props.status] || { icon: Clock3, tone: 'off' }
  return { ...m, label: m.label || STATUS_LABELS[props.status] || props.status }
})
</script>

<template>
  <span class="badge" :class="`badge--${info.tone}`">
    <component :is="info.icon" :size="14" aria-hidden="true" />
    {{ info.label }}
  </span>
</template>

<style scoped>
.badge {
  display: inline-flex; align-items: center; gap: 5px; white-space: nowrap;
  padding: 2px 10px 2px 8px; border-radius: 999px; font-size: var(--step--1); font-weight: 600;
  border: 1px solid currentColor;
}
.badge--ok { color: var(--ok); }
.badge--busy { color: var(--busy); }
.badge--off { color: var(--off); }
.badge--gold { color: var(--gold); }
.badge--danger { color: var(--danger); }
</style>
