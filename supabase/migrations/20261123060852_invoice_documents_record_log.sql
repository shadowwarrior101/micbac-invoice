-- Reshape invoice_documents to match how the site actually records documents
-- (it replaces the Google Sheet "Invoice Records" log):
--   * Append-only log semantics: every changed re-issue is a new row, so the
--     same number can appear many times (the Sheet has 26 such numbers).
--   * One number series per prefix (MIPLWB/, MIPLWB/PI/, MIPLWB/QT/), matched
--     exactly — MIPLWB/QT/005 must not count toward MIPLWB/ invoices.
--   * Columns mirror the Sheet record (POL/POD/items, display date).
--   * Rows imported from the Sheet keep their original timestamp and may lack
--     form data (the oldest records predate draftJson).

-- Guard: only reshape while empty, so this can never drop real data.
do $$
begin
  if exists (select 1 from public.invoice_documents) then
    raise exception 'invoice_documents is not empty; refusing to reshape it';
  end if;
end;
$$;

drop index public.invoice_documents_type_no_key;
create index invoice_documents_type_no_idx
  on public.invoice_documents (doc_type, upper(trim(doc_no)));

alter table public.invoice_documents
  alter column doc_date type text using doc_date::text,  -- as printed, dd.mm.yyyy
  alter column data drop not null,
  add column pol    text,
  add column pod    text,
  add column items  integer,
  add column source text not null default 'app' check (source in ('app', 'sheet_import'));

-- Signed-in users get ownership/timestamps stamped by the server. Privileged
-- sessions with no JWT (SQL editor, the one-off Sheet import) keep the values
-- they supply, so imported rows retain their original created_at.
create or replace function public.invoice_documents_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.created_by       := auth.uid();
      new.created_by_email := lower(auth.jwt() ->> 'email');
      new.created_at       := now();
      new.source           := 'app';
    else
      new.created_by       := old.created_by;
      new.created_by_email := old.created_by_email;
      new.created_at       := old.created_at;
      new.source           := old.source;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Per-series max, exact prefix: invoice_max_seq('MIPLWB/', '26-27') counts
-- 'MIPLWB/057/26-27' but not 'MIPLWB/QT/057/26-27'. Spans ALL documents
-- (restricted users included) and returns only a number.
drop function public.invoice_max_seq(text);

create or replace function public.invoice_max_seq(p_prefix text, p_fy text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  -- rest = what follows the prefix; it must be exactly '<digits>/<fy>'.
  select coalesce(max(split_part(s.rest, '/', 1)::int), 0)
  from (
    select substring(upper(trim(d.doc_no)) from length(p_prefix) + 1) as rest
    from public.invoice_documents d
    where left(upper(trim(d.doc_no)), length(p_prefix)) = upper(p_prefix)
  ) s
  where public.invoice_access() is not null
    and s.rest ~ '^\d{1,9}/[^/]+$'
    and split_part(s.rest, '/', 2) = p_fy;
$$;

revoke all on function public.invoice_max_seq(text, text) from public, anon;
grant execute on function public.invoice_max_seq(text, text) to authenticated;
