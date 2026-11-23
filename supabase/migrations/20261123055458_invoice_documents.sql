-- Saved invoices / proformas / quotations for the micbac-invoice site.
--
-- Lives in the shared "Micbac" project (same DB + auth pool as the orders
-- app). Purely additive: no existing table, policy or auth setting is touched.
--
-- Access model:
--   * Only emails in invoice_users may use the invoice site (the auth pool
--     also holds orders-app accounts that must not see invoices).
--   * restricted = false -> sees every document (how the site always worked).
--   * restricted = true  -> sees only documents they created themselves.
--   Documents created by a restricted user are still visible to everyone else.
--   * Only the creator can edit or delete a document.

-- ─── Allow-list ─────────────────────────────────────────────────────────────
-- Keyed by email (not user id) so a user can be listed before their account
-- is invited/created.
create table public.invoice_users (
  email      text primary key check (email = lower(trim(email)) and email like '%@%'),
  restricted boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.invoice_users enable row level security;
-- No policies: the table is read only through invoice_access() below.
revoke all on table public.invoice_users from anon, authenticated;
grant all on table public.invoice_users to service_role;

insert into public.invoice_users (email, restricted) values
  ('ops@micbacindia.com',    false),
  ('nilesh@micbacindia.com', false),
  ('micbac.india@gmail.com', false),
  ('exports@micbacindia.com', true);

-- 'full', 'restricted', or null (not allowed). The email comes from the
-- verified JWT, so it can't be spoofed by the client.
create or replace function public.invoice_access()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when u.restricted then 'restricted' else 'full' end
  from public.invoice_users u
  where u.email = lower(auth.jwt() ->> 'email');
$$;

revoke all on function public.invoice_access() from public, anon;
grant execute on function public.invoice_access() to authenticated;

-- ─── Documents ──────────────────────────────────────────────────────────────
create table public.invoice_documents (
  id               uuid primary key default gen_random_uuid(),
  doc_type         text not null check (doc_type in ('invoice', 'proforma', 'quotation')),
  doc_no           text not null check (length(trim(doc_no)) > 0),
  doc_date         date,
  party_name       text,
  amount           numeric(14, 2),
  currency         text,
  data             jsonb not null,  -- full form state; the app restores from this
  created_by       uuid not null default auth.uid() references auth.users (id),
  created_by_email text not null default lower(auth.jwt() ->> 'email'),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- One document per number per type. Also stops a restricted user from
-- unknowingly reusing a number that belongs to a document they can't see.
create unique index invoice_documents_type_no_key
  on public.invoice_documents (doc_type, upper(trim(doc_no)));
create index invoice_documents_updated_at_idx on public.invoice_documents (updated_at desc);
create index invoice_documents_created_by_idx on public.invoice_documents (created_by);

-- Ownership columns are server-controlled: stamped on insert, frozen on update.
create or replace function public.invoice_documents_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by       := auth.uid();
    new.created_by_email := lower(auth.jwt() ->> 'email');
    new.created_at       := now();
  else
    new.created_by       := old.created_by;
    new.created_by_email := old.created_by_email;
    new.created_at       := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger invoice_documents_stamp
  before insert or update on public.invoice_documents
  for each row execute function public.invoice_documents_stamp();

-- Highest sequence number used in a financial year across ALL documents
-- (restricted users included), e.g. 'MIPLWB/007/25-26' -> 7 for '25-26'.
-- Returns only a number, so it reveals nothing about hidden documents.
create or replace function public.invoice_max_seq(p_fy text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(substring(d.doc_no from '^[A-Z/]+(\d+)/')::int), 0)
  from public.invoice_documents d
  where public.invoice_access() is not null
    and d.doc_no like '%/' || p_fy
    and d.doc_no ~ '^[A-Z/]+\d+/';
$$;

revoke all on function public.invoice_max_seq(text) from public, anon;
grant execute on function public.invoice_max_seq(text) to authenticated;

-- ─── RLS + grants ───────────────────────────────────────────────────────────
alter table public.invoice_documents enable row level security;

create policy invoice_documents_select on public.invoice_documents
  for select to authenticated
  using (
    public.invoice_access() = 'full'
    or (public.invoice_access() = 'restricted' and created_by = auth.uid())
  );

create policy invoice_documents_insert on public.invoice_documents
  for insert to authenticated
  with check (public.invoice_access() is not null and created_by = auth.uid());

create policy invoice_documents_update on public.invoice_documents
  for update to authenticated
  using (public.invoice_access() is not null and created_by = auth.uid())
  with check (public.invoice_access() is not null and created_by = auth.uid());

create policy invoice_documents_delete on public.invoice_documents
  for delete to authenticated
  using (public.invoice_access() is not null and created_by = auth.uid());

revoke all on table public.invoice_documents from anon, authenticated;
grant select, insert, update, delete on table public.invoice_documents to authenticated;
grant all on table public.invoice_documents to service_role;
