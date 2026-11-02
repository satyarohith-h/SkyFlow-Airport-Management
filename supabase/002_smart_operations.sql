-- SkyFlow 2.0 smart operations extension. All navigation, queue and service data is explicitly demo/simulated.
create table if not exists public.airport_facilities (
  id uuid primary key default uuid_generate_v4(), airport_id uuid references public.airports(id) on delete cascade,
  name text not null, category text not null, location text not null, accessible boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.airport_queues (
  id uuid primary key default uuid_generate_v4(), airport_id uuid references public.airports(id) on delete cascade,
  name text not null, queue_type text not null, estimated_wait_minutes integer not null default 0,
  queue_length integer not null default 0, open boolean not null default true, is_simulated boolean not null default true,
  updated_at timestamptz not null default now()
);
create table if not exists public.queue_tokens (
  id uuid primary key default uuid_generate_v4(), queue_id uuid references public.airport_queues(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade, token text unique not null,
  status text not null default 'Waiting', joined_at timestamptz not null default now()
);
create table if not exists public.document_verifications (
  id uuid primary key default uuid_generate_v4(), user_id uuid references public.profiles(id) on delete cascade,
  booking_id uuid references public.bookings(id), status text not null default 'Pending review',
  document_types text[] not null default '{}', reviewer_id uuid references public.profiles(id),
  submitted_at timestamptz not null default now(), reviewed_at timestamptz, review_note text
);
create table if not exists public.assistance_requests (
  id uuid primary key default uuid_generate_v4(), user_id uuid references public.profiles(id) on delete cascade,
  airport_id uuid references public.airports(id), request_type text not null, location text,
  status text not null default 'Requested', assigned_staff_id uuid references public.profiles(id),
  created_at timestamptz not null default now(), completed_at timestamptz
);
create table if not exists public.operational_incidents (
  id uuid primary key default uuid_generate_v4(), airport_id uuid references public.airports(id),
  title text not null, incident_type text not null, priority text not null default 'Low',
  status text not null default 'Open', owner_id uuid references public.profiles(id), resolution_notes text,
  created_at timestamptz not null default now(), resolved_at timestamptz
);
create table if not exists public.service_catalog (
  id uuid primary key default uuid_generate_v4(), airport_id uuid references public.airports(id),
  provider_name text not null, category text not null, location text, items jsonb not null default '[]'::jsonb,
  is_simulated boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.role_permissions (
  id uuid primary key default uuid_generate_v4(), role public.user_role not null, permission text not null,
  unique(role, permission)
);
create index if not exists airport_facilities_search_idx on public.airport_facilities(airport_id, category);
create index if not exists airport_queues_status_idx on public.airport_queues(airport_id, open, queue_type);
create index if not exists assistance_requests_user_idx on public.assistance_requests(user_id, created_at desc);
create index if not exists incidents_status_idx on public.operational_incidents(airport_id, status, priority);
alter table public.airport_facilities enable row level security;
alter table public.airport_queues enable row level security;
alter table public.queue_tokens enable row level security;
alter table public.document_verifications enable row level security;
alter table public.assistance_requests enable row level security;
create policy "authenticated users read facilities" on public.airport_facilities for select using (auth.role() = 'authenticated');
create policy "authenticated users read queues" on public.airport_queues for select using (auth.role() = 'authenticated');
create policy "users read own queue tokens" on public.queue_tokens for select using (auth.uid() = user_id);
create policy "users read own verification" on public.document_verifications for select using (auth.uid() = user_id);
create policy "users read own assistance" on public.assistance_requests for select using (auth.uid() = user_id);
