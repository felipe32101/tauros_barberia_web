<script setup>
import { ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { LayoutDashboard, CalendarDays, Users, Armchair, Clock, Scissors, Settings, LogOut, Menu, X, ExternalLink } from '@lucide/vue'
import BrandMark from '@/components/ui/BrandMark.vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()
const open = ref(false)
watch(() => route.fullPath, () => { open.value = false })

const links = [
  { to: '/admin', label: 'Resumen', icon: LayoutDashboard, exact: true },
  { to: '/admin/citas', label: 'Citas', icon: CalendarDays },
  { to: '/admin/barberos', label: 'Barberos', icon: Users },
  { to: '/admin/sillas', label: 'Sillas', icon: Armchair },
  { to: '/admin/horarios', label: 'Horarios', icon: Clock },
  { to: '/admin/servicios', label: 'Servicios', icon: Scissors },
  { to: '/admin/ajustes', label: 'Ajustes', icon: Settings }
]

// Si la sesión se cierra o pierde el rol, salimos del panel
watch(() => auth.isAdmin, (v) => { if (auth.ready && !v) router.replace('/admin/login') })

async function logout() {
  await auth.signOut()
  router.replace('/admin/login')
}
</script>

<template>
  <div class="admin">
    <header class="topbar">
      <button class="btn btn--ghost btn--icon" :aria-expanded="open" aria-controls="admin-nav" :aria-label="open ? 'Cerrar menú' : 'Abrir menú'" @click="open = !open">
        <X v-if="open" :size="22" /><Menu v-else :size="22" />
      </button>
      <BrandMark :size="28" />
    </header>

    <aside id="admin-nav" class="sidebar" :class="{ 'is-open': open }">
      <RouterLink to="/admin" class="sidebar__brand"><BrandMark :size="32" /></RouterLink>
      <nav aria-label="Administración">
        <RouterLink v-for="l in links" :key="l.to" :to="l.to" class="sidebar__link"
                    :class="{ 'is-active': l.exact ? route.path === l.to : route.path.startsWith(l.to) }">
          <component :is="l.icon" :size="18" aria-hidden="true" /> {{ l.label }}
        </RouterLink>
      </nav>
      <div class="sidebar__foot">
        <a href="/" target="_blank" rel="noopener" class="sidebar__link small"><ExternalLink :size="16" aria-hidden="true" /> Ver sitio público</a>
        <p class="small muted who">{{ auth.profile?.full_name || auth.user?.email }}</p>
        <button class="btn btn--sm" @click="logout"><LogOut :size="16" /> Cerrar sesión</button>
      </div>
    </aside>

    <main class="content"><RouterView /></main>
  </div>
</template>

<style scoped>
.admin { min-height: 100vh; display: grid; grid-template-columns: 240px 1fr; }
.topbar { display: none; }
.sidebar {
  position: sticky; top: 0; height: 100vh; display: flex; flex-direction: column; gap: var(--space-5);
  padding: var(--space-5) var(--space-4); background: var(--carbon); border-right: 1px solid var(--line); overflow-y: auto;
}
.sidebar__brand { text-decoration: none; padding: 0 var(--space-2); }
.sidebar nav { display: grid; gap: 2px; }
.sidebar__link {
  display: flex; align-items: center; gap: var(--space-3); padding: var(--space-2) var(--space-3);
  border-radius: var(--radius-s); color: var(--bone); text-decoration: none;
}
.sidebar__link:hover { background: var(--graphite); color: var(--gold-soft); }
.sidebar__link.is-active { background: var(--graphite); color: var(--gold); box-shadow: inset 2px 0 0 var(--gold); }
.sidebar__foot { margin-top: auto; display: grid; gap: var(--space-2); }
.who { margin: var(--space-2) var(--space-3) 0; word-break: break-all; }
.content { padding: var(--space-6); min-width: 0; }

@media (max-width: 900px) {
  .admin { grid-template-columns: 1fr; }
  .topbar { display: flex; align-items: center; gap: var(--space-3); padding: var(--space-2) var(--space-4); border-bottom: 1px solid var(--line); position: sticky; top: 0; background: var(--ink); z-index: 20; }
  .sidebar { position: fixed; z-index: 25; top: 57px; left: 0; bottom: 0; height: auto; width: 260px; transform: translateX(-100%); transition: transform .2s var(--ease); }
  .sidebar.is-open { transform: none; box-shadow: 20px 0 40px rgba(0,0,0,.6); }
  .sidebar__brand { display: none; }
  .content { padding: var(--space-5) var(--space-4); }
}
</style>
