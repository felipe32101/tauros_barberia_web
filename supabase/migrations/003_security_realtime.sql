-- =====================================================================
-- Tauros Barbería — 003: Row Level Security y Realtime
-- =====================================================================

alter table public.business_settings        enable row level security;
alter table public.profiles                 enable row level security;
alter table public.barbers                  enable row level security;
alter table public.chairs                   enable row level security;
alter table public.barber_chair_assignments enable row level security;
alter table public.services                 enable row level security;
alter table public.business_hours           enable row level security;
alter table public.barber_working_hours     enable row level security;
alter table public.schedule_exceptions      enable row level security;
alter table public.customers                enable row level security;
alter table public.appointments             enable row level security;
alter table public.availability_events      enable row level security;
alter table public.rate_limit_hits          enable row level security;  -- sin políticas: solo service_role

-- Limpia políticas previas para poder re-ejecutar el script
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- ---------- profiles ----------
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
-- El usuario solo puede cambiar su nombre, nunca su rol.
revoke update on public.profiles from anon, authenticated;
grant  update (full_name) on public.profiles to authenticated;
revoke insert, delete on public.profiles from anon, authenticated;

-- ---------- Datos públicos de solo lectura ----------
create policy services_public_read on public.services
  for select to anon, authenticated using (is_active or public.is_admin());
create policy business_hours_public_read on public.business_hours
  for select to anon, authenticated using (true);
create policy availability_events_public_read on public.availability_events
  for select to anon, authenticated using (true);

-- ---------- Solo administradores ----------
do $$
declare t text;
begin
  foreach t in array array[
    'business_settings', 'barbers', 'chairs', 'barber_chair_assignments', 'services',
    'business_hours', 'barber_working_hours', 'schedule_exceptions', 'customers', 'appointments'
  ] loop
    execute format('create policy %I on public.%I for all to authenticated
                    using (public.is_admin()) with check (public.is_admin())', t || '_admin_all', t);
  end loop;
end $$;

-- Las citas solo se crean/modifican mediante funciones (validación completa).
-- El admin puede editar notas internas directamente; el resto pasa por RPC.
revoke insert, update, delete on public.appointments from anon, authenticated;
grant  update (admin_notes) on public.appointments to authenticated;
revoke all on public.rate_limit_hits from anon, authenticated;
revoke insert, update, delete on public.availability_events from anon, authenticated;
revoke all on public.customers from anon;

-- =====================================================================
-- Realtime: cada cambio que afecta la disponibilidad deja un evento
-- (sin datos personales). Los clientes escuchan esta tabla y recalculan.
-- =====================================================================
create or replace function public.tg_availability_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare tz text := public._tz();
begin
  if tg_table_name = 'appointments' then
    if tg_op in ('INSERT', 'UPDATE') then
      insert into public.availability_events (day, chair_id, source)
      values ((new.starts_at at time zone tz)::date, new.chair_id, 'appointments');
    end if;
    if tg_op = 'DELETE' or (tg_op = 'UPDATE' and (old.starts_at <> new.starts_at or old.chair_id <> new.chair_id)) then
      insert into public.availability_events (day, chair_id, source)
      values ((old.starts_at at time zone tz)::date, old.chair_id, 'appointments');
    end if;
  else
    insert into public.availability_events (day, chair_id, source) values (null, null, tg_table_name);
  end if;
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'appointments', 'schedule_exceptions', 'barber_working_hours', 'business_hours',
    'barber_chair_assignments', 'chairs', 'barbers', 'services', 'business_settings'
  ] loop
    execute format('drop trigger if exists availability_event on public.%I', t);
    if t = 'appointments' then
      execute format('create trigger availability_event after insert or update or delete on public.%I
                      for each row execute function public.tg_availability_event()', t);
    else
      execute format('create trigger availability_event after insert or update or delete on public.%I
                      for each statement execute function public.tg_availability_event()', t);
    end if;
  end loop;
end $$;

-- Publicar la tabla de eventos en Supabase Realtime
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'availability_events') then
    alter publication supabase_realtime add table public.availability_events;
  end if;
exception when undefined_object then
  raise notice 'La publicación supabase_realtime no existe; actívala desde el panel de Supabase.';
end $$;

-- =====================================================================
-- (Opcional) liberar reservas pendientes caducadas cada 5 minutos.
-- Requiere la extensión pg_cron (Database → Extensions → pg_cron).
-- Las funciones de reserva ya lo hacen solas al ejecutarse, esto es extra.
-- =====================================================================
-- select cron.schedule('tauros-release-holds', '*/5 * * * *', $$select public.release_expired_holds()$$);
