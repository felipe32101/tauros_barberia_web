import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  {
    path: '/',
    component: () => import('@/views/public/PublicLayout.vue'),
    children: [
      { path: '', name: 'home', component: () => import('@/views/public/HomeView.vue') },
      { path: 'reservar', name: 'booking', component: () => import('@/views/public/BookingView.vue'), meta: { title: 'Agendar cita' } },
      { path: 'cita/:ref?', name: 'appointment', component: () => import('@/views/public/AppointmentView.vue'), meta: { title: 'Tu cita' } },
      { path: 'mis-citas', name: 'my-appointments', component: () => import('@/views/public/MyAppointmentsView.vue'), meta: { title: 'Mis citas' } },
      { path: 'ingresar', name: 'login', component: () => import('@/views/public/LoginView.vue'), meta: { title: 'Ingresar' } },
      { path: 'restablecer', name: 'reset', component: () => import('@/views/public/ResetPasswordView.vue'), meta: { title: 'Nueva contraseña' } }
    ]
  },
  { path: '/admin/login', name: 'admin-login', component: () => import('@/views/admin/AdminLogin.vue'), meta: { title: 'Administración' } },
  {
    path: '/admin',
    component: () => import('@/views/admin/AdminLayout.vue'),
    meta: { requiresAdmin: true },
    children: [
      { path: '', name: 'admin-dashboard', component: () => import('@/views/admin/DashboardView.vue'), meta: { title: 'Resumen' } },
      { path: 'citas', name: 'admin-appointments', component: () => import('@/views/admin/AppointmentsView.vue'), meta: { title: 'Citas' } },
      { path: 'barberos', name: 'admin-barbers', component: () => import('@/views/admin/BarbersView.vue'), meta: { title: 'Barberos' } },
      { path: 'sillas', name: 'admin-chairs', component: () => import('@/views/admin/ChairsView.vue'), meta: { title: 'Sillas' } },
      { path: 'horarios', name: 'admin-schedules', component: () => import('@/views/admin/SchedulesView.vue'), meta: { title: 'Horarios' } },
      { path: 'servicios', name: 'admin-services', component: () => import('@/views/admin/ServicesView.vue'), meta: { title: 'Servicios' } },
      { path: 'ajustes', name: 'admin-settings', component: () => import('@/views/admin/SettingsView.vue'), meta: { title: 'Ajustes' } }
    ]
  },
  { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/views/public/NotFoundView.vue') }
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior(to, from, saved) {
    if (saved) return saved
    if (to.hash && !to.hash.startsWith('#t=')) return { el: to.hash, behavior: 'smooth' }
    return { top: 0 }
  }
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.init()
  if (to.matched.some((r) => r.meta.requiresAdmin) && !auth.isAdmin) {
    return { name: 'admin-login', query: { next: to.fullPath } }
  }
})

router.afterEach((to) => {
  document.title = to.meta.title ? `${to.meta.title} | Tauros Barbería` : 'Tauros Barbería'
})

export default router
