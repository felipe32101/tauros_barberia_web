<script setup>
import { X, CircleCheck, TriangleAlert } from '@lucide/vue'
import { useUiStore } from '@/stores/ui'
const ui = useUiStore()
</script>

<template>
  <div class="toasts" role="status" aria-live="polite">
    <TransitionGroup name="toast">
      <div v-for="t in ui.toasts" :key="t.id" class="toast" :class="`toast--${t.type}`">
        <CircleCheck v-if="t.type === 'ok'" :size="18" aria-hidden="true" />
        <TriangleAlert v-else :size="18" aria-hidden="true" />
        <span>{{ t.message }}</span>
        <button class="btn btn--ghost btn--icon" aria-label="Cerrar aviso" @click="ui.dismiss(t.id)"><X :size="16" /></button>
      </div>
    </TransitionGroup>
  </div>
</template>

<style scoped>
.toasts {
  position: fixed; z-index: 60; bottom: var(--space-4); left: 50%; transform: translateX(-50%);
  display: grid; gap: var(--space-2); width: min(440px, calc(100vw - 32px));
}
.toast {
  display: flex; align-items: center; gap: var(--space-3); padding: var(--space-2) var(--space-2) var(--space-2) var(--space-4);
  background: var(--graphite); border: 1px solid var(--line); border-left: 3px solid var(--ok);
  border-radius: var(--radius-s); box-shadow: 0 10px 30px rgba(0,0,0,.5); font-size: .925rem;
}
.toast span { flex: 1; }
.toast--ok svg:first-child { color: var(--ok); }
.toast--error { border-left-color: var(--danger); }
.toast--error svg:first-child { color: var(--danger); }
.toast--warn { border-left-color: var(--busy); }
.toast--warn svg:first-child { color: var(--busy); }
.toast-enter-active, .toast-leave-active { transition: all .22s var(--ease); }
.toast-enter-from, .toast-leave-to { opacity: 0; transform: translateY(8px); }
</style>
