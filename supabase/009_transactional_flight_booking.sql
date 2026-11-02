-- Transactional core for flight inventory and passenger booking. Apply after 008.
begin;

create extension if not exists pgcrypto;

alter table public.flights add column if not exists terminal_name text;
alter table public.flights add column if not exists aircraft_model text;
alter table public.flights add column if not exists booked_seats integer not null default 0 check (booked_seats >= 0);
alter table public.announcements add column if not exists status text not null default 'Published';
alter table public.announcements add column if not exists published_at timestamptz not null default now();
alter table public.flights add column if not exists changed_by uuid references public.profiles(id);
alter table public.runways add column if not exists changed_by uuid references public.profiles(id);
alter table public.support_tickets add column if not exists changed_by uuid references public.profiles(id);
alter table public.baggage add column if not exists changed_by uuid references public.profiles(id);
alter table public.operational_incidents add column if not exists changed_by uuid references public.profiles(id);
alter table public.bookings add column if not exists changed_by uuid references public.profiles(id);
-- Keep legacy nullable columns intact; RPC-created bookings always supply both references.
drop index if exists public.booking_passengers_seat_idx;

create or replace function public.prevent_overlapping_gate_assignments()
returns trigger language plpgsql security definer set search_path=public as $$
declare candidate_end timestamptz;
begin
  if new.gate_id is null or new.status='Cancelled' then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.gate_id::text,0));
  candidate_end := coalesce(new.arrival_at,new.departure_at+interval '1 hour');
  if exists(select 1 from public.flights f where f.gate_id=new.gate_id and f.id is distinct from new.id and f.status<>'Cancelled'
    and tstzrange(f.departure_at,coalesce(f.arrival_at,f.departure_at+interval '1 hour'),'[)') && tstzrange(new.departure_at,candidate_end,'[)')) then
    raise exception using errcode='23P01',message='Gate allocation overlaps another flight';
  end if;
  return new;
end $$;
drop trigger if exists flights_no_gate_overlap on public.flights;
create trigger flights_no_gate_overlap before insert or update of gate_id,departure_at,arrival_at,status on public.flights
for each row execute function public.prevent_overlapping_gate_assignments();

create or replace function public.has_airport_role(allowed text[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active=true and role::text=any(allowed));
$$;
revoke all on function public.has_airport_role(text[]) from public,anon;
grant execute on function public.has_airport_role(text[]) to authenticated,service_role;

alter table public.flights enable row level security;
alter table public.airports enable row level security;
alter table public.airlines enable row level security;
alter table public.aircraft enable row level security;
alter table public.terminals enable row level security;
alter table public.gates enable row level security;
alter table public.seats enable row level security;
alter table public.booking_passengers enable row level security;
alter table public.check_ins enable row level security;
alter table public.baggage enable row level security;
alter table public.flight_status_history enable row level security;
alter table public.announcements enable row level security;
alter table public.audit_logs enable row level security;
alter table public.operational_incidents enable row level security;
alter table public.incident_history enable row level security;
alter table public.security_screenings enable row level security;
alter table public.staff enable row level security;
alter table public.shifts enable row level security;
alter table public.equipment enable row level security;
alter table public.maintenance_work_orders enable row level security;
alter table public.role_permissions enable row level security;

drop policy if exists "authenticated read flights" on public.flights;
create policy "authenticated read flights" on public.flights for select to authenticated using (true);
drop policy if exists "authenticated read airport catalogue" on public.airports;
create policy "authenticated read airport catalogue" on public.airports for select to authenticated using (true);
drop policy if exists "authenticated read airline catalogue" on public.airlines;
create policy "authenticated read airline catalogue" on public.airlines for select to authenticated using (true);
drop policy if exists "authenticated read aircraft catalogue" on public.aircraft;
create policy "authenticated read aircraft catalogue" on public.aircraft for select to authenticated using (true);
drop policy if exists "authenticated read terminal gate catalogue" on public.terminals;
create policy "authenticated read terminal gate catalogue" on public.terminals for select to authenticated using (true);
drop policy if exists "authenticated read gates" on public.gates;
create policy "authenticated read gates" on public.gates for select to authenticated using (true);
drop policy if exists "authenticated read seats" on public.seats;
create policy "authenticated read seats" on public.seats for select to authenticated using (true);
drop policy if exists "users read own booking passengers" on public.booking_passengers;
create policy "users read own booking passengers" on public.booking_passengers for select to authenticated using (exists(select 1 from public.bookings b where b.id=booking_id and b.user_id=auth.uid()) or public.has_airport_role(array['super-admin','airport-admin','operations-manager','check-in-staff','gate-staff']));
drop policy if exists "users read own checkins" on public.check_ins;
create policy "users read own checkins" on public.check_ins for select to authenticated using (exists(select 1 from public.bookings b where b.id=booking_id and b.user_id=auth.uid()) or public.has_airport_role(array['super-admin','airport-admin','operations-manager','check-in-staff','gate-staff']));
drop policy if exists "users read own baggage" on public.baggage;
create policy "users read own baggage" on public.baggage for select to authenticated using (exists(select 1 from public.bookings b where b.id=booking_id and b.user_id=auth.uid()) or public.has_airport_role(array['super-admin','airport-admin','operations-manager','gate-staff']));
drop policy if exists "authenticated read flight history" on public.flight_status_history;
create policy "authenticated read flight history" on public.flight_status_history for select to authenticated using (true);
drop policy if exists "authenticated read published announcements" on public.announcements;
create policy "authenticated read published announcements" on public.announcements for select to authenticated using (status='Published');
drop policy if exists "operators read audit logs" on public.audit_logs;
create policy "operators read audit logs" on public.audit_logs for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin']));
drop policy if exists "operators insert audit logs" on public.audit_logs;
create policy "operators insert audit logs" on public.audit_logs for insert to authenticated with check (actor_id=auth.uid() and public.has_airport_role(array['super-admin','airport-admin','operations-manager','check-in-staff','gate-staff','security-staff']));

drop policy if exists "operators read departments" on public.departments;
drop policy if exists "authorized admins read departments" on public.departments;
create policy "authorized admins read departments" on public.departments for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "users own support tickets" on public.support_tickets;
drop policy if exists "ticket owners and support leads read tickets" on public.support_tickets;
create policy "ticket owners and support leads read tickets" on public.support_tickets for select to authenticated using (user_id=auth.uid() or public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "users create support tickets" on public.support_tickets;
drop policy if exists "users create own support tickets" on public.support_tickets;
create policy "users create own support tickets" on public.support_tickets for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "operators manage support tickets" on public.support_tickets;
drop policy if exists "authorized staff manage support tickets" on public.support_tickets;
create policy "support leads update tickets" on public.support_tickets for update to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager'])) with check (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));

drop policy if exists "authorized staff read incidents" on public.operational_incidents;
create policy "authorized staff read incidents" on public.operational_incidents for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager','security-staff']));
drop policy if exists "authorized staff manage incidents" on public.operational_incidents;
create policy "authorized staff manage incidents" on public.operational_incidents for all to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager','security-staff'])) with check (public.has_airport_role(array['super-admin','airport-admin','operations-manager','security-staff']));
drop policy if exists "authorized staff read incident history" on public.incident_history;
create policy "authorized staff read incident history" on public.incident_history for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager','security-staff']));
drop policy if exists "authorized staff read screenings" on public.security_screenings;
create policy "authorized staff read screenings" on public.security_screenings for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin','security-staff']));
drop policy if exists "authorized security staff manage screenings" on public.security_screenings;
create policy "authorized security staff manage screenings" on public.security_screenings for all to authenticated using (public.has_airport_role(array['super-admin','airport-admin','security-staff'])) with check (public.has_airport_role(array['super-admin','airport-admin','security-staff']));
drop policy if exists "admins read staff directory" on public.staff;
create policy "admins read staff directory" on public.staff for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin']));
drop policy if exists "admins manage staff directory" on public.staff;
create policy "admins manage staff directory" on public.staff for all to authenticated using (public.has_airport_role(array['super-admin','airport-admin'])) with check (public.has_airport_role(array['super-admin','airport-admin']));
drop policy if exists "admins read shifts" on public.shifts;
create policy "admins read shifts" on public.shifts for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "admins manage shifts" on public.shifts;
create policy "admins manage shifts" on public.shifts for all to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager'])) with check (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "operators read equipment" on public.equipment;
create policy "operators read equipment" on public.equipment for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "operators manage equipment" on public.equipment;
create policy "operators manage equipment" on public.equipment for all to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager'])) with check (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "operators read maintenance" on public.maintenance_work_orders;
create policy "operators read maintenance" on public.maintenance_work_orders for select to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "operators manage maintenance" on public.maintenance_work_orders;
create policy "operators manage maintenance" on public.maintenance_work_orders for all to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager'])) with check (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "super admins manage role permissions" on public.role_permissions;
create policy "super admins manage role permissions" on public.role_permissions for all to authenticated using (public.has_airport_role(array['super-admin'])) with check (public.has_airport_role(array['super-admin']));

drop policy if exists "operators manage system settings" on public.system_settings;
drop policy if exists "super admins manage system settings" on public.system_settings;
create policy "super admins manage system settings" on public.system_settings for all to authenticated using (public.has_airport_role(array['super-admin'])) with check (public.has_airport_role(array['super-admin']));
drop policy if exists "operators manage runways" on public.runways;
drop policy if exists "authorized operations manage runways" on public.runways;
create policy "authorized operations manage runways" on public.runways for all to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager'])) with check (public.has_airport_role(array['super-admin','airport-admin','operations-manager']));
drop policy if exists "operators manage boarding passes" on public.boarding_passes;
drop policy if exists "authorized staff manage boarding passes" on public.boarding_passes;
create policy "authorized staff manage boarding passes" on public.boarding_passes for all to authenticated using (public.has_airport_role(array['super-admin','airport-admin','operations-manager','gate-staff','check-in-staff'])) with check (public.has_airport_role(array['super-admin','airport-admin','operations-manager','gate-staff','check-in-staff']));

create or replace function public.create_flight_seat_inventory()
returns trigger language plpgsql security definer set search_path=public as $$
declare i integer; letters text[] := array['A','B','C','D','E','F'];
begin
  if new.seat_capacity is null or new.seat_capacity < 1 then return new; end if;
  for i in 0..least(new.seat_capacity, 600)-1 loop
    insert into public.seats(flight_id,seat_number,class)
    values(new.id, (i/6+1)::text || letters[(i%6)+1], coalesce(new.travel_class,'Economy'))
    on conflict(flight_id,seat_number) do nothing;
  end loop;
  return new;
end $$;
drop trigger if exists flights_create_seats on public.flights;
create trigger flights_create_seats after insert or update of seat_capacity on public.flights
for each row execute function public.create_flight_seat_inventory();
update public.flights set seat_capacity=seat_capacity where seat_capacity is not null;

create table if not exists public.runway_status_history (
  id uuid primary key default gen_random_uuid(), runway_id uuid not null references public.runways(id) on delete cascade,
  from_status text, to_status text not null, actor_id uuid references public.profiles(id), created_at timestamptz not null default now()
);
alter table public.runway_status_history enable row level security;
create policy "operators read runway history" on public.runway_status_history for select using (public.is_airport_operator());
create policy "operators write runway history" on public.runway_status_history for insert with check (public.is_airport_operator());

create or replace function public.record_runway_status_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then insert into public.runway_status_history(runway_id,to_status,actor_id) values(new.id,new.status,new.changed_by);
  elsif new.status is distinct from old.status then insert into public.runway_status_history(runway_id,from_status,to_status,actor_id) values(new.id,old.status,new.status,new.changed_by); end if;
  return new;
end $$;
drop trigger if exists runways_record_status on public.runways;
create trigger runways_record_status after insert or update of status on public.runways for each row execute function public.record_runway_status_change();

create or replace function public.record_support_ticket_status_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then insert into public.support_ticket_history(ticket_id,to_status,actor_id,note) values(new.id,new.status,new.user_id,'Ticket created');
  elsif new.status is distinct from old.status then insert into public.support_ticket_history(ticket_id,from_status,to_status,actor_id,note) values(new.id,old.status,new.status,new.changed_by,'Ticket status updated'); end if;
  return new;
end $$;
drop trigger if exists support_tickets_record_status on public.support_tickets;
create trigger support_tickets_record_status after insert or update of status on public.support_tickets for each row execute function public.record_support_ticket_status_change();

create or replace function public.record_incident_status_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then insert into public.incident_history(incident_id,to_status,actor_id,notes) values(new.id,new.status,new.owner_id,'Incident created');
  elsif new.status is distinct from old.status then insert into public.incident_history(incident_id,from_status,to_status,actor_id,notes) values(new.id,old.status,new.status,new.changed_by,new.resolution_notes); end if;
  return new;
end $$;
drop trigger if exists incidents_record_status on public.operational_incidents;
create trigger incidents_record_status after insert or update of status on public.operational_incidents for each row execute function public.record_incident_status_change();

create or replace function public.record_baggage_status_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then insert into public.baggage_status_history(baggage_id,to_status,actor_id) values(new.id,new.status,new.changed_by);
  elsif new.status is distinct from old.status then insert into public.baggage_status_history(baggage_id,from_status,to_status,actor_id) values(new.id,old.status,new.status,new.changed_by); end if;
  return new;
end $$;
drop trigger if exists baggage_record_status on public.baggage;
create trigger baggage_record_status after insert or update of status on public.baggage for each row execute function public.record_baggage_status_change();

create or replace function public.notify_passengers_announcement()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='Published' then
    insert into public.notifications(user_id,title,body)
      select id,new.title,new.body from public.profiles where role::text='passenger' and active=true;
  end if;
  return new;
end $$;
drop trigger if exists announcements_notify_passengers on public.announcements;
create trigger announcements_notify_passengers after insert on public.announcements for each row execute function public.notify_passengers_announcement();

create or replace function public.record_notification_delivery_queue()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.notification_deliveries(notification_id,channel,status) values(new.id,'in_app','Queued');
  return new;
end $$;
drop trigger if exists notifications_create_delivery_queue on public.notifications;
create trigger notifications_create_delivery_queue after insert on public.notifications for each row execute function public.record_notification_delivery_queue();

create or replace function public.notify_booked_passengers_flight_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare detail text;
begin
  if tg_op='UPDATE' and (new.status is distinct from old.status or new.gate is distinct from old.gate or new.estimated_departure_at is distinct from old.estimated_departure_at) then
    detail := 'Status: '||coalesce(new.status,'Unknown')||'; gate: '||coalesce(new.gate,'TBC')||'; estimated departure: '||coalesce(to_char(new.estimated_departure_at,'HH24:MI'),'TBC')||'.';
    insert into public.notifications(user_id,title,body)
      select distinct b.user_id,new.flight_number||' flight update',detail
      from public.bookings b where b.flight_id=new.id and b.status not in ('Cancelled','Refunded');
  end if;
  return new;
end $$;
drop trigger if exists flights_notify_passengers on public.flights;
create trigger flights_notify_passengers after update of status,gate,estimated_departure_at on public.flights for each row execute function public.notify_booked_passengers_flight_change();

create or replace function public.record_flight_status_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.flight_status_history(flight_id,from_status,to_status,reason) values(new.id,null,new.status,'Flight created');
  elsif new.status is distinct from old.status then
    insert into public.flight_status_history(flight_id,from_status,to_status,reason) values(new.id,old.status,new.status,'Status updated');
  end if;
  return new;
end $$;
drop trigger if exists flights_record_status_change on public.flights;
create trigger flights_record_status_change after insert or update of status on public.flights
for each row execute function public.record_flight_status_change();

create or replace function public.refresh_flight_booked_seats()
returns trigger language plpgsql security definer set search_path=public as $$
declare affected_flight uuid; affected_booking uuid;
begin
  if tg_table_name='booking_passengers' then
    affected_booking := case when tg_op='DELETE' then old.booking_id else new.booking_id end;
    select flight_id into affected_flight from public.bookings where id=affected_booking;
  else
    affected_flight := case when tg_op='DELETE' then old.flight_id else new.flight_id end;
  end if;
  if affected_flight is not null then
    update public.flights f set booked_seats = (
      select count(*) from public.booking_passengers bp
      join public.bookings b on b.id=bp.booking_id
      where b.flight_id=affected_flight and b.status not in ('Cancelled','Refunded') and bp.seat_id is not null
    ) where f.id=affected_flight;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists booking_passengers_refresh_seat_count on public.booking_passengers;
create trigger booking_passengers_refresh_seat_count after insert or delete or update of seat_id on public.booking_passengers
for each row execute function public.refresh_flight_booked_seats();
drop trigger if exists bookings_refresh_seat_count on public.bookings;
create trigger bookings_refresh_seat_count after update of status on public.bookings
for each row execute function public.refresh_flight_booked_seats();

create or replace function public.record_booking_status_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then insert into public.booking_audit_history(booking_id,from_status,to_status,actor_id,notes) values(new.id,null,new.status,new.changed_by,'Booking created; payment remains pending until a provider is configured.');
  elsif new.status is distinct from old.status then insert into public.booking_audit_history(booking_id,from_status,to_status,actor_id,notes) values(new.id,old.status,new.status,new.changed_by,'Booking status changed.'); end if;
  return new;
end $$;
drop trigger if exists bookings_record_status_history on public.bookings;
create trigger bookings_record_status_history after insert or update of status on public.bookings for each row execute function public.record_booking_status_change();

create or replace function public.create_booking_atomic(
  p_user_id uuid, p_flight_id uuid, p_passengers jsonb, p_seats text[],
  p_contact_email text, p_contact_phone text, p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_flight public.flights%rowtype;
  v_booking public.bookings%rowtype;
  v_count integer;
  v_base numeric(12,2);
  v_taxes numeric(12,2);
  v_total numeric(12,2);
  v_pnr text;
  v_passenger jsonb;
  v_seat_id uuid;
  v_seat text;
  v_index integer := 0;
begin
  if p_user_id is null or p_idempotency_key is null or length(p_idempotency_key)<8 then
    raise exception using errcode='22023', message='Booking identity and idempotency key are required';
  end if;
  if p_passengers is null or p_seats is null or jsonb_typeof(p_passengers)<>'array' or jsonb_array_length(p_passengers)<1 or jsonb_array_length(p_passengers)>9 or cardinality(p_seats)<>jsonb_array_length(p_passengers) then
    raise exception using errcode='22023', message='Passenger and seat selections are invalid';
  end if;
  if (select count(distinct s) from unnest(p_seats) s)<>cardinality(p_seats) then
    raise exception using errcode='22023', message='Duplicate seat selection';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_flight_id::text,0));
  select * into v_flight from public.flights where id=p_flight_id for update;
  if not found then raise exception using errcode='P0002', message='Flight not found'; end if;
  if v_flight.status='Cancelled' then raise exception using errcode='22023', message='Flight is cancelled'; end if;
  if exists(select 1 from public.bookings where user_id=p_user_id and idempotency_key=p_idempotency_key) then
    raise exception using errcode='23505', message='Duplicate booking request';
  end if;
  if exists(
    select 1 from unnest(p_seats) requested(seat_number)
    left join public.seats s on s.flight_id=p_flight_id and s.seat_number=requested.seat_number
    left join public.booking_passengers bp on bp.seat_id=s.id
    left join public.bookings b on b.id=bp.booking_id and b.status not in ('Cancelled','Refunded')
    where s.id is null or b.id is not null
  ) then raise exception using errcode='23505', message='One or more selected seats are unavailable'; end if;
  for v_passenger in select value from jsonb_array_elements(p_passengers) loop
    if length(trim(coalesce(v_passenger->>'fullName','')))<2
       or coalesce(v_passenger->>'dateOfBirth','') !~ '^\d{4}-\d{2}-\d{2}$'
       or coalesce(v_passenger->>'contactEmail','') !~ '^\S+@\S+\.\S+$'
       or length(coalesce(v_passenger->>'documentNumber',''))<4 then
      raise exception using errcode='22023', message='Passenger details are invalid';
    end if;
  end loop;
  v_base := v_flight.fare * jsonb_array_length(p_passengers);
  v_taxes := round(v_base * 0.12,2);
  v_total := v_base + v_taxes;
  v_pnr := 'SKY' || upper(substr(encode(gen_random_bytes(6),'hex'),1,8));
  insert into public.bookings(pnr,user_id,flight_id,status,total_amount,contact_email,contact_phone,base_fare,taxes,baggage_addons,payment_status,idempotency_key,changed_by)
    values(v_pnr,p_user_id,p_flight_id,'Confirmed',v_total,p_contact_email,p_contact_phone,v_base,v_taxes,0,'Pending',p_idempotency_key,p_user_id)
    returning * into v_booking;
  for v_passenger in select value from jsonb_array_elements(p_passengers) loop
    v_seat := p_seats[v_index+1];
    select id into v_seat_id from public.seats where flight_id=p_flight_id and seat_number=v_seat;
    insert into public.booking_passengers(booking_id,full_name,seat_id,ticket_number,date_of_birth,contact_email,contact_phone,document_type,document_last4)
      values(v_booking.id,trim(v_passenger->>'fullName'),v_seat_id,'TKT-'||upper(substr(encode(gen_random_bytes(8),'hex'),1,12)),(v_passenger->>'dateOfBirth')::date,v_passenger->>'contactEmail',v_passenger->>'contactPhone',v_passenger->>'documentType',right(v_passenger->>'documentNumber',4));
    v_index := v_index + 1;
  end loop;
  insert into public.booking_payments(booking_id,amount,status,method) values(v_booking.id,v_total,'Pending','Not configured');
  insert into public.baggage(booking_id,tag_number,status) values(v_booking.id,'BG-'||upper(substr(encode(gen_random_bytes(6),'hex'),1,10)),'Baggage Accepted');
  return jsonb_build_object('id',v_booking.id,'pnr',v_booking.pnr,'user_id',v_booking.user_id,'flight_id',v_booking.flight_id,'passenger',(p_passengers->0->>'fullName'),'status',v_booking.status,'contact_email',v_booking.contact_email,'contact_phone',v_booking.contact_phone,'base_fare',v_base,'taxes',v_taxes,'baggage_addons',0,'total_amount',v_total,'payment_status','Pending','idempotency_key',v_booking.idempotency_key,'checked_in',false,'created_at',v_booking.created_at,'passengers',p_passengers,'seats',to_jsonb(p_seats),'seat',p_seats[1],'baggage_status','Baggage Accepted','payment',jsonb_build_object('status','Pending','amount',v_total,'method','Not configured'),'simulated',true);
end $$;
revoke all on function public.create_booking_atomic(uuid,uuid,jsonb,text[],text,text,text) from public, anon, authenticated;
grant execute on function public.create_booking_atomic(uuid,uuid,jsonb,text[],text,text,text) to service_role;

create or replace function public.cancel_booking_atomic(p_booking_id uuid,p_actor_id uuid,p_is_operator boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.bookings%rowtype; f public.flights%rowtype;
begin
  select * into b from public.bookings where id=p_booking_id for update;
  if not found or (not p_is_operator and b.user_id<>p_actor_id) then raise exception using errcode='P0002',message='Booking not found'; end if;
  if b.status in ('Cancelled','Completed','Refunded') then raise exception using errcode='22023',message='This booking cannot be cancelled'; end if;
  select * into f from public.flights where id=b.flight_id;
  if f.departure_at<=now() then raise exception using errcode='22023',message='Booking is past departure and cannot be cancelled'; end if;
  update public.bookings set status='Cancelled',cancelled_at=now(),refund_status=case when payment_status='Completed' then 'Refund pending' else 'Not applicable' end,changed_by=p_actor_id,updated_at=now() where id=b.id returning * into b;
  return to_jsonb(b);
end $$;
revoke all on function public.cancel_booking_atomic(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.cancel_booking_atomic(uuid,uuid,boolean) to service_role;

create or replace function public.check_in_booking_atomic(p_booking_id uuid,p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.bookings%rowtype; f public.flights%rowtype; pass jsonb;
begin
  select * into b from public.bookings where id=p_booking_id and user_id=p_user_id for update;
  if not found then raise exception using errcode='P0002',message='Booking not found'; end if;
  if b.status in ('Cancelled','Completed') then raise exception using errcode='22023',message='Booking is not eligible for check-in'; end if;
  if exists(select 1 from public.check_ins where booking_id=b.id) then raise exception using errcode='23505',message='Booking is already checked in'; end if;
  select * into f from public.flights where id=b.flight_id;
  if now()<f.departure_at-interval '48 hours' or now()>f.departure_at-interval '60 minutes' then
    raise exception using errcode='22023',message='Online check-in is available from 48 hours until 60 minutes before departure';
  end if;
  insert into public.check_ins(booking_id,status) values(b.id,'Completed');
  update public.bookings set status='Checked-in',changed_by=p_user_id,updated_at=now() where id=b.id returning * into b;
  insert into public.boarding_passes(booking_id,passenger_id,pass_reference,qr_payload,status)
    select b.id,bp.id,'BP-'||upper(substr(encode(gen_random_bytes(8),'hex'),1,12)),'SKYFLOW:'||b.pnr||':'||bp.ticket_number,'Issued'
    from public.booking_passengers bp where bp.booking_id=b.id;
  select jsonb_agg(jsonb_build_object('reference',bp.pass_reference,'qr',bp.qr_payload,'status',bp.status)) into pass from public.boarding_passes bp where bp.booking_id=b.id;
  return jsonb_build_object('booking',to_jsonb(b),'boardingPasses',coalesce(pass,'[]'::jsonb));
end $$;
revoke all on function public.check_in_booking_atomic(uuid,uuid) from public,anon,authenticated;
grant execute on function public.check_in_booking_atomic(uuid,uuid) to service_role;

create or replace function public.board_booking_atomic(p_booking_id uuid,p_actor_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.bookings%rowtype; passes jsonb;
begin
  select * into b from public.bookings where id=p_booking_id for update;
  if not found then raise exception using errcode='P0002',message='Booking not found'; end if;
  if not exists(select 1 from public.check_ins where booking_id=b.id) then raise exception using errcode='22023',message='Passenger must be checked in before boarding'; end if;
  if not exists(select 1 from public.boarding_passes where booking_id=b.id and status='Issued') then raise exception using errcode='23505',message='Boarding is already complete or no valid boarding pass exists'; end if;
  update public.boarding_passes set status='Boarded',boarded_at=now() where booking_id=b.id and status='Issued';
  update public.bookings set status='Completed',changed_by=p_actor_id,updated_at=now() where id=b.id returning * into b;
  select jsonb_agg(jsonb_build_object('reference',pass_reference,'status',status,'boardedAt',boarded_at)) into passes from public.boarding_passes where booking_id=b.id;
  return jsonb_build_object('booking',to_jsonb(b),'boardingPasses',coalesce(passes,'[]'::jsonb));
end $$;
revoke all on function public.board_booking_atomic(uuid,uuid) from public,anon,authenticated;
grant execute on function public.board_booking_atomic(uuid,uuid) to service_role;

commit;
