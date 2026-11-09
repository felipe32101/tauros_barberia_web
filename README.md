# 💈 Tauros Barbería - Sistema de Gestión y Reservas en Tiempo Real

Bienvenido a la plataforma oficial de **Tauros Barbería**. Este sistema web interactivo ha sido desarrollado para ofrecer una experiencia rápida, moderna y sencilla al agendar citas de barbería en tiempo real, así como para facilitar la administración del negocio.

---

## 🎯 De qué trata el Proyecto

La aplicación ofrece un entorno intuitivo orientado a cubrir tanto la experiencia del cliente como las necesidades operativas de la barbería:

### 📱 Portal del Cliente
* **Reserva de Citas en Tiempo Real:** Permite seleccionar el servicio deseado, el barbero de preferencia, la silla disponible y el horario ideal sin complicaciones.
* **Indicadores Visuales en Vivo:** Muestra la disponibilidad de sillas y turnos actualizados al instante.
* **Gestión de Citas:** Consulta rápida del historial de reservas y el estado de las citas agendadas.
* **Acceso Seguro:** Creación de cuenta, inicio de sesión y recuperación de contraseña.

### 💼 Panel de Administración
* **Dashboard y Métricas:** Resumen en tiempo real de las citas del día, nivel de ocupación e ingresos.
* **Control de Barberos y Sillas:** Gestión de personal, asignación de turnos y puestos de trabajo.
* **Catálogo de Servicios:** Administración de precios, tiempos de atención y tipos de corte o tratamiento.
* **Gestión de Agenda:** Creación manual de citas, cambios de estado y configuración de horarios de atención.

---

## 🏗️ Infraestructura y Arquitectura

El proyecto está construido sobre una arquitectura **Serverless de alto rendimiento**, garantizando disponibilidad continua, respuestas inmediatas y seguridad de datos.

```
       +-------------------------------------------------------+
       |             Navegador del Cliente / Admin             |
       |                   (Interfaz Web)                      |
       +--------------------------+----------------------------+
                                  |
            +---------------------+---------------------+
            |                                           |
            v                                           v
+-----------------------+                   +-----------------------+
|  Supabase Cloud       |                   |  Vercel Serverless    |
| - Base de Datos SQL   |                   | - Lógica de API       |
| - Sincronización Vivo |                   | - Procesamiento       |
| - Seguridad (RLS)     |                   +-----------------------+
+-----------------------+
```

### Componentes Principales:

* **Frontend (Interfaz de Usuario):** Desarrollado con Vue 3 y Vite para garantizar una navegación fluida, rápida y adaptable a teléfonos móviles, tabletas y computadores.
* **Base de Datos y Tiempo Real (Supabase):** Almacenamiento seguro en la nube que gestiona la información de los usuarios y sincroniza la disponibilidad de citas en tiempo real.
* **API Serverless (Vercel):** Procesamiento seguro de reservas y validación de horarios directamente en la nube.

---

## 🌐 Acceso a la Aplicación

La aplicación se encuentra desplegada y alojada en la plataforma en la nube **Vercel**. 

Para acceder al sistema, solo debes ingresar al enlace de producción proporcionado por el administrador desde cualquier navegador web (Chrome, Safari, Edge, etc.) en tu teléfono móvil o computador:

🔗 **[Acceder a Tauros Barbería en Vercel](https://taurosbarberiaweb.vercel.app/)**

---

## 📄 Licencia

Todos los derechos reservados © Tauros Barbería.