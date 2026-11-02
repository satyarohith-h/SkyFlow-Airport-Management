-- Phase 3: passenger booking, payment, seat allocation and audit foundation.
-- Additive migration; existing booking rows remain valid.
alter table public.bookings add column if not exists contact_email text;
alter table public.bookings add column if not exists contact_phone text;
alter table public.bookings add column if not exists base_fare numeric(12,2) not null default 0;
alter table public.bookings add column if not exists taxes numeric(12,2) not null default 0;
alter table public.bookings add column if not exists baggage_addons numeric(12,2) not null default 0;
alter table public.bookings add column if not exists payment_status text not null default 'Pending';
alter table public.bookings add column if not exists idempotency_key text;
create unique index if not exists bookings_idempotency_key_idx on public.bookings(idempotency_key) where idempotency_key is not null;
alter table public.booking_passengers add column if not exists date_of_birth date;
alter table public.booking_passengers add column if not exists contact_email text;
alter table public.booking_passengers add column if not exists contact_phone text;
alter table public.booking_passengers add column if not exists document_type text;
alter table public.booking_passengers add column if not exists document_last4 text;
create unique index if not exists booking_passengers_seat_idx on public.booking_passengers(seat_id) where seat_id is not null;
create table if not exists public.booking_payments (
  id uuid primary key default gen_random_uuid(), booking_id uuid references public.bookings(id) on delete cascade,
  amount numeric(12,2) not null check (amount >= 0), status text not null check (status in ('Pending','Completed','Failed','Refunded')),
  method text not null default 'Demo payment', provider_reference text, created_at timestamptz not null default now()
);
create table if not exists public.booking_audit_history (
  id uuid primary key default gen_random_uuid(), booking_id uuid not null references public.bookings(id) on delete cascade,
  from_status text, to_status text not null, actor_id uuid references public.profiles(id), notes text, created_at timestamptz not null default now()
);
create index if not exists booking_payments_booking_idx on public.booking_payments(booking_id,created_at desc);
create index if not exists booking_audit_booking_idx on public.booking_audit_history(booking_id,created_at desc);
alter table public.booking_payments enable row level security;
alter table public.booking_audit_history enable row level security;
create policy "passengers read own booking payments" on public.booking_payments for select using (exists (select 1 from public.bookings b where b.id=booking_id and b.user_id=auth.uid()));
