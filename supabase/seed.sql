-- =====================================================================
-- Tauros Barbería — datos iniciales DE EJEMPLO
-- Los precios, nombres de barberos y horarios son de prueba.
-- Cámbialos desde el panel /admin antes de abrir al público.
-- =====================================================================

insert into public.business_settings (id) values (1) on conflict (id) do nothing;

-- Horario general de ejemplo: L-V 9:00-19:00, sábado 9:00-17:00, domingo cerrado
insert into public.business_hours (weekday, opens_at, closes_at, is_closed) values
  (1, '09:00', '19:00', false),
  (2, '09:00', '19:00', false),
  (3, '09:00', '19:00', false),
  (4, '09:00', '19:00', false),
  (5, '09:00', '19:00', false),
  (6, '09:00', '17:00', false),
  (7, null,    null,    true)
on conflict (weekday) do nothing;

-- Servicios de ejemplo (is_sample = true para identificarlos)
insert into public.services (name, description, price, duration_minutes, buffer_minutes, is_sample, sort_order) values
  ('Corte clásico',        'Corte a tijera o máquina con lavado y peinado. Precio de ejemplo.', 25000, 30, 5, true, 1),
  ('Corte + barba',        'Corte completo y perfilado de barba con toalla caliente. Precio de ejemplo.', 40000, 60, 5, true, 2),
  ('Arreglo de barba',     'Perfilado, rebajado y aceite para barba. Precio de ejemplo.', 18000, 30, 5, true, 3),
  ('Afeitado tradicional', 'Afeitado a navaja con toalla caliente. Precio de ejemplo.', 22000, 45, 5, true, 4),
  ('Corte infantil',       'Para menores de 12 años. Precio de ejemplo.', 20000, 30, 5, true, 5)
on conflict do nothing;

-- Sillas, barberos de ejemplo, asignaciones y horarios
do $$
declare
  i int;
  v_chair uuid;
  v_barber uuid;
  d int;
begin
  if exists (select 1 from public.chairs) then
    return;  -- ya hay datos, no duplicar
  end if;

  for i in 1..4 loop
    insert into public.chairs (name, sort_order) values ('Silla ' || i, i) returning id into v_chair;

    -- La silla 4 queda sin barbero para mostrar el estado "No disponible"
    continue when i = 4;

    insert into public.barbers (full_name) values ('Barbero de ejemplo ' || i) returning id into v_barber;
    insert into public.barber_chair_assignments (barber_id, chair_id, valid_from)
    values (v_barber, v_chair, current_date - 1);

    -- Lunes a viernes con pausa de almuerzo; sábado jornada continua
    for d in 1..5 loop
      insert into public.barber_working_hours (barber_id, weekday, starts_at, ends_at) values
        (v_barber, d, '09:00', '13:00'),
        (v_barber, d, '14:00', '19:00');
    end loop;
    insert into public.barber_working_hours (barber_id, weekday, starts_at, ends_at)
    values (v_barber, 6, '09:00', '17:00');
  end loop;
end $$;

-- =====================================================================
-- CREAR EL PRIMER ADMINISTRADOR
-- 1. Supabase → Authentication → Users → "Add user" (correo + contraseña).
-- 2. Ejecuta esto cambiando el correo:
--
-- update public.profiles set role = 'admin'
--  where id = (select id from auth.users where email = 'admin@taurosbarberia.com');
-- =====================================================================
