<script setup>
import { computed, onMounted, ref } from 'vue'
import { api } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { today, fmtTime } from '@/lib/format'
import { useAvailability } from '@/composables/useAvailability'
import ServiceCard from '@/components/ServiceCard.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import StateBlock from '@/components/ui/StateBlock.vue'
import LiveIndicator from '@/components/booking/LiveIndicator.vue'

const services = ref([])
const svcState = ref('loading')
const svcError = ref('')

async function loadServices() {
  svcState.value = 'loading'
  try {
    services.value = await api.activeServices()
    svcState.value = services.value.length ? 'ready' : 'empty'
  } catch (e) {
    svcError.value = errorMessage(e)
    svcState.value = 'error'
  }
}
onMounted(loadServices)

// Tablero "hoy": estado de las sillas para el servicio más corto
const refService = computed(() => [...services.value].sort((a, b) => a.duration_minutes - b.duration_minutes)[0])
const day = ref(today())
const { status, data, live } = useAvailability(day, (d) => api.availability(d, refService.value.id), {
  enabled: computed(() => Boolean(refService.value))
})
</script>

<template>
  <section class="hero">
    <img class="hero__bg" src="/img/hero-corte.jpg" alt="" aria-hidden="true" fetchpriority="high" />
    <div class="hero__veil" aria-hidden="true"></div>
    <div class="container hero__grid">
      <div class="hero__copy">
        <p class="hero__eyebrow">Barbería · Cortes clásicos y modernos</p>
        <h1 class="hero__mark">Tauros</h1>
        <p class="hero__lead">Cortes, barba y afeitado a navaja. Escoge tu servicio, tu silla y tu hora sin llamar ni hacer fila.</p>
        <div class="hero__actions">
          <RouterLink to="/reservar" class="btn btn--gold">Agendar cita</RouterLink>
          <RouterLink to="/#servicios" class="btn">Ver servicios</RouterLink>
        </div>
      </div>

      <aside class="board" aria-labelledby="board-title">
        <div class="board__head">
          <h2 id="board-title" class="board__title">Sillas hoy</h2>
          <LiveIndicator :live="live" />
        </div>
        <ul v-if="data?.chairs?.length" class="board__list">
          <li v-for="c in data.chairs" :key="c.chair_id" class="board__row">
            <span class="board__chair">{{ c.chair_name }}</span>
            <span class="board__barber muted small">{{ c.barber_name || 'Sin barbero' }}</span>
            <StatusBadge :status="c.status" kind="chair" />
            <span class="board__next small">{{ c.next_slot ? `Desde ${fmtTime(c.next_slot)}` : '' }}</span>
          </li>
        </ul>
        <p v-else-if="status === 'loading' || svcState === 'loading'" class="muted small">Cargando sillas…</p>
        <p v-else class="muted small">Hoy no quedan horarios. Mira los próximos días al agendar.</p>
        <RouterLink to="/reservar" class="board__link small">Ver todos los horarios</RouterLink>
      </aside>
    </div>
  </section>

  <section id="servicios" class="section container">
    <div class="section__head">
      <h2>Servicios</h2>
      <p class="muted">Precio y duración de cada servicio. Al reservar se guarda el precio que ves hoy.</p>
    </div>
    <StateBlock v-if="svcState !== 'ready'" :state="svcState" :message="svcState === 'empty' ? 'Todavía no hay servicios publicados.' : svcError" @retry="loadServices" />
    <div v-else class="services">
      <ServiceCard v-for="s in services" :key="s.id" :service="s" />
    </div>
  </section>

  <section id="galeria" class="section container">
    <div class="section__head">
      <h2>La barbería</h2>
      <p class="muted">Un lugar para sentarse, relajarse y salir como nuevo.</p>
    </div>
    <div class="gallery">
      <figure class="gallery__item gallery__item--wide">
        <img src="/img/sillas.jpg" alt="Sillas de barbero clásicas en ladrillo" loading="lazy" width="1600" height="1067" />
        <figcaption>Nuestras sillas</figcaption>
      </figure>
      <figure class="gallery__item">
        <img src="/img/navaja.jpg" alt="Corte con navaja y máquina" loading="lazy" width="1600" height="1067" />
        <figcaption>Detalle al detalle</figcaption>
      </figure>
      <figure class="gallery__item">
        <img src="/img/barba.jpg" alt="Perfilado de barba con cepillo" loading="lazy" width="1200" height="1800" />
        <figcaption>Barba y perfilado</figcaption>
      </figure>
      <figure class="gallery__item gallery__item--wide">
        <img src="/img/interior.jpg" alt="Sillón de barbería en cuero" loading="lazy" width="1600" height="1067" />
        <figcaption>Tu silla te espera</figcaption>
      </figure>
      <figure class="gallery__item">
        <img src="/img/herramientas.jpg" alt="Máquinas y peines sobre madera" loading="lazy" width="1200" height="800" />
        <figcaption>Herramientas</figcaption>
      </figure>
      <figure class="gallery__item">
        <img src="/img/sala.jpg" alt="Interior de la barbería" loading="lazy" width="1600" height="1067" />
        <figcaption>El ambiente</figcaption>
      </figure>
    </div>
  </section>

  <section id="como-reservar" class="section container steps">
    <h2>Así reservas</h2>
    <ol class="steps__list">
      <li><strong>Elige el servicio.</strong> Ves el precio y cuánto dura.</li>
      <li><strong>Escoge el día.</strong> Solo aparecen los días con horarios libres.</li>
      <li><strong>Mira las sillas.</strong> Cada una muestra su barbero y si está libre.</li>
      <li><strong>Toma tu hora</strong> y confirma con tu nombre y teléfono. Recibes un enlace para cambiar o cancelar.</li>
    </ol>
  </section>
</template>

<style scoped>
.hero { position: relative; isolation: isolate; border-bottom: 1px solid var(--line); background:
  radial-gradient(900px 400px at 85% 0%, rgba(201, 162, 77, .09), transparent 60%), var(--ink); }
.hero__bg {
  position: absolute; inset: 0; z-index: -2; width: 100%; height: 100%;
  object-fit: cover; object-position: 70% 40%; opacity: .5;
}
.hero__veil {
  position: absolute; inset: 0; z-index: -1;
  background: linear-gradient(90deg, #000 8%, rgba(0, 0, 0, .88) 42%, rgba(0, 0, 0, .35) 100%),
              linear-gradient(0deg, #000 2%, transparent 45%);
}
.hero__grid { display: grid; gap: var(--space-7); padding-block: var(--space-8) var(--space-7); align-items: end; }
@media (min-width: 960px) { .hero__grid { grid-template-columns: 1.25fr .9fr; } }

.hero__eyebrow {
  font-size: var(--step--1); letter-spacing: .16em; text-transform: uppercase;
  color: var(--gold); font-weight: 600; margin-bottom: var(--space-3);
}
.hero__mark {
  font-size: var(--step-5); font-weight: 700; line-height: .9; letter-spacing: -0.03em; margin: 0 0 var(--space-5);
  color: var(--bone);
  /* La línea dorada bajo el nombre funciona como el filo de una navaja */
  padding-bottom: var(--space-4); border-bottom: 2px solid var(--gold); display: inline-block;
}
.hero__lead { font-size: var(--step-1); color: #cfcac2; max-width: 36ch; line-height: 1.45; }
.hero__actions { display: flex; flex-wrap: wrap; gap: var(--space-3); margin-top: var(--space-5); }

.board { background: var(--carbon); border: 1px solid var(--line); border-radius: var(--radius-l); padding: var(--space-5); }
.board__head { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: var(--space-2); margin-bottom: var(--space-3); }
.board__title { font-size: var(--step-2); margin: 0; }
.board__list { list-style: none; padding: 0; margin: 0 0 var(--space-3); }
.board__row {
  display: grid; grid-template-columns: auto 1fr auto; grid-template-areas: 'chair barber badge' 'next next next';
  column-gap: var(--space-3); row-gap: 2px; align-items: center; padding: var(--space-3) 0; border-bottom: 1px solid var(--line);
}
.board__chair { grid-area: chair; font-family: var(--font-display); font-size: var(--step-1); }
.board__barber { grid-area: barber; }
.board__row :deep(.badge) { grid-area: badge; }
.board__next { grid-area: next; color: var(--steel); }
.board__link { display: inline-block; margin-top: var(--space-2); }

.section { padding-top: var(--space-8); }
.section__head { margin-bottom: var(--space-5); }
.services { display: grid; gap: var(--space-3); grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); }

.gallery { display: grid; gap: var(--space-3); grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); }
.gallery__item {
  position: relative; margin: 0; overflow: hidden; border-radius: var(--radius-m);
  border: 1px solid var(--line); background: var(--carbon); aspect-ratio: 4 / 3;
}
.gallery__item--wide { grid-column: span 2; aspect-ratio: 8 / 3; }
@media (max-width: 640px) {
  .gallery__item--wide { grid-column: span 1; aspect-ratio: 4 / 3; }
}
.gallery__item img {
  width: 100%; height: 100%; object-fit: cover; display: block;
  filter: saturate(.85) brightness(.82); transform: scale(1.01);
  transition: transform .5s var(--ease), filter .5s var(--ease);
}
.gallery__item:hover img { transform: scale(1.06); filter: saturate(1) brightness(1); }
.gallery__item figcaption {
  position: absolute; left: 0; right: 0; bottom: 0; padding: var(--space-4) var(--space-4) var(--space-3);
  font-size: var(--step--1); font-weight: 600; letter-spacing: .06em; text-transform: uppercase; color: var(--bone);
  background: linear-gradient(0deg, rgba(0, 0, 0, .85), transparent);
}
.gallery__item::after {
  content: ''; position: absolute; inset: 0; pointer-events: none;
  box-shadow: inset 0 0 0 1px rgba(201, 162, 77, .16);
  border-radius: inherit;
}

.steps__list { margin: 0; padding-left: 1.4em; display: grid; gap: var(--space-3); max-width: 62ch; }
.steps__list li::marker { color: var(--gold); font-family: var(--font-display); font-weight: 700; }
</style>
