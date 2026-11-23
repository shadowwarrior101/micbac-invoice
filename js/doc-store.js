// Supabase-backed invoice records (replaces the Google Sheet / Apps Script log).
// Who sees what is decided by RLS on invoice_documents (see
// supabase/migrations/*_invoice_documents*.sql); this module never filters by
// user itself, so the UI can't show something the database wouldn't return.
(function (root) {
  const cfg = root.MICBAC_CONFIG;
  const sb = root.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey);

  let me = null; // { id, email, access: 'full' | 'restricted' }

  function fail(prefix, error) {
    console.error(prefix, error);
    throw new Error(prefix + ": " + (error && error.message ? error.message : error));
  }

  // DB row -> the record shape the Records modal / exports already use.
  function toRecord(r) {
    return {
      id: r.id,
      createdAt: r.created_at,
      docType: r.doc_type,
      invNo: r.doc_no,
      invDate: r.doc_date || "",
      buyer: r.party_name || "",
      amount: r.amount == null ? 0 : Number(r.amount),
      currency: r.currency || "",
      pol: r.pol || "",
      pod: r.pod || "",
      items: r.items || 0,
      draftJson: r.data ? JSON.stringify(r.data) : "",
      createdBy: r.source === "sheet_import" ? "Imported (Sheet)" : r.created_by_email,
      mine: !!me && r.created_by === me.id,
    };
  }

  // Resolves with { id, email, access } once signed in as an allowed user, or
  // null if there's no session (caller shows the login screen).
  async function session() {
    const { data } = await sb.auth.getSession();
    const user = data.session && data.session.user;
    if (!user) return null;
    const { data: access, error } = await sb.rpc("invoice_access");
    if (error) fail("Could not check your access", error);
    if (!access) {
      await sb.auth.signOut();
      throw new Error(user.email + " is not allowed to use the invoice site");
    }
    me = { id: user.id, email: user.email, access };
    return me;
  }

  async function sendLoginLink(email) {
    const { error } = await sb.auth.signInWithOtp({
      email: String(email).trim(),
      // Only existing accounts; this site must never create users in the
      // shared auth pool (it also holds the orders app's accounts).
      options: { shouldCreateUser: false, emailRedirectTo: location.origin + location.pathname },
    });
    if (error) fail("Could not send login link", error);
  }

  async function signOut() {
    await sb.auth.signOut();
    location.reload();
  }

  // All records this user may see, newest first.
  async function list() {
    // PostgREST caps responses at 1000 rows; page through to get them all.
    const rows = [];
    for (let from = 0; ; from += 1000) {
      const { data, error } = await sb.from("invoice_documents").select("*")
        .order("created_at", { ascending: false }).range(from, from + 999);
      if (error) fail("Could not load records", error);
      rows.push(...data);
      if (data.length < 1000) break;
    }
    return rows.map(toRecord);
  }

  // rec uses the record shape (see toRecord); draft is the form-state object.
  async function insert(rec, draft) {
    const { error } = await sb.from("invoice_documents").insert({
      doc_type: rec.docType,
      doc_no: rec.invNo,
      doc_date: rec.invDate || null,
      party_name: rec.buyer || null,
      amount: Number.isFinite(rec.amount) ? rec.amount : null,
      currency: rec.currency || null,
      pol: rec.pol || null,
      pod: rec.pod || null,
      items: rec.items || 0,
      data: draft,
    });
    if (error) fail("Could not save record", error);
  }

  // RLS lets only the creator delete; returns how many rows were removed.
  async function remove(id) {
    const { error, count } = await sb.from("invoice_documents").delete({ count: "exact" }).eq("id", id);
    if (error) fail("Could not delete record", error);
    return count || 0;
  }

  async function removeAllMine() {
    const { error, count } = await sb.from("invoice_documents").delete({ count: "exact" }).eq("created_by", me.id);
    if (error) fail("Could not delete records", error);
    return count || 0;
  }

  // Highest sequence used for this prefix + FY across ALL records (including
  // ones this user can't see), so restricted users never reuse a number.
  async function maxSeq(prefix, fy) {
    const { data, error } = await sb.rpc("invoice_max_seq", { p_prefix: prefix, p_fy: fy });
    if (error) fail("Could not get next number", error);
    return data || 0;
  }

  root.DocStore = { session, sendLoginLink, signOut, list, insert, remove, removeAllMine, maxSeq, me: () => me };
})(this);
