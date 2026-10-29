-- =====================================================================
-- Tauros Barbería — 002: lógica de disponibilidad, reservas y administración
-- Toda la validación de reservas vive aquí (PostgreSQL), no en JavaScript.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public._tz() returns text
language sql stable set search_path = public as $$
  select coalesce((select timezone from public.business_settings where id = 1), 'America/Bogota');
$$;

create or replace function public._require_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;
end $$;

-- Libera reservas pendientes caducadas y limpia tablas auxiliares.
create or replace function public.release_expired_holds() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.appointments
     set status = 'cancelada', cancelled_at = now(), cancel_reason = 'Reserva pendiente caducada'
   where status = 'pendiente'
     and pending_expires_at is not null
     and pending_expires_at < now();
  get diagnostics n = row_count;
  delete from public.availability_events where created_at < now() - interval '2 days';
  delete from public.rate_limit_hits    where hit_at     < now() - interval '1 day';
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Núcleo: franjas libres de un día.
-- Considera: horario general, horario del barbero (con pausas), asignación
-- barbero↔silla vigente, excepciones (cierres, festivos, vacaciones,
-- mantenimiento), citas que bloquean (silla o barbero) y margen de preparación.
-- ---------------------------------------------------------------------
create or replace function public._available_slots(
  p_date                date,
  p_duration            int,
  p_buffer              int,
  p_chair_id            uuid        default null,
  p_exclude_appointment uuid        default null,
  p_min_start           timestamptz default null
)
returns table (chair_id uuid, barber_id uuid, slot_start timestamptz, slot_end timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  s       public.business_settings%rowtype;
  bh      public.business_hours%rowtype;
  v_dow   int := extract(isodow from p_date);
  v_open  timestamptz;
  v_close timestamptz;
  v_step  interval;
  v_min   timestamptz := coalesce(p_min_start, now());
  r record;
  w record;
  v_t     timestamptz;
  v_end   timestamptz;
  v_block timestamptz;
begin
  select * into s from public.business_settings where id = 1;
  select * into bh from public.business_hours where weekday = v_dow;
  if not found or bh.is_closed then
    return;
  end if;

  v_open  := (p_date + bh.opens_at)  at time zone s.timezone;
  v_close := (p_date + bh.closes_at) at time zone s.timezone;
  v_step  := make_interval(mins => s.slot_interval_minutes);

  for r in
    select c.id as c_id, a.barber_id as b_id
      from public.chairs c
      join public.barber_chair_assignments a
        on a.chair_id = c.id
       and p_date >= a.valid_from
       and (a.valid_until is null or p_date < a.valid_until)
      join public.barbers b on b.id = a.barber_id and b.is_active
     where c.is_active
       and (p_chair_id is null or c.id = p_chair_id)
  loop
    for w in
      select greatest((p_date + h.starts_at) at time zone s.timezone, v_open)  as ws,
             least   ((p_date + h.ends_at)   at time zone s.timezone, v_close) as we
        from public.barber_working_hours h
       where h.barber_id = r.b_id and h.weekday = v_dow and h.is_active
       order by h.starts_at
    loop
      continue when w.we <= w.ws;
      v_t := w.ws;
      loop
        v_end := v_t + make_interval(mins => p_duration);
        exit when v_end > w.we;
        v_block := v_end + make_interval(mins => p_buffer);

        if v_t >= v_min
           and not exists (
             select 1 from public.schedule_exceptions e
              where tstzrange(e.starts_at, e.ends_at, '[)') && tstzrange(v_t, v_end, '[)')
                and (e.barber_id is null or e.barber_id = r.b_id)
                and (e.chair_id  is null or e.chair_id  = r.c_id))
           and not exists (
             select 1 from public.appointments ap
              where ap.status in ('pendiente', 'confirmada', 'completada')
                and not (ap.status = 'pendiente' and ap.pending_expires_at is not null and ap.pending_expires_at < now())
                and (ap.chair_id = r.c_id or ap.barber_id = r.b_id)
                and (p_exclude_appointment is null or ap.id <> p_exclude_appointment)
                and tstzrange(ap.starts_at, ap.blocks_until, '[)') && tstzrange(v_t, v_block, '[)'))
        then
          chair_id   := r.c_id;
          barber_id  := r.b_id;
          slot_start := v_t;
          slot_end   := v_end;
          return next;
        end if;

        v_t := v_t + v_step;
      end loop;
    end loop;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Disponibilidad de un día por silla (sin datos personales).
-- ---------------------------------------------------------------------
create or replace function public._availability_json(
  p_date                date,
  p_duration            int,
  p_buffer              int,
  p_min_start           timestamptz,
  p_exclude_appointment uuid default null
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s        public.business_settings%rowtype;
  bh       public.business_hours%rowtype;
  v_dow    int := extract(isodow from p_date);
  v_closed boolean;
  v_dstart timestamptz;
  v_dend   timestamptz;
  r        record;
  v_slots  jsonb;
  v_busy   jsonb;
  v_status text;
  v_reason text;
  v_out    jsonb := '[]'::jsonb;
begin
  select * into s from public.business_settings where id = 1;
  select * into bh from public.business_hours where weekday = v_dow;
  v_closed := (not found) or bh.is_closed;
  v_dstart := p_date::timestamp at time zone s.timezone;
  v_dend   := (p_date + 1)::timestamp at time zone s.timezone;

  for r in
    select c.id, c.name, c.sort_order,
           b.id as barber_id, b.full_name as barber_name, b.photo_url
      from public.chairs c
      left join public.barber_chair_assignments a
        on a.chair_id = c.id
       and p_date >= a.valid_from
       and (a.valid_until is null or p_date < a.valid_until)
      left join public.barbers b on b.id = a.barber_id and b.is_active
     where c.is_active
     order by c.sort_order, c.name
  loop
    select coalesce(jsonb_agg(x.slot_start order by x.slot_start), '[]'::jsonb)
      into v_slots
      from public._available_slots(p_date, p_duration, p_buffer, r.id, p_exclude_appointment, p_min_start) x;

    -- Franjas ocupadas (solo horas, nunca datos del cliente)
    select coalesce(jsonb_agg(jsonb_build_array(ap.starts_at, ap.blocks_until) order by ap.starts_at), '[]'::jsonb)
      into v_busy
      from public.appointments ap
     where ap.status in ('pendiente', 'confirmada', 'completada')
       and (p_exclude_appointment is null or ap.id <> p_exclude_appointment)
       and (ap.chair_id = r.id or (r.barber_id is not null and ap.barber_id = r.barber_id))
       and ap.starts_at < v_dend and ap.blocks_until > v_dstart;

    v_reason := null;
    if r.barber_id is null then
      v_status := 'no_disponible'; v_reason := 'Sin barbero asignado';
    elsif v_closed then
      v_status := 'no_disponible'; v_reason := 'La barbería no abre este día';
    elsif jsonb_array_length(v_slots) > 0 then
      v_status := 'disponible';
    elsif not exists (select 1 from public.barber_working_hours h
                       where h.barber_id = r.barber_id and h.weekday = v_dow and h.is_active) then
      v_status := 'no_disponible'; v_reason := 'El barbero no trabaja este día';
    elsif jsonb_array_length(v_busy) > 0 then
      v_status := 'ocupada'; v_reason := 'Sin horarios libres';
    elsif exists (select 1 from public.schedule_exceptions e
                   where tstzrange(e.starts_at, e.ends_at, '[)') && tstzrange(v_dstart, v_dend, '[)')
                     and (e.barber_id is null or e.barber_id = r.barber_id)
                     and (e.chair_id  is null or e.chair_id  = r.id)) then
      v_status := 'no_disponible'; v_reason := 'Bloqueada';
    else
      v_status := 'no_disponible'; v_reason := 'Fuera de horario';
    end if;

    v_out := v_out || jsonb_build_object(
      'chair_id',     r.id,
      'chair_name',   r.name,
      'barber_id',    r.barber_id,
      'barber_name',  r.barber_name,
      'barber_photo', r.photo_url,
      'status',       v_status,
      'reason',       v_reason,
      'slots',        v_slots,
      'busy',         v_busy,
      'next_slot',    v_slots->0
    );
  end loop;

  return v_out;
end $$;

-- ---------------------------------------------------------------------
-- Datos de una cita con nombres legibles.
-- ---------------------------------------------------------------------
create or replace function public._appointment_json(p_id uuid, p_with_contact boolean default true)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id',                a.id,
    'booking_reference', a.booking_reference,
    'status',            a.status,
    'starts_at',         a.starts_at,
    'ends_at',           a.ends_at,
    'service_id',        a.service_id,
    'service_name',      a.service_name_snapshot,
    'price',             a.service_price_snapshot,
    'duration_minutes',  a.service_duration_snapshot,
    'chair_id',          a.chair_id,
    'chair_name',        ch.name,
    'barber_id',         a.barber_id,
    'barber_name',       b.full_name,
    'customer_name',     case when p_with_contact then c.full_name end,
    'customer_phone',    case when p_with_contact then c.phone end,
    'customer_email',    case when p_with_contact then c.email end,
    'customer_notes',    case when p_with_contact then a.customer_notes end,
    'pending_expires_at',a.pending_expires_at,
    'created_at',        a.created_at
  )
  from public.appointments a
  join public.customers c on c.id = a.customer_id
  join public.barbers  b on b.id = a.barber_id
  join public.chairs  ch on ch.id = a.chair_id
  where a.id = p_id;
$$;

-- ---------------------------------------------------------------------
-- ¿Una cita sigue encajando en el horario actual? Devuelve el motivo o NULL.
-- ---------------------------------------------------------------------
create or replace function public._appointment_issue(p_id uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  a    public.appointments%rowtype;
  bh   public.business_hours%rowtype;
  tz   text := public._tz();
  d    date;
  dow  int;
begin
  select * into a from public.appointments where id = p_id;
  if not found then return null; end if;
  d   := (a.starts_at at time zone tz)::date;
  dow := extract(isodow from d);

  select * into bh from public.business_hours where weekday = dow;
  if not found or bh.is_closed then
    return 'La barbería queda cerrada ese día';
  end if;
  if a.starts_at < (d + bh.opens_at) at time zone tz or a.ends_at > (d + bh.closes_at) at time zone tz then
    return 'Queda fuera del horario de la barbería';
  end if;
  if not exists (select 1 from public.barbers where id = a.barber_id and is_active) then
    return 'El barbero queda inactivo';
  end if;
  if not exists (select 1 from public.chairs where id = a.chair_id and is_active) then
    return 'La silla queda inactiva';
  end if;
  if not exists (select 1 from public.barber_chair_assignments x
                  where x.barber_id = a.barber_id and x.chair_id = a.chair_id
                    and d >= x.valid_from and (x.valid_until is null or d < x.valid_until)) then
    return 'El barbero ya no está asignado a esa silla';
  end if;
  if not exists (select 1 from public.barber_working_hours h
                  where h.barber_id = a.barber_id and h.weekday = dow and h.is_active
                    and a.starts_at >= (d + h.starts_at) at time zone tz
                    and a.ends_at   <= (d + h.ends_at)   at time zone tz) then
    return 'Queda fuera del horario del barbero';
  end if;
  if exists (select 1 from public.schedule_exceptions e
              where tstzrange(e.starts_at, e.ends_at, '[)') && tstzrange(a.starts_at, a.ends_at, '[)')
                and (e.barber_id is null or e.barber_id = a.barber_id)
                and (e.chair_id  is null or e.chair_id  = a.chair_id)) then
    return 'Se cruza con un cierre o bloqueo';
  end if;
  return null;
end $$;

-- Citas futuras activas que dejarían de encajar (filtro opcional por barbero o silla).
create or replace function public._future_conflicts(p_barber_id uuid default null, p_chair_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id,
           'booking_reference', a.booking_reference,
           'starts_at', a.starts_at,
           'customer_name', c.full_name,
           'barber_name', b.full_name,
           'chair_name', ch.name,
           'issue', x.issue) order by a.starts_at), '[]'::jsonb)
    from public.appointments a
    join public.customers c on c.id = a.customer_id
    join public.barbers  b on b.id = a.barber_id
    join public.chairs  ch on ch.id = a.chair_id
    cross join lateral (select public._appointment_issue(a.id) as issue) x
   where a.status in ('pendiente', 'confirmada')
     and a.starts_at > now()
     and x.issue is not null
     and ((p_barber_id is null and p_chair_id is null)
          or a.barber_id = p_barber_id
          or a.chair_id  = p_chair_id);
$$;

-- ---------------------------------------------------------------------
-- Crear cita (uso interno: web pública y administración)
-- ---------------------------------------------------------------------
create or replace function public._create_appointment(
  p_service_id uuid,
  p_chair_id   uuid,
  p_starts_at  timestamptz,
  p_full_name  text,
  p_phone      text,
  p_email      text,
  p_notes      text,
  p_user_id    uuid,
  p_created_by text,
  p_status     public.appointment_status default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  s          public.business_settings%rowtype;
  svc        public.services%rowtype;
  v_name     text;
  v_phone    text;
  v_email    text;
  v_notes    text;
  v_date     date;
  v_min      timestamptz;
  v_barber   uuid;
  v_active   int;
  v_customer uuid;
  v_status   public.appointment_status;
  v_expires  timestamptz;
  v_ref      text;
  v_token    text;
  v_end      timestamptz;
  v_id       uuid;
begin
  perform public.release_expired_holds();
  select * into s from public.business_settings where id = 1;

  -- Normalizar y validar datos
  v_name := btrim(regexp_replace(coalesce(p_full_name, ''), '\s+', ' ', 'g'));
  if char_length(v_name) < 3 or char_length(v_name) > 100 then raise exception 'INVALID_NAME'; end if;
  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  if v_phone !~ '^\+?[0-9]{7,15}$' then raise exception 'INVALID_PHONE'; end if;
  v_email := nullif(lower(btrim(coalesce(p_email, ''))), '');
  if v_email is not null and v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'INVALID_EMAIL'; end if;
  v_notes := nullif(btrim(coalesce(p_notes, '')), '');
  if v_notes is not null and char_length(v_notes) > 500 then raise exception 'INVALID_NOTES'; end if;

  select * into svc from public.services where id = p_service_id and is_active;
  if not found then raise exception 'SERVICE_UNAVAILABLE'; end if;

  if p_starts_at is null or p_starts_at <= now() then raise exception 'SLOT_IN_PAST'; end if;
  v_date := (p_starts_at at time zone s.timezone)::date;
  if p_created_by = 'cliente' and v_date > (now() at time zone s.timezone)::date + s.max_days_ahead then
    raise exception 'DATE_TOO_FAR';
  end if;

  -- Serializa reservas de la misma silla (la restricción EXCLUDE es la red final).
  perform pg_advisory_xact_lock(hashtextextended('chair:' || p_chair_id::text, 0));

  v_min := case when p_created_by = 'admin' then now()
                else now() + make_interval(mins => s.min_advance_minutes) end;

  select x.barber_id into v_barber
    from public._available_slots(v_date, svc.duration_minutes, svc.buffer_minutes, p_chair_id, null, v_min) x
   where x.slot_start = p_starts_at
   limit 1;
  if v_barber is null then raise exception 'SLOT_UNAVAILABLE'; end if;

  if p_created_by = 'cliente' then
    select count(*) into v_active
      from public.appointments a join public.customers c on c.id = a.customer_id
     where c.phone = v_phone and a.status in ('pendiente', 'confirmada') and a.starts_at > now();
    if v_active >= s.max_active_bookings_per_phone then raise exception 'TOO_MANY_BOOKINGS'; end if;
  end if;

  insert into public.customers (full_name, phone, email, user_id)
  values (v_name, v_phone, v_email, p_user_id)
  on conflict (phone) do update
     set full_name = excluded.full_name,
         email     = coalesce(excluded.email, public.customers.email),
         user_id   = coalesce(public.customers.user_id, excluded.user_id)
  returning id into v_customer;

  v_status := coalesce(p_status, case when s.auto_confirm then 'confirmada' else 'pendiente' end::public.appointment_status);
  if v_status not in ('pendiente', 'confirmada') then raise exception 'INVALID_STATUS'; end if;
  if v_status = 'pendiente' and p_created_by = 'cliente' and s.pending_hold_minutes > 0 then
    v_expires := now() + make_interval(mins => s.pending_hold_minutes);
  end if;

  loop
    -- Referencia corta y legible (sin 0/O/1/I/L para evitar confusiones al dictarla)
    v_ref := 'TAU-' || substr(translate(upper(encode(gen_random_bytes(12), 'base64')), '+/=0O1IL', ''), 1, 6);
    exit when char_length(v_ref) = 10
          and not exists (select 1 from public.appointments where booking_reference = v_ref);
  end loop;
  v_token := encode(gen_random_bytes(24), 'hex');   -- 192 bits, se entrega una sola vez
  v_end   := p_starts_at + make_interval(mins => svc.duration_minutes);

  begin
    insert into public.appointments (
      booking_reference, access_token_hash, customer_id, barber_id, chair_id, service_id,
      starts_at, ends_at, blocks_until, status, pending_expires_at, customer_notes,
      service_name_snapshot, service_price_snapshot, service_duration_snapshot, service_buffer_snapshot,
      created_by
    ) values (
      v_ref, encode(digest(v_token, 'sha256'), 'hex'), v_customer, v_barber, p_chair_id, svc.id,
      p_starts_at, v_end, v_end + make_interval(mins => svc.buffer_minutes), v_status, v_expires, v_notes,
      svc.name, svc.price, svc.duration_minutes, svc.buffer_minutes,
      p_created_by
    ) returning id into v_id;
  exception when exclusion_violation then
    raise exception 'SLOT_TAKEN';
  end;

  return public._appointment_json(v_id, true) || jsonb_build_object('access_token', v_token);
end $$;

-- Reprogramar (uso interno). Mantiene la duración y el precio confirmados.
create or replace function public._reschedule_appointment(
  p_id         uuid,
  p_chair_id   uuid,
  p_starts_at  timestamptz,
  p_by         text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s        public.business_settings%rowtype;
  a        public.appointments%rowtype;
  v_date   date;
  v_min    timestamptz;
  v_barber uuid;
  v_end    timestamptz;
begin
  perform public.release_expired_holds();
  select * into s from public.business_settings where id = 1;
  select * into a from public.appointments where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if a.status not in ('pendiente', 'confirmada') then raise exception 'NOT_MODIFIABLE'; end if;
  if p_starts_at is null or p_starts_at <= now() then raise exception 'SLOT_IN_PAST'; end if;

  v_date := (p_starts_at at time zone s.timezone)::date;
  if p_by = 'cliente' and v_date > (now() at time zone s.timezone)::date + s.max_days_ahead then
    raise exception 'DATE_TOO_FAR';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('chair:' || p_chair_id::text, 0));
  v_min := case when p_by = 'admin' then now() else now() + make_interval(mins => s.min_advance_minutes) end;

  select x.barber_id into v_barber
    from public._available_slots(v_date, a.service_duration_snapshot, a.service_buffer_snapshot,
                                 p_chair_id, a.id, v_min) x
   where x.slot_start = p_starts_at
   limit 1;
  if v_barber is null then raise exception 'SLOT_UNAVAILABLE'; end if;

  v_end := p_starts_at + make_interval(mins => a.service_duration_snapshot);
  begin
    update public.appointments
       set chair_id     = p_chair_id,
           barber_id    = v_barber,
           starts_at    = p_starts_at,
           ends_at      = v_end,
           blocks_until = v_end + make_interval(mins => a.service_buffer_snapshot)
     where id = a.id;
  exception when exclusion_violation then
    raise exception 'SLOT_TAKEN';
  end;

  return public._appointment_json(a.id, true);
end $$;

-- =====================================================================
-- API PÚBLICA (anon y authenticated)
-- =====================================================================

create or replace function public.get_public_info() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'business_name',    s.business_name,
    'timezone',         s.timezone,
    'currency',         s.currency,
    'slot_interval',    s.slot_interval_minutes,
    'max_days_ahead',   s.max_days_ahead,
    'cancel_min_hours', s.cancel_min_hours,
    'auto_confirm',     s.auto_confirm,
    'today',            (now() at time zone s.timezone)::date,
    'hours', (select coalesce(jsonb_agg(jsonb_build_object(
                'weekday', h.weekday, 'opens_at', h.opens_at, 'closes_at', h.closes_at, 'is_closed', h.is_closed)
                order by h.weekday), '[]'::jsonb) from public.business_hours h)
  )
  from public.business_settings s where s.id = 1;
$$;

-- Disponibilidad de un día para un servicio.
create or replace function public.get_availability(p_date date, p_service_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s       public.business_settings%rowtype;
  svc     public.services%rowtype;
  v_today date;
begin
  perform public.release_expired_holds();
  select * into s from public.business_settings where id = 1;
  select * into svc from public.services where id = p_service_id and is_active;
  if not found then raise exception 'SERVICE_UNAVAILABLE'; end if;

  v_today := (now() at time zone s.timezone)::date;
  if p_date is null or p_date < v_today or p_date > v_today + s.max_days_ahead then
    raise exception 'DATE_OUT_OF_RANGE';
  end if;

  return jsonb_build_object(
    'date', p_date,
    'timezone', s.timezone,
    'slot_interval', s.slot_interval_minutes,
    'service', jsonb_build_object('id', svc.id, 'name', svc.name, 'price', svc.price,
                                  'duration_minutes', svc.duration_minutes, 'buffer_minutes', svc.buffer_minutes),
    'chairs', public._availability_json(p_date, svc.duration_minutes, svc.buffer_minutes,
                                        now() + make_interval(mins => s.min_advance_minutes))
  );
end $$;

-- Resumen para el calendario: cuántas franjas hay cada día.
create or replace function public.get_calendar_summary(p_from date, p_to date, p_service_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s       public.business_settings%rowtype;
  svc     public.services%rowtype;
  v_today date;
  v_from  date;
  v_to    date;
  d       date;
  n       int;
  v_out   jsonb := '[]'::jsonb;
begin
  select * into s from public.business_settings where id = 1;
  select * into svc from public.services where id = p_service_id and is_active;
  if not found then raise exception 'SERVICE_UNAVAILABLE'; end if;

  v_today := (now() at time zone s.timezone)::date;
  v_from  := greatest(p_from, v_today);
  v_to    := least(p_to, v_today + s.max_days_ahead, v_from + 62);

  d := v_from;
  while d <= v_to loop
    select count(*) into n
      from public._available_slots(d, svc.duration_minutes, svc.buffer_minutes, null, null,
                                   now() + make_interval(mins => s.min_advance_minutes));
    v_out := v_out || jsonb_build_object('date', d, 'slots', n);
    d := d + 1;
  end loop;
  return v_out;
end $$;

-- =====================================================================
-- SOLO SERVIDOR (service_role, llamadas desde /api en Vercel)
-- =====================================================================

create or replace function public.register_rate_hit(p_bucket text, p_limit int, p_window_minutes int)
returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform pg_advisory_xact_lock(hashtextextended('rate:' || p_bucket, 0));
  select count(*) into n from public.rate_limit_hits
   where bucket = p_bucket and hit_at > now() - make_interval(mins => p_window_minutes);
  if n >= p_limit then return false; end if;
  insert into public.rate_limit_hits (bucket) values (p_bucket);
  return true;
end $$;

create or replace function public.book_appointment(
  p_service_id uuid, p_chair_id uuid, p_starts_at timestamptz,
  p_full_name text, p_phone text, p_email text default null, p_notes text default null,
  p_user_id uuid default null
) returns jsonb
language sql security definer set search_path = public as $$
  select public._create_appointment(p_service_id, p_chair_id, p_starts_at, p_full_name, p_phone,
                                    p_email, p_notes, p_user_id, 'cliente', null);
$$;

create or replace function public._find_by_token(p_ref text, p_token text) returns uuid
language sql stable security definer set search_path = public, extensions as $$
  select id from public.appointments
   where booking_reference = upper(btrim(p_ref))
     and access_token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

create or replace function public._can_customer_modify(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a.status in ('pendiente', 'confirmada')
     and a.starts_at - now() >= make_interval(hours => s.cancel_min_hours)
    from public.appointments a, public.business_settings s
   where a.id = p_id and s.id = 1;
$$;

create or replace function public.get_appointment_by_token(p_ref text, p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.release_expired_holds();
  v_id := public._find_by_token(p_ref, p_token);
  if v_id is null then raise exception 'NOT_FOUND'; end if;
  return public._appointment_json(v_id, true) || jsonb_build_object('can_modify', public._can_customer_modify(v_id));
end $$;

create or replace function public.cancel_appointment_by_token(p_ref text, p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := public._find_by_token(p_ref, p_token);
  if v_id is null then raise exception 'NOT_FOUND'; end if;
  perform 1 from public.appointments where id = v_id for update;
  if not public._can_customer_modify(v_id) then raise exception 'NOT_MODIFIABLE'; end if;
  update public.appointments
     set status = 'cancelada', cancelled_at = now(), cancel_reason = 'Cancelada por el cliente'
   where id = v_id;
  return public._appointment_json(v_id, true) || jsonb_build_object('can_modify', false);
end $$;

create or replace function public.reschedule_appointment_by_token(
  p_ref text, p_token text, p_chair_id uuid, p_starts_at timestamptz
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := public._find_by_token(p_ref, p_token);
  if v_id is null then raise exception 'NOT_FOUND'; end if;
  if not public._can_customer_modify(v_id) then raise exception 'NOT_MODIFIABLE'; end if;
  return public._reschedule_appointment(v_id, p_chair_id, p_starts_at, 'cliente')
         || jsonb_build_object('can_modify', public._can_customer_modify(v_id));
end $$;

-- Disponibilidad para reprogramar una cita de invitado (excluye la propia cita).
create or replace function public.get_reschedule_availability(p_ref text, p_token text, p_date date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id    uuid;
  a       public.appointments%rowtype;
  s       public.business_settings%rowtype;
  v_today date;
begin
  v_id := public._find_by_token(p_ref, p_token);
  if v_id is null then raise exception 'NOT_FOUND'; end if;
  select * into a from public.appointments where id = v_id;
  select * into s from public.business_settings where id = 1;
  v_today := (now() at time zone s.timezone)::date;
  if p_date is null or p_date < v_today or p_date > v_today + s.max_days_ahead then
    raise exception 'DATE_OUT_OF_RANGE';
  end if;
  return jsonb_build_object(
    'date', p_date, 'timezone', s.timezone, 'slot_interval', s.slot_interval_minutes,
    'service', jsonb_build_object('id', a.service_id, 'name', a.service_name_snapshot,
                                  'price', a.service_price_snapshot,
                                  'duration_minutes', a.service_duration_snapshot,
                                  'buffer_minutes', a.service_buffer_snapshot),
    'chairs', public._availability_json(p_date, a.service_duration_snapshot, a.service_buffer_snapshot,
                                        now() + make_interval(mins => s.min_advance_minutes), a.id));
end $$;

-- =====================================================================
-- CLIENTE AUTENTICADO
-- =====================================================================

create or replace function public.my_appointments() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public._appointment_json(a.id, true)
                            || jsonb_build_object('can_modify', public._can_customer_modify(a.id))
                            order by a.starts_at desc), '[]'::jsonb)
    from public.appointments a
    join public.customers c on c.id = a.customer_id
   where auth.uid() is not null and c.user_id = auth.uid();
$$;

create or replace function public.cancel_my_appointment(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.appointments a join public.customers c on c.id = a.customer_id
                  where a.id = p_id and auth.uid() is not null and c.user_id = auth.uid()) then
    raise exception 'NOT_FOUND';
  end if;
  perform 1 from public.appointments where id = p_id for update;
  if not public._can_customer_modify(p_id) then raise exception 'NOT_MODIFIABLE'; end if;
  update public.appointments
     set status = 'cancelada', cancelled_at = now(), cancel_reason = 'Cancelada por el cliente'
   where id = p_id;
  return public._appointment_json(p_id, true);
end $$;

-- =====================================================================
-- ADMINISTRACIÓN (requiere profiles.role = 'admin')
-- =====================================================================

create or replace function public.admin_availability(
  p_date date, p_service_id uuid default null, p_exclude_appointment uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dur int; v_buf int;
begin
  perform public._require_admin();
  perform public.release_expired_holds();
  if p_exclude_appointment is not null then
    select service_duration_snapshot, service_buffer_snapshot into v_dur, v_buf
      from public.appointments where id = p_exclude_appointment;
  else
    select duration_minutes, buffer_minutes into v_dur, v_buf
      from public.services where id = p_service_id and is_active;
  end if;
  if v_dur is null then raise exception 'SERVICE_UNAVAILABLE'; end if;
  return jsonb_build_object('date', p_date, 'timezone', public._tz(),
    'chairs', public._availability_json(p_date, v_dur, v_buf, now(), p_exclude_appointment));
end $$;

create or replace function public.admin_create_appointment(
  p_service_id uuid, p_chair_id uuid, p_starts_at timestamptz,
  p_full_name text, p_phone text, p_email text default null, p_notes text default null,
  p_status public.appointment_status default 'confirmada'
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._require_admin();
  return public._create_appointment(p_service_id, p_chair_id, p_starts_at, p_full_name, p_phone,
                                    p_email, p_notes, null, 'admin', p_status) - 'access_token';
end $$;

create or replace function public.admin_reschedule_appointment(p_id uuid, p_chair_id uuid, p_starts_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._require_admin();
  return public._reschedule_appointment(p_id, p_chair_id, p_starts_at, 'admin');
end $$;

create or replace function public.admin_set_appointment_status(
  p_id uuid, p_status public.appointment_status, p_reason text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a public.appointments%rowtype;
  v_ok boolean;
begin
  perform public._require_admin();
  select * into a from public.appointments where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  v_ok := case a.status
    when 'pendiente'  then p_status in ('confirmada', 'cancelada')
    when 'confirmada' then p_status in ('cancelada', 'completada', 'no_asistio')
    else false
  end;
  if not v_ok then raise exception 'INVALID_TRANSITION'; end if;
  if p_status in ('completada', 'no_asistio') and a.starts_at > now() then
    raise exception 'NOT_STARTED_YET';
  end if;

  begin
    update public.appointments
       set status = p_status,
           pending_expires_at = null,
           cancelled_at  = case when p_status = 'cancelada' then now() end,
           cancel_reason = case when p_status = 'cancelada' then coalesce(nullif(btrim(p_reason), ''), 'Cancelada por la barbería') end
     where id = p_id;
  exception when exclusion_violation then
    raise exception 'SLOT_TAKEN';
  end;
  return public._appointment_json(p_id, true);
end $$;

create or replace function public.admin_list_appointments(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tz text := public._tz();
begin
  perform public._require_admin();
  if p_to < p_from or p_to - p_from > 62 then raise exception 'RANGE_TOO_LARGE'; end if;
  return (
    select coalesce(jsonb_agg(public._appointment_json(a.id, true)
                              || jsonb_build_object('created_by', a.created_by, 'cancel_reason', a.cancel_reason,
                                                    'admin_notes', a.admin_notes)
                              order by a.starts_at), '[]'::jsonb)
      from public.appointments a
     where a.starts_at >= p_from::timestamp at time zone tz
       and a.starts_at <  (p_to + 1)::timestamp at time zone tz
  );
end $$;

create or replace function public.admin_dashboard(p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  tz      text := public._tz();
  v_date  date;
  v_from  timestamptz;
  v_to    timestamptz;
  v_dow   int;
  v_occ   jsonb;
  v_next  jsonb;
begin
  perform public._require_admin();
  v_date := coalesce(p_date, (now() at time zone tz)::date);
  v_from := v_date::timestamp at time zone tz;
  v_to   := (v_date + 1)::timestamp at time zone tz;
  v_dow  := extract(isodow from v_date);

  -- Ocupación por silla: minutos reservados / minutos de trabajo del barbero asignado
  select coalesce(jsonb_agg(jsonb_build_object(
           'chair_id', c.id, 'chair_name', c.name, 'barber_name', b.full_name,
           'booked_minutes', coalesce(bk.mins, 0),
           'available_minutes', coalesce(wk.mins, 0),
           'appointments', coalesce(bk.n, 0)) order by c.sort_order, c.name), '[]'::jsonb)
    into v_occ
    from public.chairs c
    left join public.barber_chair_assignments a
      on a.chair_id = c.id and v_date >= a.valid_from and (a.valid_until is null or v_date < a.valid_until)
    left join public.barbers b on b.id = a.barber_id and b.is_active
    left join lateral (
      select sum(extract(epoch from (ap.ends_at - ap.starts_at)) / 60)::int as mins, count(*)::int as n
        from public.appointments ap
       where ap.chair_id = c.id and ap.status in ('pendiente', 'confirmada', 'completada')
         and ap.starts_at >= v_from and ap.starts_at < v_to
    ) bk on true
    left join lateral (
      select sum(extract(epoch from (least(h.ends_at, bh.closes_at) - greatest(h.starts_at, bh.opens_at))) / 60)::int as mins
        from public.barber_working_hours h
        join public.business_hours bh on bh.weekday = h.weekday and not bh.is_closed
       where h.barber_id = b.id and h.weekday = v_dow and h.is_active
         and least(h.ends_at, bh.closes_at) > greatest(h.starts_at, bh.opens_at)
    ) wk on true
   where c.is_active;

  select coalesce(jsonb_agg(public._appointment_json(x.id, true) order by x.starts_at), '[]'::jsonb)
    into v_next
    from (select id, starts_at from public.appointments
           where status in ('pendiente', 'confirmada') and starts_at >= now()
           order by starts_at limit 8) x;

  return jsonb_build_object(
    'date', v_date,
    'today_total',     (select count(*) from public.appointments where starts_at >= v_from and starts_at < v_to and status <> 'cancelada'),
    'today_confirmed', (select count(*) from public.appointments where starts_at >= v_from and starts_at < v_to and status = 'confirmada'),
    'today_completed', (select count(*) from public.appointments where starts_at >= v_from and starts_at < v_to and status = 'completada'),
    'today_cancelled', (select count(*) from public.appointments where starts_at >= v_from and starts_at < v_to and status = 'cancelada'),
    'pending',         (select count(*) from public.appointments where status = 'pendiente' and starts_at >= now()),
    'active_barbers',  (select count(*) from public.barbers where is_active),
    'active_chairs',   (select count(*) from public.chairs where is_active),
    'occupancy', v_occ,
    'upcoming',  v_next
  );
end $$;

-- ---------- Cambios de horario con advertencia de citas afectadas ----------
-- Todas estas funciones aplican el cambio, revisan las citas futuras y, si hay
-- afectadas y p_confirm = false, deshacen el cambio y devuelven la lista.

create or replace function public.admin_save_business_hours(p_hours jsonb, p_confirm boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_conf jsonb := '[]'::jsonb;
  h jsonb;
begin
  perform public._require_admin();
  begin
    for h in select * from jsonb_array_elements(p_hours) loop
      insert into public.business_hours (weekday, opens_at, closes_at, is_closed)
      values ((h->>'weekday')::smallint,
              nullif(h->>'opens_at', '')::time,
              nullif(h->>'closes_at', '')::time,
              coalesce((h->>'is_closed')::boolean, false))
      on conflict (weekday) do update
         set opens_at = excluded.opens_at, closes_at = excluded.closes_at, is_closed = excluded.is_closed;
    end loop;

    v_conf := public._future_conflicts();
    if jsonb_array_length(v_conf) > 0 and not p_confirm then
      raise exception 'NEEDS_CONFIRM';
    end if;
  exception when raise_exception then
    if sqlerrm = 'NEEDS_CONFIRM' then
      return jsonb_build_object('saved', false, 'conflicts', v_conf);
    end if;
    raise;
  end;
  return jsonb_build_object('saved', true, 'conflicts', v_conf);
end $$;

-- p_hours: [{ "weekday": 1, "starts_at": "09:00", "ends_at": "13:00" }, ...]
create or replace function public.admin_save_barber_hours(p_barber_id uuid, p_hours jsonb, p_confirm boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_conf jsonb := '[]'::jsonb;
  h  jsonb;
  bh public.business_hours%rowtype;
  v_wd smallint; v_s time; v_e time;
begin
  perform public._require_admin();
  if not exists (select 1 from public.barbers where id = p_barber_id) then raise exception 'NOT_FOUND'; end if;
  begin
    delete from public.barber_working_hours where barber_id = p_barber_id;
    for h in select * from jsonb_array_elements(p_hours) loop
      v_wd := (h->>'weekday')::smallint;
      v_s  := (h->>'starts_at')::time;
      v_e  := (h->>'ends_at')::time;
      select * into bh from public.business_hours where weekday = v_wd;
      if not found or bh.is_closed or v_s < bh.opens_at or v_e > bh.closes_at then
        raise exception 'HOURS_OUTSIDE_BUSINESS';
      end if;
      insert into public.barber_working_hours (barber_id, weekday, starts_at, ends_at)
      values (p_barber_id, v_wd, v_s, v_e);
    end loop;

    v_conf := public._future_conflicts(p_barber_id, null);
    if jsonb_array_length(v_conf) > 0 and not p_confirm then
      raise exception 'NEEDS_CONFIRM';
    end if;
  exception
    when raise_exception then
      if sqlerrm = 'NEEDS_CONFIRM' then
        return jsonb_build_object('saved', false, 'conflicts', v_conf);
      end if;
      raise;
    when exclusion_violation then
      raise exception 'HOURS_OVERLAP';
  end;
  return jsonb_build_object('saved', true, 'conflicts', v_conf);
end $$;

create or replace function public.admin_create_exception(
  p_barber_id uuid, p_chair_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_type public.exception_type, p_reason text default null, p_confirm boolean default false
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_conf jsonb := '[]'::jsonb;
  v_id uuid;
begin
  perform public._require_admin();
  if p_ends_at <= p_starts_at then raise exception 'INVALID_RANGE'; end if;
  begin
    insert into public.schedule_exceptions (barber_id, chair_id, starts_at, ends_at, type, reason, created_by)
    values (p_barber_id, p_chair_id, p_starts_at, p_ends_at, p_type, nullif(btrim(p_reason), ''), auth.uid())
    returning id into v_id;

    v_conf := public._future_conflicts(p_barber_id, p_chair_id);
    if jsonb_array_length(v_conf) > 0 and not p_confirm then
      raise exception 'NEEDS_CONFIRM';
    end if;
  exception when raise_exception then
    if sqlerrm = 'NEEDS_CONFIRM' then
      return jsonb_build_object('saved', false, 'conflicts', v_conf);
    end if;
    raise;
  end;
  return jsonb_build_object('saved', true, 'id', v_id, 'conflicts', v_conf);
end $$;

-- Asigna un barbero a una silla desde una fecha (p_chair_id NULL = dejarlo sin silla).
create or replace function public.admin_assign_barber(
  p_barber_id uuid, p_chair_id uuid, p_valid_from date default null, p_confirm boolean default false
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_conf jsonb := '[]'::jsonb;
  v_from date := coalesce(p_valid_from, (now() at time zone public._tz())::date);
begin
  perform public._require_admin();
  begin
    -- Cerrar asignaciones vigentes/futuras del barbero
    delete from public.barber_chair_assignments where barber_id = p_barber_id and valid_from >= v_from;
    update public.barber_chair_assignments set valid_until = v_from
     where barber_id = p_barber_id and valid_from < v_from and (valid_until is null or valid_until > v_from);

    if p_chair_id is not null then
      -- Cerrar asignaciones vigentes/futuras de la silla
      delete from public.barber_chair_assignments where chair_id = p_chair_id and valid_from >= v_from;
      update public.barber_chair_assignments set valid_until = v_from
       where chair_id = p_chair_id and valid_from < v_from and (valid_until is null or valid_until > v_from);
      insert into public.barber_chair_assignments (barber_id, chair_id, valid_from)
      values (p_barber_id, p_chair_id, v_from);
    end if;

    v_conf := public._future_conflicts(p_barber_id, p_chair_id);
    if jsonb_array_length(v_conf) > 0 and not p_confirm then
      raise exception 'NEEDS_CONFIRM';
    end if;
  exception when raise_exception then
    if sqlerrm = 'NEEDS_CONFIRM' then
      return jsonb_build_object('saved', false, 'conflicts', v_conf);
    end if;
    raise;
  end;
  return jsonb_build_object('saved', true, 'conflicts', v_conf);
end $$;

create or replace function public.admin_set_barber_active(p_id uuid, p_active boolean, p_confirm boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_conf jsonb := '[]'::jsonb;
begin
  perform public._require_admin();
  begin
    update public.barbers set is_active = p_active where id = p_id;
    if not found then raise exception 'NOT_FOUND'; end if;
    v_conf := public._future_conflicts(p_id, null);
    if jsonb_array_length(v_conf) > 0 and not p_confirm then raise exception 'NEEDS_CONFIRM'; end if;
  exception when raise_exception then
    if sqlerrm = 'NEEDS_CONFIRM' then return jsonb_build_object('saved', false, 'conflicts', v_conf); end if;
    raise;
  end;
  return jsonb_build_object('saved', true, 'conflicts', v_conf);
end $$;

create or replace function public.admin_set_chair_active(p_id uuid, p_active boolean, p_confirm boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_conf jsonb := '[]'::jsonb;
begin
  perform public._require_admin();
  begin
    update public.chairs set is_active = p_active where id = p_id;
    if not found then raise exception 'NOT_FOUND'; end if;
    v_conf := public._future_conflicts(null, p_id);
    if jsonb_array_length(v_conf) > 0 and not p_confirm then raise exception 'NEEDS_CONFIRM'; end if;
  exception when raise_exception then
    if sqlerrm = 'NEEDS_CONFIRM' then return jsonb_build_object('saved', false, 'conflicts', v_conf); end if;
    raise;
  end;
  return jsonb_build_object('saved', true, 'conflicts', v_conf);
end $$;

-- =====================================================================
-- Permisos de ejecución
-- =====================================================================
revoke execute on all functions in schema public from public, anon, authenticated;
grant  execute on all functions in schema public to service_role;

grant execute on function public.is_admin()                                   to anon, authenticated;
grant execute on function public.get_public_info()                            to anon, authenticated;
grant execute on function public.get_availability(date, uuid)                 to anon, authenticated;
grant execute on function public.get_calendar_summary(date, date, uuid)       to anon, authenticated;

grant execute on function public.my_appointments()                            to authenticated;
grant execute on function public.cancel_my_appointment(uuid)                  to authenticated;

grant execute on function public.admin_availability(date, uuid, uuid)                                         to authenticated;
grant execute on function public.admin_create_appointment(uuid, uuid, timestamptz, text, text, text, text, public.appointment_status) to authenticated;
grant execute on function public.admin_reschedule_appointment(uuid, uuid, timestamptz)                        to authenticated;
grant execute on function public.admin_set_appointment_status(uuid, public.appointment_status, text)          to authenticated;
grant execute on function public.admin_list_appointments(date, date)                                          to authenticated;
grant execute on function public.admin_dashboard(date)                                                        to authenticated;
grant execute on function public.admin_save_business_hours(jsonb, boolean)                                    to authenticated;
grant execute on function public.admin_save_barber_hours(uuid, jsonb, boolean)                                to authenticated;
grant execute on function public.admin_create_exception(uuid, uuid, timestamptz, timestamptz, public.exception_type, text, boolean) to authenticated;
grant execute on function public.admin_assign_barber(uuid, uuid, date, boolean)                               to authenticated;
grant execute on function public.admin_set_barber_active(uuid, boolean, boolean)                              to authenticated;
grant execute on function public.admin_set_chair_active(uuid, boolean, boolean)                               to authenticated;

-- Solo el servidor (clave service_role en /api) puede crear o tocar citas de invitados.
grant execute on function public.register_rate_hit(text, int, int)                                             to service_role;
grant execute on function public.book_appointment(uuid, uuid, timestamptz, text, text, text, text, uuid)       to service_role;
grant execute on function public.get_appointment_by_token(text, text)                                          to service_role;
grant execute on function public.cancel_appointment_by_token(text, text)                                       to service_role;
grant execute on function public.reschedule_appointment_by_token(text, text, uuid, timestamptz)                to service_role;
grant execute on function public.get_reschedule_availability(text, text, date)                                 to service_role;
grant execute on function public.release_expired_holds()                                                       to service_role;

-- Las funciones nuevas no deben quedar abiertas por defecto.
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
