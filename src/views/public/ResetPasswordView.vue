<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useUiStore } from '@/stores/ui'
import { errorMessage } from '@/lib/errors'

// Supabase abre esta página con la sesión de recuperación ya iniciada.
const auth = useAuthStore()
const ui = useUiStore()
const router = useRouter()
const password = ref('')
const busy = ref(false)
const error = ref('')

async function save() {
  if (password.value.length < 8) { error.value = 'Mínimo 8 caracteres.'; return }
  busy.value = true
  try {
    await auth.updatePassword(password.value)
    ui.toast('Contraseña actualizada.')
    router.replace(auth.isAdmin ? '/admin' : '/mis-citas')
  } catch (e) { error.value = errorMessage(e, 'El enlace venció. Pide uno nuevo.') }
  finally { busy.value = false }
}
</script>

<template>
  <div class="container page">
    <form class="panel card" @submit.prevent="save">
      <h1>Nueva contraseña</h1>
      <div class="field">
        <label for="np">Contraseña nueva</label>
        <input id="np" v-model="password" class="input" type="password" autocomplete="new-password" />
      </div>
      <p v-if="error" class="field-error" role="alert">{{ error }}</p>
      <button class="btn btn--gold" :disabled="busy">Guardar contraseña</button>
    </form>
  </div>
</template>

<style scoped>
.page { padding-top: var(--space-7); display: grid; place-items: start center; }
.card { width: min(420px, 100%); }
</style>
