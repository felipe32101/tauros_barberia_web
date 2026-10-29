import { onBeforeUnmount } from 'vue'
import { supabase } from '@/lib/supabase'

// Llama a `fn` cuando cambia cualquier dato que afecte la agenda (citas, horarios, sillas…).
export function useRealtimeRefresh(fn, delay = 500) {
  let t = null
  const ch = supabase
    .channel(`admin-${Math.random().toString(36).slice(2)}`)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'availability_events' }, () => {
      clearTimeout(t)
      t = setTimeout(fn, delay)
    })
    .subscribe()
  onBeforeUnmount(() => { clearTimeout(t); supabase.removeChannel(ch) })
}
