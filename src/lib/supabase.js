import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isConfigured = Boolean(url && anonKey)

if (!isConfigured) {
  console.warn('[Tauros] Falta VITE_SUPABASE_URL o VITE_SUPABASE_ANON_KEY. Copia .env.example a .env.')
}

// Solo la clave pública (anon). La clave service_role vive únicamente en /api.
export const supabase = createClient(
  url || 'https://example.supabase.co',
  anonKey || 'missing-anon-key',
  { auth: { persistSession: true, autoRefreshToken: true } }
)
