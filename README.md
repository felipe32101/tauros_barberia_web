# 💈 Tauros Barbería - Sistema de Gestión y Reservas en Tiempo Real

**Tauros Barbería** es una plataforma web moderna y responsive desarrollada para la gestión integral de citas, barberos, servicios y horarios en una barbería. Ofrece una experiencia intuitiva tanto para los clientes (que desean agendar citas de forma interactiva en tiempo real) como para los administradores y barberos (que gestionan la agenda y disponibilidades).

---

## 🚀 De qué trata el Proyecto

El sistema está dividido en dos grandes módulos principales:

1. **Portal Público (Clientes):**
   - **Reserva de Citas Interactiva:** Selección de servicios, barberos disponibles, selector visual de sillas (`ChairFloor`) y bloques de horarios libres (`SlotPicker`).
   - **Visualización en Tiempo Real:** Indicadores en vivo sobre la disponibilidad de sillas y turnos.
   - **Gestión de Mis Citas:** Los clientes pueden consultar el estado de sus reservas actuales e históricas.
   - **Autenticación:** Iniciar sesión y recuperación de contraseña.

2. **Panel de Administración (Barberos / Admin):**
   - **Dashboard e Métricas:** Resumen visual del estado diario de citas y ocupación.
   - **Gestión de Citas:** Crear, detallar, reprogramar o cancelar reservas.
   - **Gestión de Barberos y Sillas:** Alta/baja de barberos y asignación de puestos de trabajo.
   - **Gestión de Servicios:** Configuración de precios, duraciones y catálogo.
   - **Horarios y Configuración:** Control sobre días laborales, turnos y parámetros del negocio.

---

## 🏗️ Arquitectura e Infraestructura

El proyecto sigue una arquitectura **Serverless / Jamstack**, desacoplada, escalable y optimizada para responder en tiempo real.

```
       +-------------------------------------------------------+
       |                  Cliente (Frontend)                    |
       |  Vue 3 (Vite) + Pinia + Vue Router + Tailwind CSS      |
       +--------------------------+----------------------------+
                                  |
            +---------------------+---------------------+
            |                                           |
            v                                           v
+-----------------------+                   +-----------------------+
|  Supabase (Backend)   |                   |  Vercel Serverless    |
| - PostgreSQL (Schema) |                   |  API Routes           |
| - Auth & RLS          |                   |  (/api/reservas,      |
| - Realtime Sync       |                   |   /api/cita)         |
| - PL/pgSQL Functions  |                   +-----------------------+
+-----------------------+
```

### 1. Frontend (SPA)
- **Framework:** [Vue 3](https://vuejs.org/) (Composition API) impulsado por [Vite](https://vitejs.org/).
- **Gestión de Estado:** [Pinia](https://pinia.vuejs.org/) (`auth.js`, `ui.js`).
- **Enrutamiento:** [Vue Router](https://router.vuejs.org/) con guards de navegación para rutas públicas y protegidas de administración.
- **Estilos:** CSS Modular / Utility-first.

### 2. Backend & Base de Datos (Supabase)
- **Base de Datos:** PostgreSQL administrado en [Supabase](https://supabase.com/).
- **Esquema y Migraciones (`supabase/migrations/`):**
  - `001_schema.sql`: Definición de tablas (`appointments`, `barbers`, `chairs`, `services`, `schedules`, etc.).
  - `002_functions.sql`: Procedimientos almacenados en PL/pgSQL para lógica compleja de disponibilidad y validación de turnos sin colisiones.
  - `003_security_realtime.sql`: Políticas de seguridad a nivel de fila (**RLS - Row Level Security**) y configuración de suscripciones **Realtime**.
- **Autenticación:** Supabase Auth integrado para administradores y clientes.

### 3. Serverless API (Vercel Node.js Functions)
Ubicadas en el directorio `/api`, procesan solicitudes del servidor que requieren lógica segura o transacciones adicionales:
- `api/reservas.js`: Endpoints para consultar/crear reservas.
- `api/cita.js`: Gestión y validación puntual de citas.
- `api/_lib/server.js`: Helpers e inicialización de clientes del servidor.

---

## 📁 Estructura del Proyecto

```text
tauros-barberia/
├── api/                        # Serverless API routes (Vercel)
│   ├── _lib/                   # Helpers de servidor
│   ├── cita.js                 # API handler de cita individual
│   └── reservas.js             # API handler de reservas masivas/búsqueda
├── public/                     # Assets estáticos (Favicon, logos)
├── src/
│   ├── assets/                 # Recursos gráficos
│   ├── components/             # Componentes UI reutilizables
│   │   ├── admin/              # Componentes del dashboard (SlotPicker, AppointmentCreate, etc.)
│   │   ├── booking/            # Componentes del flujo de reserva (ChairFloor, SlotGrid, LiveIndicator)
│   │   └── ui/                 # Componentes atómicos (BaseModal, ConfirmDialog, StatusBadge, ToastHost)
│   ├── composables/            # Lógica reactiva extraída (useAvailability.js, useRealtimeRefresh.js)
│   ├── lib/                    # Clientes y utilidades (supabase.js, api.js, errors.js, format.js)
│   ├── router/                 # Configuración de Vue Router
│   ├── stores/                 # Tiendas de Pinia (auth.js, ui.js)
│   ├── styles/                 # Hojas de estilo base
│   ├── views/                  # Vistas principales
│   │   ├── admin/              # Dashboard, Barberos, Servicios, Citas, Horarios, Configuración
│   │   └── public/             # Home, Booking, Mis Citas, Login, Reset Password
│   ├── App.vue                 # Componente raíz
│   └── main.js                 # Punto de entrada de la aplicación Vue
├── supabase/                   # Scripts de la infraestructura de BD
│   ├── migrations/             # Migraciones SQL (Schema, Functions, RLS/Realtime)
│   └── seed.sql                # Datos iniciales de prueba
├── .env.example                # Plantilla de variables de entorno
├── index.html                  # HTML base
├── package.json                # Dependencias y scripts de NPM
├── vercel.json                 # Configuración de despliegue en Vercel
└── vite.config.js              # Configuración de Vite
```

---

## 🛠️ Requisitos Previos

Antes de comenzar, asegúrate de contar con:
- **Node.js**: `v18.x` o superior.
- **npm** o **pnpm**.
- Una cuenta activa en **[Supabase](https://supabase.com/)**.
- CLI de Supabase (opcional pero recomendado para aplicar migraciones).

---

## ⚙️ Configuración del Entorno Local

1. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/tu-usuario/tauros-barberia.git
   cd tauros-barberia
   ```

2. **Instalar dependencias:**
   ```bash
   npm install
   ```

3. **Configurar Variables de Entorno:**
   Copia el archivo de ejemplo `.env.example` a `.env`:
   ```bash
   cp .env.example .env
   ```
   Rellena los valores requeridos con tus credenciales de Supabase:
   ```env
   VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
   VITE_SUPABASE_ANON_KEY=tu-anon-key
   ```

4. **Inicializar la Base de Datos en Supabase:**
   Ejecuta en el editor SQL de Supabase o mediante el CLI las migraciones contenidas en la carpeta `supabase/migrations/` en orden consecutivo:
   - `001_schema.sql`
   - `002_functions.sql`
   - `003_security_realtime.sql`
   - *(Opcional)* `seed.sql` para cargar datos iniciales de prueba.

5. **Iniciar el servidor de desarrollo:**
   ```bash
   npm run dev
   ```
   Abre tu navegador en `http://localhost:5173`.

---

## 🚀 Despliegue (Deployment)

El proyecto está preparado de forma nativa para ser desplegado en **Vercel**:

1. Vincula tu repositorio de GitHub a un nuevo proyecto en **Vercel**.
2. Vercel detectará la configuración automáticamente mediante el archivo `vercel.json` y los endpoints en `/api`.
3. Configura las **Environment Variables** en el panel de Vercel (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, etc.).
4. Haz clic en **Deploy**.

---

## 📄 Licencia

Este proyecto se distribuye bajo la licencia **MIT**. Consulta el archivo `LICENSE` para más detalles.