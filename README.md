# Final-Dashboard

Built to Work event analytics dashboards (static, client-side, Supabase-backed).

| Page | Purpose |
|------|---------|
| `index.html` | Event analytics — KPIs, filters, participant table, assignment pipeline |
| `operations.html` | Real-time operations metrics and per-day drill-down |
| `customer.html` | Company candidate portal (scoped to the logged-in company) |
| `shared.js` | Shared config + helpers (Supabase client, phone/escape/upload utils) |

## Security

Access control depends on Supabase Row-Level Security. **Before relying on this
in production, read [`SECURITY.md`](./SECURITY.md) and apply
[`supabase-rls.sql`](./supabase-rls.sql).** Without RLS the public anon key
exposes all candidate PII.
