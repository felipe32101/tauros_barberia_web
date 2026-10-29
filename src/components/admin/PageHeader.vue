<script setup>
defineProps({ title: { type: String, required: true }, subtitle: { type: String, default: '' } })
</script>

<template>
  <header class="ph">
    <div>
      <h1>{{ title }}</h1>
      <p v-if="subtitle" class="muted">{{ subtitle }}</p>
    </div>
    <div class="ph__actions"><slot /></div>
  </header>
</template>

<style scoped>
.ph { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: flex-end; gap: var(--space-4); margin-bottom: var(--space-5); }
.ph h1 { font-size: var(--step-3); margin-bottom: var(--space-1); }
.ph p { margin: 0; }
.ph__actions { display: flex; flex-wrap: wrap; gap: var(--space-2); }
</style>
