# Tauros Barbería — reservas en línea y panel de administración

Vue 3 + Vite (frontend), funciones de servidor en `/api` (Vercel) y Supabase (PostgreSQL, Auth, Realtime).

## Estructura

```
api/                     Funciones de servidor (Vercel). Usan la clave service_role.
  reservas.js            POST crear cita
  cita.js                POST consultar / cancelar / reprogramar con enlace privado
src/
  views/public/          Inicio, reserva en 6 pasos, mi cita, mis citas, login
  views/admin/           Resumen, citas (día/semana/lista), barberos, sillas, horarios, servicios, ajustes
  components/booking/    Calendario, plano de sillas, horas, indicador en vivo
  composables/           Disponibilidad + Realtime
supabase/migrations/     001 esquema, 002 funciones, 003 seguridad y realtime
supabase/seed.sql        Datos DE EJEMPLO (precios y barberos ficticios)
```

## Puesta en marcha

1. **Supabase**: crea el proyecto y en *SQL Editor* ejecuta, en orden:
   `001_schema.sql`, `002_functions.sql`, `003_security_realtime.sql`, `seed.sql`.
2. **Primer admin**: *Authentication → Users → Add user*, luego:
   ```sql
   update public.profiles set role = 'admin'
    where id = (select id from auth.users where email = 'TU_CORREO');
   ```
3. **Variables**: copia `.env.example` a `.env` y llena las claves (*Project Settings → API*).
4. **Local**: `npm install` y `npm run dev` → http://localhost:5173 (el `/api` corre dentro de Vite, no hace falta la CLI de Vercel).
5. **Vercel**: importa el repo (framework Vite) y agrega las mismas 5 variables de `.env.example`.
6. **Auth → URL Configuration**: pon la URL de Vercel como *Site URL* y agrega `https://TU-DOMINIO/restablecer` en *Redirect URLs*.

## Cómo funciona la seguridad

- Toda la validación de reservas está en PostgreSQL (`_create_appointment`, `_available_slots`): horario general, horario del barbero con pausas, asignación silla↔barbero, cierres/festivos/vacaciones/mantenimiento, margen de preparación, anticipación mínima y citas existentes.
- Doble reserva imposible: restricciones `EXCLUDE` sobre silla y barbero + bloqueo por silla. Probado con 6 reservas simultáneas a la misma hora: entra 1.
- RLS en todas las tablas. Los clientes no ven datos de otros; nadie puede darse rol admin desde la app.
- Invitados: cada cita genera un token de 192 bits; en la BD solo se guarda su hash SHA‑256. El enlace usa `#t=` para que el token no viaje en logs del servidor.
- `service_role` solo en `/api` (variables sin prefijo `VITE_`). Límite de solicitudes por IP anonimizada.
- Realtime: los clientes escuchan `availability_events` (sin datos personales). Si Realtime falla, la página refresca cada 45 s. La comprobación final siempre la hace la BD.
- Cambios de horario, bloqueos, desactivar barbero/silla o reasignar: si dejan citas por fuera, el panel muestra cuáles y pide confirmación.

## Pendiente / decisiones

- **Figma**: no se pudo abrir el archivo (sin permiso de acceso). Los colores y tipografías están en `src/styles/base.css` (`:root`) y el logo es provisional en `src/components/ui/BrandMark.vue`; ajústalos al diseño.
- **Notificaciones**: no se envían correos ni WhatsApp. El punto para agregarlas está marcado con `TODO` en `api/reservas.js`.
- **Datos de ejemplo**: servicios, precios y barberos del seed son ficticios (marcados como "ejemplo").
- Reservas pendientes: si en *Ajustes* se desactiva la confirmación automática, apartan el horario por el tiempo configurado y luego se liberan solas. Opcional: activar `pg_cron` (comentado al final de `003`).
