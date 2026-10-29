<script setup>
import { computed, onMounted, ref } from 'vue'
import { api } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { fmtDateTime, money } from '@/lib/format'
import { useAuthStore } from '@/stores/auth'
import { useUiStore } from '@/stores/ui'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import StateBlock from '@/components/ui/StateBlock.vue'

const auth = useAuthStore()
const ui = useUiStore()
const items = ref([])
const state = ref('loading')
const err = ref('')

async function load() {
  if (!auth.isLoggedIn) { state.value = 'guest'; return }
  state.value = 'loading'
  try {
    items.value = await api.myAppointments()
    state.value = 'ready'
  } catch (e) { err.value = errorMessage(e); state.value = 'error' }
}
onMounted(async () => { await auth.init(); load() })

const now = Date.now()
const upcoming = computed(() => items.value.filter((a) => new Date(a.starts_at).getTime() >= now && ['pendiente', 'confirmada'].includes(a.status)).reverse())
const past = computed(() => items.value.filter((a) => !upcoming.value.includes(a)))

async function cancel(a) {
  const ok = await ui.confirm({
    title: 'Cancelar cita', message: `¿Cancelar tu cita del ${fmtDateTime(a.starts_at)}?`,
    confirmText: 'Sí, cancelar', cancelText: 'No', danger: true
  })
  if (!ok) return
  try { await api.cancelMine(a.id); ui.toast('Cita cancelada.'); load() }
  catch (e) { ui.toast(errorMessage(e), 'error') }
}

async function logout() { await auth.signOut(); state.value = 'guest' }
</script>

<template>
  <div class="container page">
    <div class="head">
      <h1>Mis citas</h1>
      <button v-if="auth.isLoggedIn" class="btn btn--sm" @click="logout">Cerrar sesión</button>
    </div>

    <StateBlock v-if="state === 'guest'" state="empty" message="Ingresa para ver las citas que reservaste con tu cuenta.">
      <RouterLink to="/ingresar?next=/mis-citas" class="btn btn--gold btn--sm">Ingresar</RouterLink>
      <RouterLink to="/cita" class="small">Reservé sin cuenta</RouterLink>
    </StateBlock>
    <StateBlock v-else-if="state !== 'ready'" :state="state" :message="err" @retry="load" />

    <template v-else>
      <section>
        <h2>Próximas</h2>
        <StateBlock v-if="!upcoming.length" state="empty" message="No tienes citas próximas.">
          <RouterLink to="/reservar" class="btn btn--gold btn--sm">Agendar cita</RouterLink>
        </StateBlock>
        <ul v-else class="list">
          <li v-for="a in upcoming" :key="a.id" class="item panel">
            <div>
              <strong>{{ fmtDateTime(a.starts_at) }}</strong>
              <p class="muted small">{{ a.service_name }} ({{ money(a.price) }}) en {{ a.chair_name }} con {{ a.barber_name }}. Reserva {{ a.booking_reference }}.</p>
            </div>
            <StatusBadge :status="a.status" />
            <button v-if="a.can_modify" class="btn btn--danger btn--sm" @click="cancel(a)">Cancelar</button>
          </li>
        </ul>
      </section>
      <section v-if="past.length" class="past">
        <h2>Historial</h2>
        <ul class="list">
          <li v-for="a in past" :key="a.id" class="item panel">
            <div>
              <strong>{{ fmtDateTime(a.starts_at) }}</strong>
              <p class="muted small">{{ a.service_name }} con {{ a.barber_name }}</p>
            </div>
            <StatusBadge :status="a.status" />
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

<style scoped>
.page { padding-top: var(--space-6); max-width: 860px; }
.head { display: flex; justify-content: space-between; align-items: center; gap: var(--space-3); }
h2 { font-size: var(--step-2); margin-top: var(--space-5); }
.list { list-style: none; padding: 0; display: grid; gap: var(--space-3); }
.item { display: flex; align-items: center; gap: var(--space-4); flex-wrap: wrap; padding: var(--space-4); }
.item > div { flex: 1; min-width: 220px; }
.item p { margin: 4px 0 0; }
.past { margin-top: var(--space-6); }
</style>
