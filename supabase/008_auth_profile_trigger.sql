-- Keep Supabase Auth identities and application profiles synchronized.
-- Run after 007_workflow_integrity.sql.
begin;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)), new.email, 'passenger')
  on conflict (id) do update set email = excluded.email, updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create policy "users update own profile" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
revoke update on public.profiles from authenticated;
grant update(full_name, phone, preferences) on public.profiles to authenticated;
revoke insert on public.profiles from anon, authenticated;

commit;
