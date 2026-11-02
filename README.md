# SkyFlow Airport Management

SkyFlow is a connected airport operations simulation with Passenger and Admin workspaces. It includes JWT demo authentication, a live simulated flight board, passenger trips, check-in and boarding-pass data, baggage status, smart guidance, terminal navigation, queues, document review, assistance requests, notifications, admin operational metrics, and protected flight updates.

## Run locally

1. Install Node.js 20+.
2. Run `npm install` at the repository root.
3. Copy `server/.env.example` to `server/.env` and set `JWT_SECRET` (PostgreSQL is optional for the demo API).
4. Run `npm run dev`.
5. Open `http://localhost:5173`.

The frontend homepage is `http://localhost:5173/`. The backend health endpoint is `http://localhost:4000/api/health`.

Demo accounts: `admin@skyflow.demo / admin123` and `passenger@skyflow.demo / passenger123`.

The PostgreSQL/Supabase foundation is in `supabase/001_initial_schema.sql`. Apply migrations through `supabase/009_transactional_flight_booking.sql` in order. The server uses a server-only Supabase HTTPS adapter for Auth, profiles, flight inventory, bookings, check-in, boarding, airport operations, support, announcements, reports, settings, and audit records. Supabase-configured workflows fail closed; they do not fall back to in-memory demo data.

## Current security and operations surface

The API now includes passenger registration, password-reset handoff messaging, profile updates/deactivation, role-aware JWT authorization, rate limiting, administrator invitations and account activation, support tickets, announcements, runway/gate operations, audit logs, reports, and configurable operational settings. New public registrations are always created as `passenger`; administrator roles can only be provisioned through the protected administrator API.

Apply migrations in filename order through `supabase/009_transactional_flight_booking.sql`. Migrations 006–009 add staff, shifts, runways, screening, maintenance, support, administrator invitations, settings, boarding passes, baggage history, ticket history, notification delivery state, Auth profile synchronization, atomic seat/booking workflows, flight capacity and gate-overlap guards, status-history triggers, indexes, and scoped RLS policies. Supabase Auth email delivery must be configured for verification, invitation, and password-reset emails. `DEMO_MODE=true` is opt-in for the isolated test harness only; normal server starts default to `unconfigured` when Supabase variables are absent.

### API examples

`POST /api/auth/register`, `POST /api/auth/forgot-password`, `GET/PATCH /api/profile`, `GET/POST/PATCH /api/admin/users`, `GET/PATCH /api/operations/runways`, `GET/POST/PATCH /api/support/tickets`, `GET/POST /api/announcements`, `GET /api/reports/summary`, `GET /api/audit-logs`, and `GET/PATCH /api/settings` are protected according to role and ownership. Financial values and flight operations remain explicitly simulated.

### Production checklist

1. Configure Supabase Auth and email delivery.
2. Apply migrations 001 through 009 without resetting the database.
3. Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and server-only `SUPABASE_SERVICE_ROLE_KEY`; leave `DEMO_MODE=false` (the default).
4. Bootstrap the first administrator below. Provide valid airport, airline, terminal, gate, and aircraft records before scheduling flights.
5. Set a strong `AUTH_REDIRECT_URL` allowlisted in Supabase Auth, exact `CLIENT_ORIGINS`, and run `npm test` and `npm run build` before deployment. The test runner opts into an isolated demo fixture on port 4100; production does not.

### First Super Administrator bootstrap

1. Register through the passenger signup and verify the email using your configured Supabase Auth provider.
2. In the Supabase SQL editor as the project owner, replace the email literal below with that verified account. This bootstrap does not create or set a password and is not exposed through the application API:

```sql
do $$
declare verified_user uuid;
begin
  select id into verified_user
  from auth.users
  where lower(email) = lower('your-verified-admin@example.com')
    and email_confirmed_at is not null;
  if verified_user is null then
    raise exception 'No verified Supabase Auth user found for bootstrap';
  end if;
  update public.profiles set role = 'super-admin', active = true, updated_at = now()
  where id = verified_user;
  if not found then raise exception 'Profile bootstrap failed'; end if;
end $$;
```

3. Sign in via the page menu’s **Administrator Login**. Provision additional staff only through the Super Administrator workflow. Do not expose the service-role key to the frontend.


## Passenger service centre (new)

The passenger **Services** page now contains 30 request types (hotel, taxi, parking, dining, accessibility, medical help, baggage issues, refunds, complaints, support and more). A passenger submits a request with details and location. The **Passenger requests** page in the Admin workspace lists the same records and allows an administrator to change status/priority and add a response. Both dashboards refresh the shared request list every 15 seconds.

### Apply the new database migration

After applying migrations `001` through `009`, run:

`supabase/010_passenger_service_requests.sql`

This creates the shared `passenger_service_requests` table, indexes, row-level security policies and Realtime publication membership (when the Supabase Realtime publication exists).

### New API

- `GET /api/service-requests` — passengers see only their own requests; administrators see all requests.
- `POST /api/service-requests` — passenger-only request creation.
- `PATCH /api/service-requests/:id` — administrator-only status, priority, assignment and response updates.

The local demo mode keeps requests in server memory and labels the API response as simulated. Persistent cross-session and cross-instance operation requires Supabase configuration and migration `010`.

### Run locally

1. Copy `server/.env.example` to `server/.env` and configure Supabase settings (or explicitly enable the repository's local demo mode for local testing only).
2. Copy `client/.env.example` to `client/.env` and set `VITE_API_URL` to your backend API URL.
3. From the repository root run `npm install`, then `npm run dev`.
4. Apply the SQL migration before testing persistent service requests.
