<script setup>
import { onMounted, onBeforeUnmount, ref, nextTick } from 'vue'
import { X } from '@lucide/vue'

const props = defineProps({
  title: { type: String, required: true },
  wide: { type: Boolean, default: false }
})
const emit = defineEmits(['close'])
const box = ref(null)
let lastFocus = null

function onKey(e) {
  if (e.key === 'Escape') emit('close')
  if (e.key === 'Tab' && box.value) {
    const f = box.value.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')
    if (!f.length) return
    const first = f[0], last = f[f.length - 1]
    if (e.shiftKey && document.activeElement === first) { last.focus(); e.preventDefault() }
    else if (!e.shiftKey && document.activeElement === last) { first.focus(); e.preventDefault() }
  }
}

onMounted(async () => {
  lastFocus = document.activeElement
  document.addEventListener('keydown', onKey)
  document.body.style.overflow = 'hidden'
  await nextTick()
  const target = box.value?.querySelector('[autofocus], input, select, textarea, button:not(.modal__close)')
  ;(target || box.value)?.focus()
})
onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKey)
  document.body.style.overflow = ''
  lastFocus?.focus?.()
})
</script>

<template>
  <Teleport to="body">
    <div class="modal-backdrop" @mousedown.self="emit('close')">
      <div ref="box" class="modal" :class="{ 'modal--wide': props.wide }" role="dialog" aria-modal="true" :aria-label="title" tabindex="-1">
        <header class="modal__head">
          <h2>{{ title }}</h2>
          <button class="btn btn--ghost btn--icon modal__close" aria-label="Cerrar" @click="emit('close')"><X :size="20" /></button>
        </header>
        <div class="modal__body"><slot /></div>
        <footer v-if="$slots.footer" class="modal__foot"><slot name="footer" /></footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.modal-backdrop {
  position: fixed; inset: 0; z-index: 50; background: rgba(0,0,0,.72);
  display: grid; place-items: center; padding: var(--space-4);
  animation: fade .15s var(--ease);
}
.modal {
  width: min(520px, 100%); max-height: calc(100vh - 32px); display: flex; flex-direction: column;
  background: var(--carbon); border: 1px solid var(--line); border-radius: var(--radius-l);
  box-shadow: 0 24px 60px rgba(0,0,0,.6); animation: rise .2s var(--ease);
}
.modal--wide { width: min(920px, 100%); }
.modal__head { display: flex; align-items: center; justify-content: space-between; gap: var(--space-3); padding: var(--space-4) var(--space-4) 0 var(--space-5); }
.modal__head h2 { font-size: var(--step-2); margin: 0; }
.modal__body { padding: var(--space-4) var(--space-5); overflow-y: auto; }
.modal__foot { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: var(--space-2); padding: var(--space-4) var(--space-5); border-top: 1px solid var(--line); }
@keyframes fade { from { opacity: 0; } }
@keyframes rise { from { opacity: 0; transform: translateY(10px); } }
</style>
