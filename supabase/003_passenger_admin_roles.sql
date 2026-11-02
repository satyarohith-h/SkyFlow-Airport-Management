-- Consolidate authentication to Passenger and Admin only.
-- Legacy staff records are retained and mapped to Admin so no profile data is deleted.
begin;
alter table if exists public.profiles alter column role drop default;
alter type public.user_role rename to user_role_legacy;
create type public.user_role as enum ('admin','passenger');
alter table if exists public.profiles alter column role type public.user_role
  using case when role::text = 'passenger' then 'passenger'::public.user_role else 'admin'::public.user_role end;
alter table if exists public.role_permissions alter column role type public.user_role
  using case when role::text = 'passenger' then 'passenger'::public.user_role else 'admin'::public.user_role end;
drop type public.user_role_legacy;
alter table if exists public.profiles alter column role set default 'passenger';
commit;
