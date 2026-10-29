<script setup>
import { reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { TriangleAlert } from '@lucide/vue'
import BrandMark from '@/components/ui/BrandMark.vue'
import { useAuthStore } from '@/stores/auth'
import { useUiStore } from '@/stores/ui'

const auth = useAuthStore()
const ui = useUiStore()
const route = useRoute()
const router = useRouter()
const form = reactive({ email: '', password: '' })
const busy = ref(false)
const error = ref('')
const resetMode = ref(false)

async function submit() {
  error.value = ''
  if (!form.email.trim()) { error.value = 'Escribe tu correo.'; return }
  busy.value = true
  try {
    if (resetMode.value) {
      await auth.resetPassword(form.email, '/restablecer')
      ui.toast('Si el correo existe, te llegará un enlace para cambiar la contraseña.')
      resetMode.value = false
      return
    }
    await auth.signIn(form.email, form.password)
    if (!auth.isAdmin) {
      await auth.signOut()
      error.value = 'Esta cuenta no tiene permisos de administración.'
      return
    }
    router.replace(String(route.query.next || '/admin'))
  } catch (e) {
    error.value = e.message === 'Invalid login credentials' ? 'Correo o contraseña incorrectos.' : 'No se pudo iniciar sesión. Intenta de nuevo.'
  } finally { busy.value = false }
}
</script>

<template>
  <div class="wrap">
    <form class="panel card" novalidate @submit.prevent="submit">
      <BrandMark />
      <h1>Administración</h1>
      <div class="field">
        <label for="a-email">Correo</label>
        <input id="a-email" v-model="form.email" class="input" type="email" autocomplete="username" />
      </div>
      <div v-if="!resetMode" class="field">
        <label for="a-pass">Contraseña</label>
        <input id="a-pass" v-model="form.password" class="input" type="password" autocomplete="current-password" />
      </div>
      <div v-if="error" class="alert alert--error" role="alert"><TriangleAlert :size="18" /><p>{{ error }}</p></div>
      <button class="btn btn--gold full" :disabled="busy">{{ busy ? 'Un momento…' : resetMode ? 'Enviar enlace' : 'Ingresar' }}</button>
      <button type="button" class="link small" @click="resetMode = !resetMode">{{ resetMode ? 'Volver a ingresar' : 'Olvidé mi contraseña' }}</button>
      <RouterLink to="/" class="small back">Ir al sitio público</RouterLink>
    </form>
  </div>
</template>

<style scoped>
.wrap { min-height: 100vh; display: grid; place-items: center; padding: var(--space-4); }
.card { width: min(400px, 100%); display: grid; gap: var(--space-2); }
.card h1 { margin: var(--space-4) 0 var(--space-3); font-size: var(--step-3); }
.full { width: 100%; }
.link { background: none; border: 0; color: var(--gold); cursor: pointer; justify-self: start; padding: var(--space-2) 0; text-decoration: underline; }
.back { color: var(--steel); }
</style>
