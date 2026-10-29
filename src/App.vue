<script setup>
import { onMounted } from 'vue'
import { useUiStore } from '@/stores/ui'
import { isConfigured } from '@/lib/supabase'
import ToastHost from '@/components/ui/ToastHost.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'

const ui = useUiStore()
onMounted(() => ui.loadInfo())
</script>

<template>
  <div v-if="!isConfigured" class="config-warning" role="alert">
    Falta configurar Supabase: copia <code>.env.example</code> a <code>.env</code> y pon tus claves.
  </div>
  <RouterView />
  <ToastHost />
  <ConfirmDialog />
</template>

<style scoped>
.config-warning {
  background: var(--gold); color: var(--on-gold); padding: var(--space-2) var(--space-4);
  font-size: var(--step--1); font-weight: 600; text-align: center;
}
</style>
