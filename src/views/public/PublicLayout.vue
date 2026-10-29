<script setup>
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Menu, X } from '@lucide/vue'
import BrandMark from '@/components/ui/BrandMark.vue'
import { useAuthStore } from '@/stores/auth'
import { useUiStore } from '@/stores/ui'
import { WEEKDAYS } from '@/lib/format'

const auth = useAuthStore()
const ui = useUiStore()
const route = useRoute()
const open = ref(false)
watch(() => route.fullPath, () => { open.value = false })

const hhmm = (t) => (t ? t.slice(0, 5) : '')
</script>

<template>
  <a href="#main" class="skip">Saltar al contenido</a>
  <header class="header">
    <div class="container header__row">
      <RouterLink to="/" class="header__brand" aria-label="Tauros Barbería, inicio"><BrandMark /></RouterLink>

      <button class="btn btn--ghost btn--icon header__toggle" :aria-expanded="open" aria-controls="main-nav" :aria-label="open ? 'Cerrar menú' : 'Abrir menú'" @click="open = !open">
        <X v-if="open" :size="22" /><Menu v-else :size="22" />
      </button>

      <nav id="main-nav" class="nav" :class="{ 'is-open': open }" aria-label="Principal">
        <RouterLink to="/#servicios" class="nav__link">Servicios</RouterLink>
        <RouterLink to="/#como-reservar" class="nav__link">Cómo reservar</RouterLink>
        <RouterLink v-if="auth.isLoggedIn" to="/mis-citas" class="nav__link">Mis citas</RouterLink>
        <RouterLink v-else to="/cita" class="nav__link">Consultar mi cita</RouterLink>
        <RouterLink v-if="auth.isAdmin" to="/admin" class="nav__link">Administración</RouterLink>
        <RouterLink v-if="!auth.isLoggedIn" to="/ingresar" class="nav__link">Ingresar</RouterLink>
        <RouterLink to="/reservar" class="btn btn--gold nav__cta">Agendar cita</RouterLink>
      </nav>
    </div>
  </header>

  <main id="main"><RouterView /></main>

  <footer class="footer">
    <div class="container footer__grid">
      <div>
        <BrandMark :size="30" />
        <p class="muted small footer__note">Reserva en línea las 24 horas. Para cambios de último momento comunícate directamente con la barbería.</p>
      </div>
      <div v-if="ui.info?.hours?.length">
        <h3 class="footer__title">Horario</h3>
        <ul class="hours">
          <li v-for="h in ui.info.hours" :key="h.weekday">
            <span>{{ WEEKDAYS[h.weekday - 1] }}</span>
            <span class="muted">{{ h.is_closed ? 'Cerrado' : `${hhmm(h.opens_at)} – ${hhmm(h.closes_at)}` }}</span>
          </li>
        </ul>
      </div>
      <div>
        <h3 class="footer__title">Tu cita</h3>
        <p class="small"><RouterLink to="/reservar">Agendar una cita</RouterLink></p>
        <p class="small"><RouterLink to="/cita">Consultar, cambiar o cancelar</RouterLink></p>
      </div>
    </div>
    <div class="container footer__bottom small muted">© {{ new Date().getFullYear() }} Tauros Barbería</div>
  </footer>
</template>

<style scoped>
.skip { position: absolute; left: -9999px; top: 0; background: var(--gold); color: var(--on-gold); padding: var(--space-2) var(--space-4); z-index: 100; }
.skip:focus { left: var(--space-4); }

.header { position: sticky; top: 0; z-index: 30; background: rgba(0, 0, 0, .88); backdrop-filter: blur(10px); border-bottom: 1px solid var(--line); }
.header__row { display: flex; align-items: center; justify-content: space-between; min-height: 72px; gap: var(--space-4); }
.header__brand { text-decoration: none; }
.header__toggle { display: none; }

.nav { display: flex; align-items: center; gap: var(--space-5); }
.nav__link { color: var(--bone); text-decoration: none; font-size: .95rem; padding: var(--space-2) 0; border-bottom: 1px solid transparent; }
.nav__link:hover, .nav__link.router-link-exact-active { color: var(--gold-soft); border-bottom-color: var(--gold); }

@media (max-width: 860px) {
  .header__toggle { display: inline-flex; }
  .nav {
    position: absolute; top: 72px; left: 0; right: 0; display: none; flex-direction: column; align-items: stretch;
    gap: 0; padding: var(--space-2) var(--space-4) var(--space-5); background: var(--ink); border-bottom: 1px solid var(--line);
  }
  .nav.is-open { display: flex; }
  .nav__link { padding: var(--space-3) 0; border-bottom: 1px solid var(--line); }
  .nav__cta { margin-top: var(--space-4); }
}

.footer { border-top: 1px solid var(--line); margin-top: var(--space-8); padding-top: var(--space-7); background: var(--carbon); }
.footer__grid { display: grid; gap: var(--space-6); grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); }
.footer__note { margin-top: var(--space-4); max-width: 34ch; }
.footer__title { font-size: var(--step-1); }
.hours { list-style: none; margin: 0; padding: 0; font-size: .925rem; }
.hours li { display: flex; justify-content: space-between; gap: var(--space-4); padding: 4px 0; border-bottom: 1px solid var(--line); max-width: 300px; }
.footer__bottom { padding-block: var(--space-5); margin-top: var(--space-6); border-top: 1px solid var(--line); }
</style>
