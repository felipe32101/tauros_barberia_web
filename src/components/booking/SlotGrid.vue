<script setup>
import { computed } from 'vue'
import { fmtTime, localTime } from '@/lib/format'

const props = defineProps({
  slots: { type: Array, required: true },
  modelValue: { type: String, default: null },
  label: { type: String, default: 'Horarios disponibles' }
})
const emit = defineEmits(['update:modelValue'])

const groups = computed(() => {
  const g = [
    { name: 'Mañana', items: [] },
    { name: 'Tarde', items: [] },
    { name: 'Noche', items: [] }
  ]
  for (const s of props.slots) {
    const h = Number(localTime(s).slice(0, 2))
    g[h < 12 ? 0 : h < 18 ? 1 : 2].items.push(s)
  }
  return g.filter((x) => x.items.length)
})
</script>

<template>
  <div class="slots" role="radiogroup" :aria-label="label">
    <div v-for="g in groups" :key="g.name" class="slots__group">
      <h4 class="slots__title">{{ g.name }}</h4>
      <div class="slots__list">
        <button
          v-for="s in g.items"
          :key="s"
          class="slot"
          :class="{ 'is-selected': modelValue === s }"
          role="radio"
          :aria-checked="modelValue === s"
          @click="emit('update:modelValue', s)"
        >{{ fmtTime(s) }}</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.slots { display: grid; gap: var(--space-4); }
.slots__title { font-family: var(--font-body); font-size: var(--step--1); color: var(--steel); font-weight: 500; margin-bottom: var(--space-2); }
.slots__list { display: flex; flex-wrap: wrap; gap: var(--space-2); }
.slot {
  min-width: 96px; min-height: 42px; padding: 0 var(--space-3);
  border: 1px solid var(--line); border-radius: var(--radius-s); background: var(--carbon);
  color: var(--bone); cursor: pointer; font-variant-numeric: tabular-nums;
  transition: border-color .12s, background-color .12s;
}
.slot:hover { border-color: var(--gold); }
.slot.is-selected { background: var(--gold); border-color: var(--gold); color: var(--on-gold); font-weight: 700; }
</style>
