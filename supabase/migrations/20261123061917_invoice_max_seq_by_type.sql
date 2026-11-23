-- Count a number series only within its own document type.
-- Quotations issued before the per-series prefixes existed were numbered
-- MIPLWB/NNN (e.g. MIPLWB/90712/26-27), so a prefix-only match made the
-- next invoice number jump to 90713. Series <-> type: MIPLWB/ = invoice,
-- MIPLWB/PI/ = proforma, MIPLWB/QT/ = quotation.

drop function public.invoice_max_seq(text, text);

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
      and left(upper(trim(d.doc_no)), length(p_prefix)) = upper(p_prefix)
  ) s
  where public.invoice_access() is not null
    and s.rest ~ '^\d{1,9}/[^/]+$'
    and split_part(s.rest, '/', 2) = p_fy;
$$;

revoke all on function public.invoice_max_seq(text, text, text) from public, anon;
grant execute on function public.invoice_max_seq(text, text, text) to authenticated;
