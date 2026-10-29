<script setup>
import { ref, watch } from 'vue'
import { useUiStore } from '@/stores/ui'
import { fmtDateTime } from '@/lib/format'
import BaseModal from './BaseModal.vue'

const ui = useUiStore()
const text = ref('')
watch(() => ui.dialog, () => { text.value = '' })

function accept() {
  ui.closeDialog(ui.dialog?.input ? text.value : true)
}
</script>

<template>
  <BaseModal v-if="ui.dialog" :title="ui.dialog.title" @close="ui.closeDialog(false)">
    <p>{{ ui.dialog.message }}</p>
    <ul v-if="ui.dialog.items?.length" class="items">
      <li v-for="c in ui.dialog.items" :key="c.id">
        <strong>{{ c.booking_reference }}</strong> · {{ fmtDateTime(c.starts_at) }}<br />
        <span class="muted small">{{ c.customer_name }} con {{ c.barber_name }} en {{ c.chair_name }}. {{ c.issue }}.</span>
      </li>
    </ul>
    <div v-if="ui.dialog.input" class="field">
      <label for="dialog-input">{{ ui.dialog.inputLabel || 'Motivo (opcional)' }}</label>
      <input id="dialog-input" v-model="text" class="input" maxlength="200" />
    </div>
    <template #footer>
      <button class="btn" @click="ui.closeDialog(false)">{{ ui.dialog.cancelText }}</button>
      <button class="btn" :class="ui.dialog.danger ? 'btn--danger' : 'btn--gold'" @click="accept">{{ ui.dialog.confirmText }}</button>
    </template>
  </BaseModal>
</template>

<style scoped>
.items { list-style: none; padding: 0; margin: 0 0 var(--space-4); display: grid; gap: var(--space-2); max-height: 260px; overflow-y: auto; }
.items li { padding: var(--space-2) var(--space-3); background: var(--graphite); border-radius: var(--radius-s); font-size: .925rem; }
</style>
