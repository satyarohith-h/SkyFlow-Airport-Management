-- Workflow integrity additions. Run after 006_operations_security_and_support.sql.
begin;

alter table public.profiles add column if not exists active boolean not null default true;
alter table public.profiles add column if not exists preferences jsonb not null default '{}'::jsonb;
alter table public.bookings add column if not exists cancelled_at timestamptz;
alter table public.bookings add column if not exists refund_status text not null default 'Not applicable';

create table if not exists public.boarding_passes (
  id uuid primary key default gen_random_uuid(), booking_id uuid not null references public.bookings(id) on delete cascade,
  passenger_id uuid references public.booking_passengers(id) on delete cascade, pass_reference text not null unique,
  qr_payload text not null, status text not null default 'Issued', issued_at timestamptz not null default now(), boarded_at timestamptz,
  unique(booking_id, passenger_id), check (status in ('Issued','Validated','Boarded','Voided'))
);
create table if not exists public.baggage_status_history (
  id uuid primary key default gen_random_uuid(), baggage_id uuid not null references public.baggage(id) on delete cascade,
  from_status text, to_status text not null, location text, actor_id uuid references public.profiles(id), created_at timestamptz not null default now()
);
create table if not exists public.support_ticket_history (
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  from_status text, to_status text not null, note text, actor_id uuid references public.profiles(id), created_at timestamptz not null default now()
);
create table if not exists public.notification_deliveries (
  id uuid primary key default gen_random_uuid(), notification_id uuid not null references public.notifications(id) on delete cascade,
  channel text not null default 'in_app', status text not null default 'Queued', provider_reference text,
  attempted_at timestamptz, delivered_at timestamptz, error_message text, check (status in ('Queued','Sent','Delivered','Failed'))
);

create unique index if not exists flights_gate_schedule_idx on public.flights(gate_id, departure_at) where gate_id is not null;
create index if not exists boarding_passes_booking_idx on public.boarding_passes(booking_id,status);
create index if not exists baggage_history_idx on public.baggage_status_history(baggage_id,created_at desc);
create index if not exists notification_delivery_status_idx on public.notification_deliveries(status,attempted_at);

alter table public.boarding_passes enable row level security;
alter table public.baggage_status_history enable row level security;
alter table public.support_ticket_history enable row level security;
alter table public.notification_deliveries enable row level security;

create policy "passengers read own boarding passes" on public.boarding_passes for select using (exists (select 1 from public.bookings b where b.id=booking_id and b.user_id=auth.uid()));
create policy "operators manage boarding passes" on public.boarding_passes for all using (public.is_airport_operator()) with check (public.is_airport_operator());
create policy "passengers read own baggage history" on public.baggage_status_history for select using (exists (select 1 from public.baggage bg join public.bookings b on b.id=bg.booking_id where bg.id=baggage_id and b.user_id=auth.uid()));
create policy "operators manage baggage history" on public.baggage_status_history for all using (public.is_airport_operator()) with check (public.is_airport_operator());
create policy "ticket owners read history" on public.support_ticket_history for select using (exists (select 1 from public.support_tickets st where st.id=ticket_id and st.user_id=auth.uid()) or public.is_airport_operator());
create policy "operators manage ticket history" on public.support_ticket_history for all using (public.is_airport_operator()) with check (public.is_airport_operator());
create policy "notification owners read deliveries" on public.notification_deliveries for select using (exists (select 1 from public.notifications n where n.id=notification_id and n.user_id=auth.uid()) or public.is_airport_operator());

commit;
