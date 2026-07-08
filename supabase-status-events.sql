-- ============================================================================
-- supabase-status-events.sql — status-change tracking, rejection history,
-- and Hired/Rejected notifications for the pipeline.
--
-- Run this ONCE in the Supabase SQL editor, AFTER supabase-rls.sql (it reuses
-- the is_admin() and my_company_id() helpers defined there).
-- Safe to re-run: every statement is idempotent.
--
-- What it does:
--   1. Adds status_changed_at + rejection_reason columns to
--      candidate_assignments (backfilling status_changed_at from updated_at).
--   2. Creates status_events — an append-only log of every status change,
--      keyed by phone so rejection history survives unassignment and spans
--      companies.
--   3. Installs a BEFORE UPDATE trigger that atomically stamps
--      status_changed_at and writes the status_events row whenever status
--      changes, no matter which app made the change. Events caused by staff
--      (admins) are born seen = true so staff never notify themselves.
--   4. Locks status_events down: clients can only SELECT (scoped by RLS);
--      the only client write allowed is admins flipping the `seen` flag.
--      All inserts happen through the trigger.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 1 — columns on candidate_assignments
-- ----------------------------------------------------------------------------
alter table public.candidate_assignments
  add column if not exists status_changed_at timestamptz;
alter table public.candidate_assignments
  add column if not exists rejection_reason text;

-- One-time backfill so existing rows show a plausible "changed X ago".
update public.candidate_assignments
  set status_changed_at = updated_at
  where status_changed_at is null;


-- ----------------------------------------------------------------------------
-- STEP 2 — status_events: append-only status-change log
-- ----------------------------------------------------------------------------
create table if not exists public.status_events (
  id            uuid primary key default gen_random_uuid(),
  -- keep the event even if the assignment row is later deleted (unassigned)
  assignment_id uuid references public.candidate_assignments(id) on delete set null,
  phone         text not null,
  company_id    uuid,          -- no FK: history must survive company deletion
  company_name  text,          -- denormalized for the same reason
  old_status    text,
  new_status    text not null,
  reason        text,          -- rejection reason typed by the company
  changed_by    text,          -- email of the user who made the change
  changed_at    timestamptz not null default now(),
  seen          boolean not null default false
);

create index if not exists se_phone_idx on public.status_events (phone);
create index if not exists se_feed_idx  on public.status_events (changed_at desc)
  where new_status in ('Hired','Rejected');


-- ----------------------------------------------------------------------------
-- STEP 3 — trigger: stamp status_changed_at + log the event atomically
-- ----------------------------------------------------------------------------
create or replace function public.log_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    new.status_changed_at := now();
    insert into public.status_events
      (assignment_id, phone, company_id, company_name, old_status, new_status,
       reason, changed_by, seen)
    values
      (new.id, new.phone, new.company_id,
       (select c.name from public.companies c where c.id = new.company_id),
       old.status, new.status,
       case when new.status = 'Rejected' then new.rejection_reason end,
       coalesce(auth.jwt() ->> 'email', ''),
       public.is_admin());   -- staff-authored changes never notify staff
  end if;
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists trg_status_change on public.candidate_assignments;
create trigger trg_status_change
  before update on public.candidate_assignments
  for each row execute function public.log_status_change();


-- ----------------------------------------------------------------------------
-- STEP 4 — RLS + grants: read-only for clients, trigger does all inserts
-- ----------------------------------------------------------------------------
alter table public.status_events enable row level security;

-- Companies see their own events; admins see everything.
drop policy if exists se_select on public.status_events;
create policy se_select on public.status_events
  for select to authenticated
  using ( public.is_admin() or company_id = public.my_company_id() );

-- Only admins may update (and only the seen column, per the grant below).
drop policy if exists se_update on public.status_events;
create policy se_update on public.status_events
  for update to authenticated
  using ( public.is_admin() )
  with check ( public.is_admin() );

-- No client-side insert/delete: the security-definer trigger bypasses these.
revoke insert, update, delete on public.status_events from anon, authenticated;
grant  select        on public.status_events to authenticated;
grant  update (seen) on public.status_events to authenticated;


-- ----------------------------------------------------------------------------
-- Verify (optional): run after applying
-- ----------------------------------------------------------------------------
-- select column_name from information_schema.columns
--   where table_name = 'candidate_assignments'
--     and column_name in ('status_changed_at','rejection_reason');
-- select tgname from pg_trigger where tgname = 'trg_status_change';
-- select rowsecurity from pg_tables where tablename = 'status_events';
