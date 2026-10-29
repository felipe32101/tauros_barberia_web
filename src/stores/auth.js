import { defineStore } from 'pinia'
import { supabase } from '@/lib/supabase'

// El rol que guarda este store solo decide qué se muestra.
// La seguridad real está en las políticas RLS y en las funciones de la base de datos.
export const useAuthStore = defineStore('auth', {
  state: () => ({ session: null, profile: null, ready: false, _readyPromise: null }),
  getters: {
    user: (s) => s.session?.user ?? null,
    isLoggedIn: (s) => Boolean(s.session),
    isAdmin: (s) => s.profile?.role === 'admin'
  },
  actions: {
    init() {
      if (this._readyPromise) return this._readyPromise
      this._readyPromise = (async () => {
        try {
          const { data } = await supabase.auth.getSession()
          this.session = data.session
          await this.loadProfile()
        } catch (e) {
          console.warn('[auth]', e)
        } finally {
          this.ready = true
        }
        supabase.auth.onAuthStateChange(async (_event, session) => {
          this.session = session
          await this.loadProfile()
        })
      })()
      return this._readyPromise
    },
    async loadProfile() {
      if (!this.session) { this.profile = null; return }
      const { data } = await supabase.from('profiles').select('id, full_name, role').eq('id', this.session.user.id).maybeSingle()
      this.profile = data
    },
    async signIn(email, password) {
      const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
      if (error) throw error
      this.session = data.session
      await this.loadProfile()
    },
    async signUp(fullName, email, password) {
      const { data, error } = await supabase.auth.signUp({
        email: email.trim(),
        password,
        options: { data: { full_name: fullName.trim() }, emailRedirectTo: `${window.location.origin}/mis-citas` }
      })
      if (error) throw error
      this.session = data.session
      await this.loadProfile()
      return data
    },
    async resetPassword(email, redirectPath = '/restablecer') {
      const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
        redirectTo: `${window.location.origin}${redirectPath}`
      })
      if (error) throw error
    },
    async updatePassword(password) {
      const { error } = await supabase.auth.updateUser({ password })
      if (error) throw error
    },
    async signOut() {
      await supabase.auth.signOut()
      this.session = null
      this.profile = null
    }
  }
})
