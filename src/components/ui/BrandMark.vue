<script setup>
// Marca de Tauros: cachos de toro dorados (silueta, sin rostro).
defineProps({ size: { type: Number, default: 36 }, withName: { type: Boolean, default: true } })
</script>

<template>
  <span class="brand">
    <svg :width="size" :height="size" viewBox="0 0 64 64" aria-hidden="true">
      <defs>
        <linearGradient id="brand-gold" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#F6E3A9" />
          <stop offset=".45" stop-color="#C9A24D" />
          <stop offset="1" stop-color="#8A6A2A" />
        </linearGradient>
      </defs>
      <rect width="64" height="64" rx="12" fill="#000" />
      <g fill="url(#brand-gold)">
        <path d="M33 40 C46 41, 55 34, 59.5 7 C56 25, 47 34, 33 31 Z" />
        <path d="M31 40 C18 41, 9 34, 4.5 7 C8 25, 17 34, 31 31 Z" />
      </g>
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
