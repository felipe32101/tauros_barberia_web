-- =====================================================================
-- Tauros Barbería — 001: esquema base
-- Ejecutar en Supabase (SQL Editor) en orden: 001, 002, 003, 004 y seed.
-- =====================================================================

create extension if not exists btree_gist with schema extensions;
create extension if not exists pgcrypto  with schema extensions;

-- ---------- Tipos ----------
do $$ begin
  create type public.app_role as enum ('cliente', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.appointment_status as enum
    ('pendiente', 'confirmada', 'completada', 'cancelada', 'no_asistio');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.exception_type as enum
    ('cierre', 'festivo', 'descanso', 'vacaciones', 'mantenimiento', 'otro');
exception when duplicate_object then null; end $$;

-- ---------- Configuración general (una sola fila) ----------
create table if not exists public.business_settings (
  id                            smallint primary key default 1 check (id = 1),
  business_name                 text    not null default 'Tauros Barbería',
  timezone                      text    not null default 'America/Bogota',
  currency                      text    not null default 'COP',
  slot_interval_minutes         int     not null default 30 check (slot_interval_minutes between 5 and 120),
  min_advance_minutes           int     not null default 30 check (min_advance_minutes between 0 and 2880),
  max_days_ahead                int     not null default 30 check (max_days_ahead between 1 and 365),
  -- true: las reservas web quedan confirmadas. false: quedan "pendiente" hasta que el admin confirme.
  auto_confirm                  boolean not null default true,
  -- minutos que una cita pendiente bloquea el horario. 0 = no caduca.
  pending_hold_minutes          int     not null default 60 check (pending_hold_minutes between 0 and 10080),
  -- horas mínimas antes de la cita para que el cliente pueda cancelar o cambiarla.
  cancel_min_hours              int     not null default 2 check (cancel_min_hours between 0 and 168),
  max_active_bookings_per_phone int     not null default 3 check (max_active_bookings_per_phone between 1 and 20),
  updated_at                    timestamptz not null default now()
);

-- ---------- Perfiles (vinculados a Supabase Auth) ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  role       public.app_role not null default 'cliente',
  created_at timestamptz not null default now()
);

-- ---------- Barberos ----------
create table if not exists public.barbers (
  id         uuid primary key default gen_random_uuid(),
  full_name  text not null check (char_length(btrim(full_name)) between 2 and 100),
  phone      text check (phone is null or phone ~ '^\+?[0-9]{7,15}$'),
  email      text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  photo_url  text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Sillas ----------
create table if not exists public.chairs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique check (char_length(btrim(name)) between 1 and 50),
  description text,
  sort_order  int  not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------- Asignación barbero ↔ silla con vigencia ----------
-- valid_until es exclusivo (la asignación termina el día anterior). NULL = sin fecha de fin.
create table if not exists public.barber_chair_assignments (
  id          uuid primary key default gen_random_uuid(),
  barber_id   uuid not null references public.barbers(id) on delete restrict,
  chair_id    uuid not null references public.chairs(id)  on delete restrict,
  valid_from  date not null default current_date,
  valid_until date,
  created_at  timestamptz not null default now(),
  check (valid_until is null or valid_until > valid_from),
  -- Un barbero no puede tener dos sillas a la vez, ni una silla dos barberos a la vez.
  constraint assignment_barber_no_overlap exclude using gist
    (barber_id with =, daterange(valid_from, valid_until, '[)') with &&),
  constraint assignment_chair_no_overlap exclude using gist
    (chair_id with =, daterange(valid_from, valid_until, '[)') with &&)
);

-- ---------- Servicios ----------
create table if not exists public.services (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (char_length(btrim(name)) between 2 and 80),
  description      text,
  price            numeric(12,2) not null check (price >= 0),
  duration_minutes int  not null check (duration_minutes between 5 and 480),
  buffer_minutes   int  not null default 0 check (buffer_minutes between 0 and 120),
  is_active        boolean not null default true,
  is_sample        boolean not null default false,  -- marca los datos de ejemplo
  sort_order       int  not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ---------- Horario general (weekday ISO: 1 = lunes … 7 = domingo) ----------
create table if not exists public.business_hours (
  weekday   smallint primary key check (weekday between 1 and 7),
  opens_at  time,
  closes_at time,
  is_closed boolean not null default false,
  check (is_closed or (opens_at is not null and closes_at is not null and closes_at > opens_at))
);

-- ---------- Horario de cada barbero ----------
-- Varias franjas por día permiten modelar pausas (ej. 09:00-13:00 y 14:00-19:00).
create table if not exists public.barber_working_hours (
  id        uuid primary key default gen_random_uuid(),
  barber_id uuid not null references public.barbers(id) on delete cascade,
  weekday   smallint not null check (weekday between 1 and 7),
  starts_at time not null,
  ends_at   time not null,
  is_active boolean not null default true,
  check (ends_at > starts_at),
  constraint barber_hours_no_overlap exclude using gist (
    barber_id with =, weekday with =,
    tsrange(date '2000-01-01' + starts_at, date '2000-01-01' + ends_at, '[)') with &&
  )
);

-- ---------- Excepciones: cierres, festivos, vacaciones, descansos, mantenimiento ----------
-- barber_id y chair_id NULL = aplica a toda la barbería.
create table if not exists public.schedule_exceptions (
  id         uuid primary key default gen_random_uuid(),
  barber_id  uuid references public.barbers(id) on delete cascade,
  chair_id   uuid references public.chairs(id)  on delete cascade,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  type       public.exception_type not null default 'otro',
  reason     text check (reason is null or char_length(reason) <= 200),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (not (barber_id is not null and chair_id is not null))
);

-- ---------- Clientes ----------
create table if not exists public.customers (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references auth.users(id) on delete set null,
  full_name  text not null check (char_length(btrim(full_name)) between 3 and 100),
  phone      text not null unique check (phone ~ '^\+?[0-9]{7,15}$'),
  email      text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Citas ----------
create table if not exists public.appointments (
  id                        uuid primary key default gen_random_uuid(),
  booking_reference         text not null unique,
  access_token_hash         text not null,           -- sha256 del token del invitado (nunca el token)
  customer_id               uuid not null references public.customers(id) on delete restrict,
  barber_id                 uuid not null references public.barbers(id)   on delete restrict,
  chair_id                  uuid not null references public.chairs(id)    on delete restrict,
  service_id                uuid not null references public.services(id)  on delete restrict,
  starts_at                 timestamptz not null,
  ends_at                   timestamptz not null,
  blocks_until              timestamptz not null,    -- ends_at + margen de preparación
  status                    public.appointment_status not null default 'confirmada',
  pending_expires_at        timestamptz,
  customer_notes            text check (customer_notes is null or char_length(customer_notes) <= 500),
  admin_notes               text check (admin_notes is null or char_length(admin_notes) <= 1000),
  service_name_snapshot     text not null,
  service_price_snapshot    numeric(12,2) not null,
  service_duration_snapshot int  not null,
  service_buffer_snapshot   int  not null default 0,
  created_by                text not null default 'cliente' check (created_by in ('cliente', 'admin')),
  cancelled_at              timestamptz,
  cancel_reason             text,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  check (ends_at > starts_at),
  check (blocks_until >= ends_at),
  -- Garantía definitiva contra reservas cruzadas (aunque lleguen al mismo tiempo):
  constraint appointment_chair_no_overlap exclude using gist (
    chair_id with =, tstzrange(starts_at, blocks_until, '[)') with &&
  ) where (status in ('pendiente', 'confirmada', 'completada')),
  constraint appointment_barber_no_overlap exclude using gist (
    barber_id with =, tstzrange(starts_at, blocks_until, '[)') with &&
  ) where (status in ('pendiente', 'confirmada', 'completada'))
);

-- ---------- Eventos de disponibilidad (para Realtime sin exponer datos privados) ----------
create table if not exists public.availability_events (
  id         bigserial primary key,
  day        date,          -- NULL = el cambio puede afectar cualquier día
  chair_id   uuid,
  source     text not null,
  created_at timestamptz not null default now()
);

-- ---------- Límite de solicitudes ----------
create table if not exists public.rate_limit_hits (
  id     bigserial primary key,
  bucket text not null,
  hit_at timestamptz not null default now()
);

-- ---------- Índices ----------
create index if not exists idx_appointments_starts      on public.appointments (starts_at);
create index if not exists idx_appointments_customer    on public.appointments (customer_id);
create index if not exists idx_appointments_barber_time on public.appointments (barber_id, starts_at);
create index if not exists idx_appointments_chair_time  on public.appointments (chair_id, starts_at);
create index if not exists idx_appointments_pending     on public.appointments (pending_expires_at) where status = 'pendiente';
create index if not exists idx_exceptions_range         on public.schedule_exceptions using gist (tstzrange(starts_at, ends_at, '[)'));
create index if not exists idx_assign_barber            on public.barber_chair_assignments (barber_id);
create index if not exists idx_assign_chair             on public.barber_chair_assignments (chair_id);
create index if not exists idx_hours_barber             on public.barber_working_hours (barber_id, weekday);
create index if not exists idx_customers_user           on public.customers (user_id);
create index if not exists idx_rate_bucket              on public.rate_limit_hits (bucket, hit_at);
create index if not exists idx_av_events_created        on public.availability_events (created_at);

-- ---------- updated_at automático ----------
create or replace function public.tg_set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['barbers','chairs','services','customers','appointments','business_settings'] loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format('create trigger set_updated_at before update on public.%I
                    for each row execute function public.tg_set_updated_at()', t);
  end loop;
end $$;

-- ---------- Perfil automático al registrarse (siempre como cliente) ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'full_name', ''), 100), 'cliente')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
