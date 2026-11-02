-- Phase 2: airport catalogue, searchable flights and status history.
-- Safe to run after 001_initial_schema.sql; additive changes preserve existing rows.
alter table public.airports add column if not exists timezone text not null default 'UTC';
alter table public.airports add column if not exists status text not null default 'Operational';
alter table public.airports add column if not exists terminal_info text not null default 'Main terminal';
alter table public.flights add column if not exists airline_code text;
alter table public.flights add column if not exists arrival_time time;
alter table public.flights add column if not exists duration_minutes integer;
alter table public.flights add column if not exists stops integer not null default 0;
alter table public.flights add column if not exists travel_class text not null default 'Economy';
alter table public.flights add column if not exists fare numeric(12,2) not null default 0;
alter table public.flights add column if not exists baggage_allowance text not null default '20 kg';
alter table public.flights add column if not exists gate text;
alter table public.flights add column if not exists seat_capacity integer;
create table if not exists public.flight_status_history (
  id uuid primary key default gen_random_uuid(), flight_id uuid not null references public.flights(id) on delete cascade,
  from_status text, to_status text not null, reason text, changed_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create index if not exists airports_code_idx on public.airports(code);
create index if not exists airports_city_idx on public.airports(city);
create index if not exists flights_route_date_idx on public.flights(origin_airport_id, destination_airport_id, departure_at);
create index if not exists flights_fare_idx on public.flights(fare);
create index if not exists flight_status_history_flight_idx on public.flight_status_history(flight_id, created_at desc);
insert into public.airports (code,name,city,country,timezone,status,terminal_info) values
('DEL','Indira Gandhi International','New Delhi','India','Asia/Kolkata','Operational','T1 / T2 / T3'),('HYD','Rajiv Gandhi International','Hyderabad','India','Asia/Kolkata','Operational','T1'),('BLR','Kempegowda International','Bengaluru','India','Asia/Kolkata','Operational','T1 / T2'),('MAA','Chennai International','Chennai','India','Asia/Kolkata','Operational','T1 / T2'),('TIR','Tirupati International','Tirupati','India','Asia/Kolkata','Operational','Main terminal'),('BOM','Chhatrapati Shivaji Maharaj International','Mumbai','India','Asia/Kolkata','Operational','T1 / T2'),('CCU','Netaji Subhas Chandra Bose International','Kolkata','India','Asia/Kolkata','Operational','T1'),('COK','Cochin International','Kochi','India','Asia/Kolkata','Operational','T1 / T3'),('GOI','Manohar International','Goa','India','Asia/Kolkata','Operational','Main terminal'),('VTZ','Visakhapatnam International','Visakhapatnam','India','Asia/Kolkata','Operational','Main terminal'),('DXB','Dubai International','Dubai','UAE','Asia/Dubai','Operational','T1 / T2 / T3'),('SIN','Singapore Changi','Singapore','Singapore','Asia/Singapore','Operational','T1 / T2 / T3 / T4'),('LHR','Heathrow Airport','London','United Kingdom','Europe/London','Operational','T2 / T3 / T5'),('JFK','John F. Kennedy International','New York','USA','America/New_York','Operational','T1 / T4 / T5 / T8'),('DOH','Hamad International','Doha','Qatar','Asia/Qatar','Operational','Concourse A / B / C'),('HND','Haneda Airport','Tokyo','Japan','Asia/Tokyo','Operational','T1 / T2 / T3')
on conflict (code) do update set timezone=excluded.timezone,status=excluded.status,terminal_info=excluded.terminal_info;
