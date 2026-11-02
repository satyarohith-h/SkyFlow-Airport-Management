-- SkyFlow operational hardening and workflow tables.
-- Additive migration: run after 005_passenger_booking_system.sql.
begin;

alter type public.user_role add value if not exists 'super-admin';
alter type public.user_role add value if not exists 'airport-admin';
alter type public.user_role add value if not exists 'operations-manager';
alter type public.user_role add value if not exists 'check-in-staff';
alter type public.user_role add value if not exists 'gate-staff';
alter type public.user_role add value if not exists 'security-staff';

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(), name text not null unique, created_at timestamptz not null default now()
);
create table if not exists public.staff (
  id uuid primary key references public.profiles(id) on delete cascade, employee_number text unique not null,
  department_id uuid references public.departments(id), title text, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.shifts (
  id uuid primary key default gen_random_uuid(), staff_id uuid not null references public.staff(id) on delete cascade,
  starts_at timestamptz not null, ends_at timestamptz not null, status text not null default 'Scheduled',
  check (ends_at > starts_at), created_at timestamptz not null default now()
);
create table if not exists public.runways (
  id uuid primary key default gen_random_uuid(), code text not null unique, status text not null default 'Operational',
  maintenance_due date, updated_at timestamptz not null default now(), check (status in ('Operational','Maintenance','Closed'))
);
create table if not exists public.security_screenings (
  id uuid primary key default gen_random_uuid(), booking_id uuid references public.bookings(id) on delete set null,
  passenger_id uuid references public.profiles(id) on delete set null, status text not null default 'Pending',
  notes text, screened_by uuid references public.profiles(id), screened_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.incident_history (
  id uuid primary key default gen_random_uuid(), incident_id uuid not null references public.operational_incidents(id) on delete cascade,
  from_status text, to_status text not null, actor_id uuid references public.profiles(id), notes text, created_at timestamptz not null default now()
);
create table if not exists public.equipment (
  id uuid primary key default gen_random_uuid(), asset_tag text not null unique, name text not null, location text,
  status text not null default 'Operational', created_at timestamptz not null default now()
);
create table if not exists public.maintenance_work_orders (
  id uuid primary key default gen_random_uuid(), equipment_id uuid references public.equipment(id) on delete cascade,
  title text not null, priority text not null default 'Normal', status text not null default 'Open', due_at timestamptz,
  assigned_to uuid references public.profiles(id), completed_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject text not null, description text not null, priority text not null default 'Normal', status text not null default 'Open',
  assigned_to uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.admin_invitations (
  id uuid primary key default gen_random_uuid(), email text not null, role public.user_role not null,
  invited_by uuid not null references public.profiles(id), status text not null default 'Pending setup', expires_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.system_settings (
  key text primary key, value jsonb not null default '{}'::jsonb, updated_by uuid references public.profiles(id), updated_at timestamptz not null default now()
);

create index if not exists support_tickets_user_status_idx on public.support_tickets(user_id,status,created_at desc);
create index if not exists maintenance_due_idx on public.maintenance_work_orders(status,due_at);
create index if not exists screening_status_idx on public.security_screenings(status,created_at desc);
alter table public.departments enable row level security;
alter table public.staff enable row level security;
alter table public.shifts enable row level security;
alter table public.runways enable row level security;
alter table public.security_screenings enable row level security;
alter table public.equipment enable row level security;
alter table public.maintenance_work_orders enable row level security;
alter table public.support_tickets enable row level security;
alter table public.admin_invitations enable row level security;
alter table public.system_settings enable row level security;

create or replace function public.is_airport_operator() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role::text in ('super-admin','airport-admin','operations-manager','check-in-staff','gate-staff','security-staff','admin'));
$$;
create policy "operators read departments" on public.departments for select using (public.is_airport_operator());
create policy "operators manage runways" on public.runways for all using (public.is_airport_operator()) with check (public.is_airport_operator());
create policy "users own support tickets" on public.support_tickets for select using (user_id = auth.uid() or public.is_airport_operator());
create policy "users create support tickets" on public.support_tickets for insert with check (user_id = auth.uid());
create policy "operators manage support tickets" on public.support_tickets for update using (public.is_airport_operator()) with check (public.is_airport_operator());
create policy "operators manage system settings" on public.system_settings for all using (public.is_airport_operator()) with check (public.is_airport_operator());

commit;
