-- Restricted users (exports@) may only create proformas and quotations —
-- never commercial (tax) invoices. Enforced on insert and on update so a
-- direct API call can't create one or turn an existing row into one.
-- (Official letters are generated in the browser and never stored, so the
-- site's UI is what blocks those.)

drop policy invoice_documents_insert on public.invoice_documents;
create policy invoice_documents_insert on public.invoice_documents
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and (
      public.invoice_access() = 'full'
      or (public.invoice_access() = 'restricted' and doc_type in ('proforma', 'quotation'))
    )
  );

drop policy invoice_documents_update on public.invoice_documents;
create policy invoice_documents_update on public.invoice_documents
  for update to authenticated
  using (public.invoice_access() is not null and created_by = auth.uid())
  with check (
    created_by = auth.uid()
    and (
      public.invoice_access() = 'full'
      or (public.invoice_access() = 'restricted' and doc_type in ('proforma', 'quotation'))
    )
  );
