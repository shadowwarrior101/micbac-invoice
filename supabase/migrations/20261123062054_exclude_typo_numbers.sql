-- Leave hand-typed outlier numbers out of next-number calculation.
-- Three FY 26-27 invoices were saved with date-like typos (829, 0905, 907)
-- while the real sequence is at 057, so the next invoice came out as 908.
-- The records keep their numbers (they may already have been sent);
-- they're only ignored when working out the next number.

alter table public.invoice_documents
  add column exclude_from_numbering boolean not null default false;

update public.invoice_documents
set exclude_from_numbering = true
where doc_type = 'invoice'
  and upper(trim(doc_no)) in ('MIPLWB/829/26-27', 'MIPLWB/0905/26-27', 'MIPLWB/907/26-27');

create or replace function public.invoice_max_seq(p_doc_type text, p_prefix text, p_fy text)
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
    where d.doc_type = p_doc_type
      and not d.exclude_from_numbering
      and left(upper(trim(d.doc_no)), length(p_prefix)) = upper(p_prefix)
  ) s
  where public.invoice_access() is not null
    and s.rest ~ '^\d{1,9}/[^/]+$'
    and split_part(s.rest, '/', 2) = p_fy;
$$;
