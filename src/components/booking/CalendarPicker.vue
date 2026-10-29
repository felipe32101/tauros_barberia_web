<script setup>
import { computed, ref, watch } from 'vue'
import { ChevronLeft, ChevronRight } from '@lucide/vue'
import { addDays, isoWeekday, today } from '@/lib/format'

/**
 * Calendario mensual. `summary` es [{ date, slots }] y marca qué días tienen horarios.
 * Sin `summary`, todos los días dentro del rango son seleccionables.
 */
const props = defineProps({
  modelValue: { type: String, default: null },
  maxDaysAhead: { type: Number, default: 30 },
  summary: { type: Array, default: null },
  loading: { type: Boolean, default: false },
  allowPast: { type: Boolean, default: false }
})
const emit = defineEmits(['update:modelValue', 'month'])

const base = today()
const month = ref((props.modelValue || base).slice(0, 7))
const maxDate = computed(() => addDays(base, props.maxDaysAhead))
const slotsByDate = computed(() => Object.fromEntries((props.summary || []).map((d) => [d.date, d.slots])))

const monthLabel = computed(() =>
  new Intl.DateTimeFormat('es-CO', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${month.value}-15T12:00:00Z`))
)

const cells = computed(() => {
  const first = `${month.value}-01`
  const lead = isoWeekday(first) - 1
  const out = []
  for (let i = 0; i < lead; i++) out.push(null)
  let d = first
  while (d.startsWith(month.value)) {
    const outOfRange = (!props.allowPast && d < base) || d > maxDate.value
    const slots = slotsByDate.value[d]
    const noSlots = props.summary && !outOfRange && slots === 0
    out.push({ date: d, day: Number(d.slice(8)), disabled: outOfRange || noSlots, noSlots, isToday: d === base })
    d = addDays(d, 1)
  }
  return out
})

const canPrev = computed(() => props.allowPast || month.value > base.slice(0, 7))
const canNext = computed(() => month.value < maxDate.value.slice(0, 7))

function shift(n) {
  const [y, m] = month.value.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1 + n, 1))
  month.value = dt.toISOString().slice(0, 7)
}

watch(month, (m) => emit('month', m), { immediate: true })
watch(() => props.modelValue, (v) => { if (v && !v.startsWith(month.value)) month.value = v.slice(0, 7) })

function onKey(e, cell) {
  const moves = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }
  if (!moves[e.key]) return
  e.preventDefault()
  const target = addDays(cell.date, moves[e.key])
  if (!target.startsWith(month.value)) shift(moves[e.key] > 0 ? 1 : -1)
  requestAnimationFrame(() => document.querySelector(`[data-date="${target}"]`)?.focus())
}
</script>

<template>
  <div class="cal" :aria-busy="loading">
    <div class="cal__head">
      <button class="btn btn--ghost btn--icon" :disabled="!canPrev" aria-label="Mes anterior" @click="shift(-1)"><ChevronLeft :size="20" /></button>
      <h3 class="cal__title" aria-live="polite">{{ monthLabel }}</h3>
      <button class="btn btn--ghost btn--icon" :disabled="!canNext" aria-label="Mes siguiente" @click="shift(1)"><ChevronRight :size="20" /></button>
    </div>
    <div class="cal__grid" role="grid">
      <span v-for="(w, i) in ['L', 'M', 'M', 'J', 'V', 'S', 'D']" :key="i" class="cal__wd" aria-hidden="true">{{ w }}</span>
      <template v-for="(c, i) in cells" :key="c?.date || `e${i}`">
        <span v-if="!c" />
        <button
          v-else
          class="cal__day"
          :class="{ 'is-selected': c.date === modelValue, 'is-today': c.isToday, 'is-full': c.noSlots }"
          :data-date="c.date"
          :disabled="c.disabled"
          :aria-pressed="c.date === modelValue"
          :aria-label="`${c.day}${c.noSlots ? ', sin horarios' : ''}${c.isToday ? ', hoy' : ''}`"
          @click="emit('update:modelValue', c.date)"
          @keydown="onKey($event, c)"
        >{{ c.day }}</button>
      </template>
    </div>
    <p class="cal__legend small muted">
      <span class="dot dot--sel" /> Seleccionado
      <span class="dot dot--full" /> Sin horarios
      <span v-if="loading" class="loading">Revisando días…</span>
    </p>
  </div>
</template>

<style scoped>
.cal { max-width: 420px; }
.cal__head { display: flex; align-items: center; justify-content: space-between; margin-bottom: var(--space-3); }
.cal__title { margin: 0; font-size: var(--step-1); }
.cal__title::first-letter { text-transform: uppercase; }
.cal__grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 4px; }
.cal__wd { text-align: center; font-size: var(--step--1); color: var(--steel); padding-bottom: 4px; }
.cal__day {
  aspect-ratio: 1; border-radius: var(--radius-s); border: 1px solid var(--line);
  background: var(--carbon); color: var(--bone); cursor: pointer; font-variant-numeric: tabular-nums;
  transition: border-color .12s, background-color .12s;
}
.cal__day:hover:not(:disabled) { border-color: var(--gold); }
.cal__day:disabled { background: transparent; border-color: transparent; color: #4a4a4a; cursor: not-allowed; }
.cal__day.is-full { text-decoration: line-through; color: #6a5a3a; }
.cal__day.is-today { border-color: var(--steel); }
.cal__day.is-selected { background: var(--gold); border-color: var(--gold); color: var(--on-gold); font-weight: 700; }
.cal__legend { display: flex; align-items: center; gap: var(--space-2); flex-wrap: wrap; margin-top: var(--space-3); }
.dot { width: 10px; height: 10px; border-radius: 3px; display: inline-block; }
.dot--sel { background: var(--gold); }
.dot--full { background: #3a3122; margin-left: var(--space-3); }
.loading { margin-left: auto; }
</style>
