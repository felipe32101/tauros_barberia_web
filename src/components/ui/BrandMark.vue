<script setup>
// Marca provisional de Tauros (cuernos + T). Reemplázala por el logo oficial de Figma:
// basta con poner el SVG/PNG en /public y cambiar este componente.
defineProps({ size: { type: Number, default: 36 }, withName: { type: Boolean, default: true } })
</script>

<template>
  <span class="brand">
    <svg :width="size" :height="size" viewBox="0 0 64 64" aria-hidden="true">
      <circle cx="32" cy="32" r="30" fill="none" stroke="currentColor" stroke-width="1.5" opacity=".55" />
      <path d="M12 17c2.5 10 9 15 20 15s17.5-5 20-15" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" />
      <path d="M22 31.5h20M32 31.5V51" stroke="currentColor" stroke-width="4" stroke-linecap="round" />
    </svg>
    <span v-if="withName" class="brand__name">Tauros<span class="brand__sub">Barbería</span></span>
  </span>
</template>

<style scoped>
.brand { display: inline-flex; align-items: center; gap: var(--space-3); color: var(--gold); }
.brand__name {
  font-family: var(--font-display); font-size: 1.45rem; font-weight: 700; color: var(--bone);
  display: flex; flex-direction: column; line-height: 1;
}
.brand__sub { font-family: var(--font-body); font-size: .68rem; font-weight: 500; color: var(--gold); letter-spacing: .08em; margin-top: 3px; }
</style>
