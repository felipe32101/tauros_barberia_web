<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { TriangleAlert } from '@lucide/vue'
import { api } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/errors'
import { money, minutesLabel, fmtDateTime } from '@/lib/format'
import { useUiStore } from '@/stores/ui'
import BaseModal from '@/components/ui/BaseModal.vue'
import SlotPicker from './SlotPicker.vue'

const props = defineProps({ date: { type: String, required: true } })
const emit = defineEmits(['close', 'saved'])
const ui = useUiStore()

const services = ref([])
onMounted(async () => {
  const { data } = await supabase.from('services').select('id, name, price, duration_minutes').eq('is_active', true).order('sort_order')
  services.value = data || []
})

const serviceId = ref('')
const service = computed(() => services.value.find((s) => s.id === serviceId.value))
const pick = ref(null)
const form = reactive({ full_name: '', phone: '', email: '', notes: '', status: 'confirmada' })
const busy = ref(false)
const error = ref('')

async function save() {
  error.value = ''
  if (!pick.value) { error.value = 'Elige silla y hora.'; return }
  busy.value = true
  try {
    const a = await api.rpc('admin_create_appointment', {
      p_service_id: serviceId.value, p_chair_id: pick.value.chair_id, p_starts_at: pick.value.starts_at,
      p_full_name: form.full_name, p_phone: form.phone, p_email: form.email || null, p_notes: form.notes || null,
      p_status: form.status
    })
    ui.toast(`Cita ${a.booking_reference} creada para ${fmtDateTime(a.starts_at)}.`)
    emit('saved', a)
  } catch (e) { error.value = errorMessage(e) }
  finally { busy.value = false }
}
</script>

<template>
  <BaseModal title="Nueva cita" wide @close="emit('close')">
    <div class="grid">
      <div>
        <div class="field">
          <label for="c-svc">Servicio</label>
          <select id="c-svc" v-model="serviceId" class="select">
            <option value="" disabled>Elige un servicio</option>
            <option v-for="s in services" :key="s.id" :value="s.id">{{ s.name }}, {{ minutesLabel(s.duration_minutes) }}, {{ money(s.price) }}</option>
          </select>
        </div>
        <SlotPicker :service-id="serviceId || null" :duration="service?.duration_minutes || 30" :initial-date="props.date" @change="pick = $event" />
      </div>
      <form class="client" @submit.prevent="save">
        <h3>Cliente</h3>
        <div class="field"><label for="c-name">Nombre completo</label><input id="c-name" v-model="form.full_name" class="input" required maxlength="100" /></div>
        <div class="field"><label for="c-phone">Teléfono</label><input id="c-phone" v-model="form.phone" class="input" type="tel" required maxlength="20" /></div>
        <div class="field"><label for="c-email">Correo (opcional)</label><input id="c-email" v-model="form.email" class="input" type="email" maxlength="160" /></div>
        <div class="field"><label for="c-notes">Observaciones</label><textarea id="c-notes" v-model="form.notes" class="textarea" maxlength="500" /></div>
        <div class="field">
          <label for="c-status">Estado inicial</label>
          <select id="c-status" v-model="form.status" class="select">
            <option value="confirmada">Confirmada</option>
            <option value="pendiente">Pendiente</option>
          </select>
        </div>
      </form>
    </div>
    <div v-if="error" class="alert alert--error" role="alert"><TriangleAlert :size="18" /><p>{{ error }}</p></div>
    <template #footer>
      <button class="btn" @click="emit('close')">Cancelar</button>
      <button class="btn btn--gold" :disabled="busy || !pick || !serviceId" @click="save">{{ busy ? 'Guardando…' : 'Crear cita' }}</button>
    </template>
  </BaseModal>
</template>

<style scoped>
.grid { display: grid; gap: var(--space-5); }
@media (min-width: 820px) { .grid { grid-template-columns: 1fr 280px; } }
.client h3 { font-size: var(--step-1); }
</style>
