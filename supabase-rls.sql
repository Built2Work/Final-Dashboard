-- ============================================================================
--  Built to Work — Dashboard Row-Level Security (RLS) policies
-- ============================================================================
--  WHY THIS FILE EXISTS
--  The dashboard is a static client-side app. The Supabase *anon* key is, by
--  design, embedded in the page source and therefore public. That is fine ONLY
--  if Row-Level Security is enabled and correctly scoped on every table — RLS is
--  the ONLY thing actually stopping a visitor from reading all candidate PII.
--  The per-company / per-phone filtering done in JavaScript is convenience only;
--  it provides NO security on its own.
--
--  HOW TO APPLY
--  Supabase Dashboard -> SQL Editor -> paste this whole file -> Run.
--  Re-running is safe: every statement is idempotent (DROP ... IF EXISTS first).
--
--  ACCESS MODEL THIS SCRIPT IMPLEMENTS
--   * Staff/admin users  -> full read of the three event tables. Identified by
--                           membership in the new `admins` table (see STEP 1).
--                           These are the people who use index.html / operations.html.
--   * Company users      -> identified by a row in `companies` whose `email`
--                           matches their auth email. They can read ONLY:
--                             - their own `companies` row
--                             - `candidate_assignments` for their company
--                             - event-table rows whose phone is assigned to them
--                           They use customer.html.
--   * Everyone else      -> no access.
--
--  IMPORTANT: review the table/column names below against your actual schema
--  before running. Quoted identifiers ("Mobile Phone") are case/space sensitive.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 1 — Admin/staff registry
-- Add the email of every staff member who should see ALL event data.
-- ----------------------------------------------------------------------------
create table if not exists public.admins (
  email text primary key
);
-- Seed it (replace with your real staff emails):
-- insert into public.admins(email) values ('joe@built2work.com') on conflict do nothing;

-- Only admins may read the admins table; nobody can modify it via the API.
alter table public.admins enable row level security;
drop policy if exists admins_self_read on public.admins;
create policy admins_self_read on public.admins
  for select to authenticated
  using ( lower(email) = lower(auth.jwt() ->> 'email') );


-- ----------------------------------------------------------------------------
-- STEP 2 — Helper functions (security definer so they can read across tables)
-- ----------------------------------------------------------------------------

-- Phone normalizer mirroring the dashboard's JS normalizePhone():
-- strip non-digits, drop a leading country-code "1", keep the last 9 digits.
create or replace function public.normalize_phone(p text)
returns text
language sql
immutable
as $$
  select right(regexp_replace(regexp_replace(coalesce(split_part(p, '.', 1), ''), '\D', '', 'g'), '^1', ''), 9)
$$;

-- Is the current user a staff/admin?
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins a
    where lower(a.email) = lower(auth.jwt() ->> 'email')
  )
$$;

-- The company id (if any) that the current user belongs to.
create or replace function public.my_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.id from public.companies c
  where lower(c.email) = lower(auth.jwt() ->> 'email')
  limit 1
$$;

-- The set of normalized phones assigned to the current user's company.
create or replace function public.my_assigned_phones()
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select ca.phone from public.candidate_assignments ca
  where ca.company_id = public.my_company_id()
$$;


-- ----------------------------------------------------------------------------
-- STEP 3 — companies: a user may read only their own company row
-- ----------------------------------------------------------------------------
alter table public.companies enable row level security;

drop policy if exists companies_self_read on public.companies;
create policy companies_self_read on public.companies
  for select to authenticated
  using ( lower(email) = lower(auth.jwt() ->> 'email') or public.is_admin() );


-- ----------------------------------------------------------------------------
-- STEP 4 — candidate_assignments: scoped to the user's own company
-- (admins get full access for management from index.html)
-- ----------------------------------------------------------------------------
alter table public.candidate_assignments enable row level security;

drop policy if exists ca_select on public.candidate_assignments;
create policy ca_select on public.candidate_assignments
  for select to authenticated
  using ( company_id = public.my_company_id() or public.is_admin() );

drop policy if exists ca_insert on public.candidate_assignments;
create policy ca_insert on public.candidate_assignments
  for insert to authenticated
  with check ( company_id = public.my_company_id() or public.is_admin() );

drop policy if exists ca_update on public.candidate_assignments;
create policy ca_update on public.candidate_assignments
  for update to authenticated
  using ( company_id = public.my_company_id() or public.is_admin() )
  with check ( company_id = public.my_company_id() or public.is_admin() );

drop policy if exists ca_delete on public.candidate_assignments;
create policy ca_delete on public.candidate_assignments
  for delete to authenticated
  using ( company_id = public.my_company_id() or public.is_admin() );


-- ----------------------------------------------------------------------------
-- STEP 5 — Event tables: admins read all; company users read only the rows
-- whose (normalized) phone is assigned to them.
-- NOTE: the phone column differs per table — adjust the quoted names if needed.
-- ----------------------------------------------------------------------------

-- web_registration : phone column = "Mobile Phone"
alter table public.web_registration enable row level security;
drop policy if exists web_read on public.web_registration;
create policy web_read on public.web_registration
  for select to authenticated
  using (
    public.is_admin()
    or public.normalize_phone("Mobile Phone") in (select public.my_assigned_phones())
  );

-- exc_truck_loading : phone column = "Login Code"
alter table public.exc_truck_loading enable row level security;
drop policy if exists exc_read on public.exc_truck_loading;
create policy exc_read on public.exc_truck_loading
  for select to authenticated
  using (
    public.is_admin()
    or public.normalize_phone("Login Code") in (select public.my_assigned_phones())
  );

-- windows_trivia : phone columns = "Mobile Phone" (fallback "QR Code Scan")
alter table public.windows_trivia enable row level security;
drop policy if exists win_read on public.windows_trivia;
create policy win_read on public.windows_trivia
  for select to authenticated
  using (
    public.is_admin()
    or public.normalize_phone(coalesce("Mobile Phone", "QR Code Scan")) in (select public.my_assigned_phones())
  );


-- ----------------------------------------------------------------------------
-- STEP 6 — Storage bucket: candidate-files
-- Path convention used by the app: assignments/{phone}_{company_id}_{ts}.{ext}
-- Company users may read/write only files whose embedded company_id is theirs.
-- ----------------------------------------------------------------------------
drop policy if exists cf_read on storage.objects;
create policy cf_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'candidate-files'
    and (
      public.is_admin()
      or split_part(split_part(name, '/', 2), '_', 2)::uuid = public.my_company_id()
    )
  );

drop policy if exists cf_write on storage.objects;
create policy cf_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'candidate-files'
    and (
      public.is_admin()
      or split_part(split_part(name, '/', 2), '_', 2)::uuid = public.my_company_id()
    )
  );

drop policy if exists cf_update on storage.objects;
create policy cf_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'candidate-files'
    and (
      public.is_admin()
      or split_part(split_part(name, '/', 2), '_', 2)::uuid = public.my_company_id()
    )
  );


-- ----------------------------------------------------------------------------
-- PERFORMANCE NOTE
-- The event-table policies normalize the phone per row. On large tables add a
-- generated, indexed column to avoid a full scan per query, e.g.:
--
--   alter table public.web_registration
--     add column if not exists phone_norm text
--     generated always as (public.normalize_phone("Mobile Phone")) stored;
--   create index if not exists web_phone_norm_idx on public.web_registration(phone_norm);
--
-- then change the policy to compare against phone_norm directly.
-- (generated columns require the function to be IMMUTABLE — normalize_phone is.)
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- VERIFY (run after applying):
--   select tablename, rowsecurity from pg_tables
--   where schemaname='public'
--     and tablename in ('web_registration','exc_truck_loading','windows_trivia',
--                       'companies','candidate_assignments','admins');
--   -- rowsecurity must be true for every row.
-- Then log in as a company user and confirm you can only see your own rows.
-- ----------------------------------------------------------------------------
