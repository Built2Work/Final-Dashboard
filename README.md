# Final-Dashboard

Built to Work event analytics dashboards (static, client-side, Supabase-backed).

| Page | Purpose |
|------|---------|
| `index.html` | Event analytics — KPIs, filters, participant table, assignment pipeline |
| `operations.html` | Real-time operations metrics and per-day drill-down |
| `customer.html` | Company candidate portal (scoped to the logged-in company) |
| `demo.html` | Public, login-free demo of the analytics dashboard on anonymized data |
| `shared.js` | Shared config + helpers (Supabase client, phone/escape/upload utils) |
| `demo-data.js` | Anonymized static snapshot that powers `demo.html` (no real PII) |

## Demo

`demo.html` is a shareable copy of the analytics dashboard with **no login** and
**no Supabase access**. It runs entirely on the static snapshot in `demo-data.js`,
in which participant names are faked, phones/emails are removed, street addresses
are scrubbed, and map coordinates are jittered. All database-write controls
(assign / edit notes / file upload / geocode) are removed, so it is read-only.

The committed `demo-data.js` is small synthetic placeholder data. To refresh it
with real-but-anonymized numbers from the live dashboard:

1. Open `index.html`, log in, and let the data load. Open the **Pipeline** tab
   once so the CRM data is loaded too.
2. Open DevTools → **Console**, paste the contents of `make-demo-data.js`, and
   run it. Anonymization happens in your browser; it downloads a scrubbed
   `demo-data.js` (no raw PII ever leaves the page).
3. Replace `demo-data.js` in the repo with the downloaded file and push.

> ⚠️ Only ever commit a `demo-data.js` produced by `make-demo-data.js` (or the
> synthetic placeholder). Never paste live query results in directly — they
> contain real PII.

## Security

Access control depends on Supabase Row-Level Security. **Before relying on this
in production, read [`SECURITY.md`](./SECURITY.md) and apply
[`supabase-rls.sql`](./supabase-rls.sql).** Without RLS the public anon key
exposes all candidate PII.

Then apply [`supabase-status-events.sql`](./supabase-status-events.sql) — it adds
the status-change log behind the Pipeline tab's Hired/Rejected notifications,
"status changed X ago" timestamps, and per-candidate rejection history.
