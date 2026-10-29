<script setup>
import { Clock } from '@lucide/vue'
import { money, minutesLabel } from '@/lib/format'

defineProps({
  service: { type: Object, required: true },
  selectable: { type: Boolean, default: false },
  selected: { type: Boolean, default: false }
})
defineEmits(['select'])
</script>

<template>
  <component
    :is="selectable ? 'button' : 'article'"
    class="svc"
    :class="{ 'is-selectable': selectable, 'is-selected': selected }"
    :role="selectable ? 'radio' : undefined"
    :aria-checked="selectable ? selected : undefined"
    @click="selectable && $emit('select', service)"
  >
    <div class="svc__top">
      <h3 class="svc__name">{{ service.name }}</h3>
      <span class="svc__price">{{ money(service.price) }}</span>
    </div>
    <p v-if="service.description" class="svc__desc">{{ service.description }}</p>
    <span class="svc__meta small"><Clock :size="14" aria-hidden="true" /> {{ minutesLabel(service.duration_minutes) }}</span>
    <span v-if="service.is_sample" class="svc__sample small">Dato de ejemplo</span>
  </component>
</template>

<style scoped>
.svc {
  display: grid; gap: var(--space-2); align-content: start; text-align: left; width: 100%;
  padding: var(--space-5); background: var(--carbon); color: var(--bone);
  border: 1px solid var(--line); border-radius: var(--radius-m);
}
.svc.is-selectable { cursor: pointer; transition: border-color .15s var(--ease); }
.svc.is-selectable:hover { border-color: var(--gold); }
.svc.is-selected { border-color: var(--gold); box-shadow: inset 0 0 0 1px var(--gold); }
.svc__top { display: flex; justify-content: space-between; align-items: baseline; gap: var(--space-3); }
.svc__name { margin: 0; font-size: var(--step-1); }
.svc__price { color: var(--gold); font-weight: 600; white-space: nowrap; font-variant-numeric: tabular-nums; }
.svc__desc { color: var(--steel); font-size: .925rem; margin: 0; }
.svc__meta { display: inline-flex; align-items: center; gap: 6px; color: var(--steel); }
.svc__sample { color: var(--busy); }
</style>
