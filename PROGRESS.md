# PROGRESS

## 2026-11-25 — Goods amount + port picker fixes

**Done**
- Goods table: a row's Amount now updates while typing Qty/Rate (`updateRowAmount`). It was only drawn on
  table rebuild, so the row being edited kept showing its old amount (e.g. $0.00 on a newly added row).
- Port pickers: "Clear selection" option at the top of the list once a port is chosen.
- Port of Loading is now validated on step ② (was marked required but never checked; it was always pre-filled
  with Kolkata, which can now be cleared).
- Verified on the live site: row 4 (28 × 2952) shows $82,656.00 as you type; clearing Mundra resets the picker.

## 2026-11-23 — Records move to Supabase; exports@ sees only its own

**Goal:** `exports@micbacindia.com` sees only the invoices / proformas / quotations it created; every
other user sees everything (including exports' records). Works the same as before for everyone else.

**Done**
- Records (the Records modal, next-number lookup, delete) now use Supabase table `invoice_documents`
  in the shared "Micbac" project instead of the Google Sheet / Apps Script. `apps-script/Code.gs` removed.
- Migrations (applied): `20261123055458_invoice_documents`, `20261123060852_invoice_documents_record_log`.
  - `invoice_users` allow-list (email, `restricted`): ops@, nilesh@, micbac.india@gmail.com full; exports@ restricted.
    Only listed emails can use the site — the auth pool also holds orders-app accounts.
  - RLS: full users read all rows; restricted users read only their own; only the creator can delete.
  - Append-only log, same as the Sheet (a changed re-issue adds a row; the fingerprint guard still skips identical ones).
  - `invoice_max_seq(prefix, fy)`: per-series max (MIPLWB/, MIPLWB/PI/, MIPLWB/QT/), exact prefix, across ALL rows,
    so exports never reuses a number it can't see.
- Magic-link login gate (`shouldCreateUser: false`, same as freightysh-invoice); Sign out in the nav.
- Records modal: new "Created By" column (also in CSV/Excel); delete button only on your own rows;
  "Clear All" became "Clear My Records" (RLS can't delete other people's rows anyway).
- Save/Load Draft stay per-browser localStorage, unchanged.
- Imported all 117 Sheet records (26 invoices, 91 quotations; 110 with form data) via
  `supabase db query --linked -f data-import/sheet-import.sql` (gitignored — real customer data). Original
  timestamps kept; full users see 117, exports sees 0.
- `20261123061917_invoice_max_seq_by_type`: series count only their own doc type. Pre-series quotations were
  numbered MIPLWB/NNN (e.g. MIPLWB/90712), which made the next invoice 90713 — the old Apps Script had the same flaw.
- `20261123062054_exclude_typo_numbers`: new `exclude_from_numbering` flag, set on the hand-typed invoices
  MIPLWB/829, /0905, /907 (26-27) so the next invoice is 058, not 908. Their numbers are unchanged.
  To ignore another outlier later: set `exclude_from_numbering = true` on that row (SQL editor).
- Verified: migration + RLS assertions run against the live DB in rolled-back transactions (both migrations); 12 unit tests pass.

**Decisions / deviations**
- Shared the Micbac Supabase project (user's choice). Trade-off: the orders app lets any logged-in user read
  orders/customers/logistics, so invoice-site users (incl. exports) can read that via the API.
- Imported Sheet rows are owned by nilesh@micbacindia.com and shown as "Imported (Sheet)"; exports doesn't see them.
- Sheet token was public, so the Sheet could never enforce per-user visibility — hence the move.

- `20261123064048_restricted_doc_types`: restricted users can insert/update only `proforma` and `quotation` rows
  (commercial invoices rejected by RLS). UI for restricted users: Official Letter hidden, invoice type locked to
  Proforma, makePDF refuses letters/commercial invoices. Letters are never stored, so that block is UI-only.
- Login uses the emailed one-time **code** (`verifyOtp`): the project's shared email template sends a code, not a
  link (the orders app relies on that), so the sign-in screen has a code field. Redirect URL was added by the user.
- Verified as a restricted user with a temporary test login (allow-listed as restricted, then removed): sees 0 of
  117 records, next numbers PI/001 and QT/003. It created no records. Its Supabase Auth account still exists — delete
  it under Authentication → Users if not needed.
- Deployed 2026-11-23: fast-forwarded `main` to the work and pushed; GitHub Pages serves
  https://shadowwarrior101.github.io/micbac-invoice/ (GitHub username changed from anupaminnit; remote updated).

**Pending**
- Invite exports@micbacindia.com in Supabase Auth (redirect URL is done).
- After import: undeploy the Apps Script web app (its public token still allows reading/wiping the Sheet).
- Logged-in UI not yet checked in a browser.

## 2026-09-28 — Seal toggle, proforma invoice, quotation weighing unit

**Done**
- Global "Include seal & signature" checkbox (next to doc-type bar) — applies to Invoice, Quotation and Letter. Unticked → the stamp+signature image is replaced by an equally sized blank box, so the printed copy can be stamped/signed by hand without layout shift. Saved in drafts.
- Invoice Type select (Commercial / Proforma) on step ① — invoice only. Proforma: "PROFORMA INVOICE" title + footer, no packing list sheet, logged to the Sheet as `docType: proforma` (Records modal already had a style for it).
- Quotation "Weighing Unit" dropdown (MT / KGS / LBS) on the Goods step, replacing the old free-text "Weight Unit". Drives goods-table headers, row unit names, RATE/<unit>, qty-total unit, and gross/net weight units in the PDF. Old drafts with free-text units are normalised (e.g. "kgs" → KGS).
- Fixed preview modal appending the literal text "undefined" when there is no packing-list sheet (quotation, proforma).

**Decisions**
- (Revised per user) The quotation weighing unit applies to weights only: goods-table Gross Wt header, Quotation Details gross/net weight, and those weights in the PDF. Qty is always MT and rate always RATE/MT; row units are never relabelled. Invoice weights stay KGS.
- Proforma shares the invoice numbering sequence (same `MIPLWB/NNN/FY` prefix). If proformas should not consume invoice numbers, give them their own prefix (e.g. `MIPLWB/PI/`) — the Sheet's `nextInvoiceNo` already handles any prefix.


## 2026-09-28 — Dead-code cleanup + bug audit

**Done** (index.html 443 KB → 320 KB, no behaviour change; e2e checks pass)
- Removed the unused jsPDF path: `buildDoc`, the jsPDF + autotable CDN scripts, and the `LOGO` base64 it alone used.
- Removed the unused `LH_LOGO` base64; the nav bar now reuses `LTR_LOGO` (the two logos were byte-identical).
- Removed the preview modal's dead iframe path (`previewFrame`, `_previewBlobUrl`, `if(false)` branch).
- Removed reads of the non-existent `notifyCountry` field, the unused `.tp`/`.tr` CSS, unused id attributes, and duplicate guards in the CSV/Excel export.

**Bug audit** — 19 issues found; top 6 fixed in the next session.

## 2026-09-28 — Bug fixes 1–6

**Done** (one commit each)
1. Escaped all user/Sheet data in the document builders, step-4 summary and Records table; record ids coerced to numbers in inline handlers.
2. Port restore via `restorePort` — matches by label, repairs already-corrupted records, clears the picker when a record has no port (also fixes the stale-POD issue).
3. Amount in words moved to `js/amount-words.js` with unit tests (`node --test`): lakh/crore for INR, million/billion otherwise; PENCE/FILS for GBP/AED.
4. Letter placeholder tagged with `.rte-ph`, never printed; empty letters can't be downloaded; button label restored correctly.
5. Record insert skipped when the same (type, number) was already saved with an identical form state (FNV hash in localStorage `micbac_saved_fp`).
6. Number series per type: `MIPLWB/` invoice, `MIPLWB/PI/` proforma, `MIPLWB/QT/` quotation; new FY restarts at 001; Clone asks the Sheet.

**Decisions / deviations**
- `js/amount-words.js` is the first file outside index.html — needed for unit tests; GitHub Pages serves it alongside.
- Duplicate-record guard is per browser (localStorage). A different device reprinting the same doc can still add a row; a server-side upsert in Code.gs would fix that but needs a redeploy.
- Historic quotations numbered `MIPLWB/NNN` stay in the Sheet and still count toward the invoice series max; no data was changed.

**Next — remaining audit items** — all fixed in the following session.

## 2026-09-28 — Remaining audit items (7–19)

**Done** (one commit each; 89 browser checks + 12 unit tests pass)
- Qty totals: `js/quantities.js` (unit-tested) — no float noise, totalled per unit ("28 METRIC TONNES + 18 BAGS").
- Documents: named consignee prints its own name/address; tax code under notify party; addresses keep line breaks; quotation prints Agent/Distributor; cleared Tolerance stays cleared.
- Progress-bar jumps validate every skipped step and land on the first incomplete one.
- Goods table escapes qty/rate/bags/weight (gap from the earlier escaping pass).
- Preview injects the sheets directly — packing list visible, no #s0/#s1 id clash.
- Invoice numbers normalised to upper-case (field on change, records, number tracking).
- Email Draft opens one window (the document) with an "Open Gmail draft" link in its toolbar — second popup was blocked by browsers.
- Letter fields included in Save/Load Draft; body sanitised on restore (`sanitizeRichText`); Sheet records omit letter fields.
- Letter date dd.mm.yyyy; `todayISO()` local-time helper replaces UTC/duplicated date code.

**Decisions**
- Email flow is now two clicks (save PDF, then "Open Gmail draft") — the only way both windows open reliably.
- Record fingerprints changed shape (letter fields excluded), so the first re-download of each already-saved doc after deploy adds one more row.

**Open / next**
- Invoice RATE column always says "/MT", even for rows in another unit (e.g. BAGS).

