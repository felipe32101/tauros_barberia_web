import { defineStore } from 'pinia'
import { setTimezone } from '@/lib/format'
import { api } from '@/lib/api'

let toastId = 0

export const useUiStore = defineStore('ui', {
  state: () => ({
    toasts: [],
    dialog: null,      // { title, message, items, confirmText, cancelText, danger, input, resolve }
    info: null         // configuración pública de la barbería
  }),
  actions: {
    toast(message, type = 'ok', ms = 4200) {
      const id = ++toastId
      this.toasts.push({ id, message, type })
      setTimeout(() => this.dismiss(id), ms)
    },
    dismiss(id) { this.toasts = this.toasts.filter((t) => t.id !== id) },

    // Diálogo de confirmación. Devuelve Promise<boolean> (o el texto si input = true).
    confirm(opts) {
      return new Promise((resolve) => {
        this.dialog = { confirmText: 'Confirmar', cancelText: 'Volver', ...opts, resolve }
      })
    },
    closeDialog(value) {
      const d = this.dialog
      this.dialog = null
      d?.resolve(value)
    },

    // Ejecuta una acción admin que puede devolver citas afectadas y pedir confirmación.
    // fn(confirm:boolean) debe devolver { saved, conflicts }.
    async withConflicts(fn, what = 'Este cambio') {
      const first = await fn(false)
      if (first?.saved !== false) return first
      const ok = await this.confirm({
        title: 'Hay citas afectadas',
        message: `${what} deja por fuera las siguientes citas. Si continúas, tendrás que reprogramarlas o cancelarlas desde Citas.`,
        items: first.conflicts,
        confirmText: 'Aplicar de todas formas',
        danger: true
      })
      if (!ok) return { saved: false, cancelled: true }
      return fn(true)
    },

    async loadInfo() {
      if (this.info) return this.info
      try {
        this.info = await api.publicInfo()
        setTimezone(this.info?.timezone)
      } catch (e) {
        console.warn('[info]', e)
      }
      return this.info
    }
  }
})
