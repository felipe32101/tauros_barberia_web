<script setup>
import { reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { TriangleAlert } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { useUiStore } from '@/stores/ui'
import { errorMessage } from '@/lib/errors'

const auth = useAuthStore()
const ui = useUiStore()
const route = useRoute()
const router = useRouter()

const mode = ref('login') // login | signup | reset
const form = reactive({ full_name: '', email: '', password: '' })
const busy = ref(false)
const error = ref('')

const authMessages = {
  'Invalid login credentials': 'Correo o contraseña incorrectos.',
  'Email not confirmed': 'Confirma tu correo antes de ingresar (revisa tu bandeja).',
  'User already registered': 'Ya existe una cuenta con ese correo.'
}

async function submit() {
  error.value = ''
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.email.trim())) { error.value = 'Escribe un correo válido.'; return }
  if (mode.value !== 'reset' && form.password.length < 8) { error.value = 'La contraseña debe tener al menos 8 caracteres.'; return }
  if (mode.value === 'signup' && form.full_name.trim().length < 3) { error.value = 'Escribe tu nombre completo.'; return }
  busy.value = true
  try {
    if (mode.value === 'login') {
      await auth.signIn(form.email, form.password)
      router.replace(String(route.query.next || '/mis-citas'))
    } else if (mode.value === 'signup') {
      const data = await auth.signUp(form.full_name, form.email, form.password)
      if (data.session) router.replace('/mis-citas')
      else { ui.toast('Te enviamos un correo para confirmar tu cuenta.'); mode.value = 'login' }
    } else {
      await auth.resetPassword(form.email)
      ui.toast('Si el correo existe, te llegará un enlace para crear una nueva contraseña.')
      mode.value = 'login'
    }
  } catch (e) {
    error.value = authMessages[e.message] || errorMessage(e)
  } finally { busy.value = false }
}
</script>

<template>
  <div class="container page">
    <div class="card panel">
      <h1>{{ mode === 'signup' ? 'Crear cuenta' : mode === 'reset' ? 'Recuperar contraseña' : 'Ingresar' }}</h1>
      <p class="muted small">
        {{ mode === 'signup' ? 'Con una cuenta ves todas tus citas en un solo lugar. No es obligatoria para reservar.' :
           mode === 'reset' ? 'Te enviaremos un enlace a tu correo.' : 'Para ver tus citas reservadas con tu cuenta.' }}
      </p>
      <form novalidate @submit.prevent="submit">
        <div v-if="mode === 'signup'" class="field">
          <label for="l-name">Nombre completo</label>
          <input id="l-name" v-model="form.full_name" class="input" autocomplete="name" />
        </div>
        <div class="field">
          <label for="l-email">Correo</label>
          <input id="l-email" v-model="form.email" class="input" type="email" autocomplete="email" />
        </div>
        <div v-if="mode !== 'reset'" class="field">
          <label for="l-pass">Contraseña</label>
          <input id="l-pass" v-model="form.password" class="input" type="password" :autocomplete="mode === 'signup' ? 'new-password' : 'current-password'" />
        </div>
        <div v-if="error" class="alert alert--error" role="alert"><TriangleAlert :size="18" /><p>{{ error }}</p></div>
        <button class="btn btn--gold full" type="submit" :disabled="busy">
          {{ busy ? 'Un momento…' : mode === 'signup' ? 'Crear cuenta' : mode === 'reset' ? 'Enviar enlace' : 'Ingresar' }}
        </button>
      </form>
      <div class="switch small">
        <button v-if="mode !== 'login'" class="link" @click="mode = 'login'">Ya tengo cuenta</button>
        <button v-if="mode !== 'signup'" class="link" @click="mode = 'signup'">Crear cuenta</button>
        <button v-if="mode !== 'reset'" class="link" @click="mode = 'reset'">Olvidé mi contraseña</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.page { padding-top: var(--space-7); display: grid; place-items: start center; }
.card { width: min(440px, 100%); }
.full { width: 100%; }
.switch { display: flex; flex-wrap: wrap; gap: var(--space-4); margin-top: var(--space-4); }
.link { background: none; border: 0; color: var(--gold); cursor: pointer; padding: 0; text-decoration: underline; text-underline-offset: 3px; }
</style>
