-- Shared passenger service workflows. Run after 009_transactional_flight_booking.sql.
begin;

create table if not exists public.passenger_service_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check (request_type in (
    'Hotel booking','Airport taxi','Parking reservation','Dining order','Shopping assistance',
    'Wheelchair assistance','Elderly passenger assistance','Medical assistance','Unaccompanied minor support',
    'Hearing assistance','Visual assistance','Lost baggage','Delayed baggage','Baggage delivery',
    'Special meal request','Lounge access','Porter service','Language assistance','Airport escort',
    'Pet travel assistance','Accessibility support','Travel document help','Flight disruption support',
    'Refund request','Booking change','Passenger complaint','Service feedback','Lost and found',
    'Airport shuttle','General support'
  )),
  title text not null check (char_length(title) between 3 and 120),
  description text not null check (char_length(description) between 8 and 3000),
  location text,
  details jsonb not null default '{}'::jsonb,
  status text not null default 'Submitted' check (status in ('Submitted','Acknowledged','In progress','Waiting for passenger','Resolved','Rejected')),
  priority text not null default 'Normal' check (priority in ('Low','Normal','High','Urgent')),
  admin_response text,
  assigned_to uuid references public.profiles(id) on delete set null,
  changed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists passenger_service_requests_user_created_idx
  on public.passenger_service_requests(user_id, created_at desc);
create index if not exists passenger_service_requests_status_priority_idx
  on public.passenger_service_requests(status, priority, created_at desc);

alter table public.passenger_service_requests enable row level security;

drop policy if exists "passengers create own service requests" on public.passenger_service_requests;
create policy "passengers create own service requests"
  on public.passenger_service_requests for insert
  with check (user_id = auth.uid());

drop policy if exists "passengers read own service requests" on public.passenger_service_requests;
create policy "passengers read own service requests"
  on public.passenger_service_requests for select
  using (user_id = auth.uid() or public.is_airport_operator());

drop policy if exists "airport operators update service requests" on public.passenger_service_requests;
create policy "airport operators update service requests"
  on public.passenger_service_requests for update
  using (public.is_airport_operator())
  with check (public.is_airport_operator());

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.passenger_service_requests;
  end if;
exception when duplicate_object then
  null;
end $$;

commit;
