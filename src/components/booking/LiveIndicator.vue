<script setup>
import { Wifi, WifiOff, LoaderCircle } from '@lucide/vue'
defineProps({ live: { type: String, required: true } })
</script>

<template>
  <span class="live small" :class="`live--${live}`">
    <Wifi v-if="live === 'live'" :size="14" aria-hidden="true" />
    <WifiOff v-else-if="live === 'offline'" :size="14" aria-hidden="true" />
    <LoaderCircle v-else :size="14" class="spin" aria-hidden="true" />
    {{ live === 'live' ? 'Disponibilidad en tiempo real' : live === 'offline' ? 'Sin conexión en vivo, actualizamos cada minuto' : 'Conectando…' }}
  </span>
</template>

<style scoped>
.live { display: inline-flex; align-items: center; gap: 6px; color: var(--steel); }
.live--live svg { color: var(--ok); }
.live--offline svg { color: var(--busy); }
</style>
