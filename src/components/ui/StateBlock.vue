<script setup>
import { LoaderCircle, TriangleAlert, CalendarX2 } from '@lucide/vue'
// state: loading | empty | error
defineProps({ state: { type: String, required: true }, message: { type: String, default: '' } })
defineEmits(['retry'])
</script>

<template>
  <div class="state" :role="state === 'error' ? 'alert' : 'status'">
    <LoaderCircle v-if="state === 'loading'" class="spin" :size="22" aria-hidden="true" />
    <TriangleAlert v-else-if="state === 'error'" :size="22" class="err" aria-hidden="true" />
    <CalendarX2 v-else :size="22" aria-hidden="true" />
    <p>{{ message || (state === 'loading' ? 'Cargando…' : state === 'error' ? 'Algo salió mal.' : 'No hay nada por aquí.') }}</p>
    <slot />
    <button v-if="state === 'error'" class="btn btn--sm" @click="$emit('retry')">Reintentar</button>
  </div>
</template>

<style scoped>
.state {
  display: grid; justify-items: center; gap: var(--space-2); text-align: center;
  padding: var(--space-6) var(--space-4); color: var(--steel);
  border: 1px dashed var(--line); border-radius: var(--radius-m);
}
.state p { margin: 0; }
.err { color: var(--danger); }
</style>
