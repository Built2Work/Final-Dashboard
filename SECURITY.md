# Security notes & required manual steps

This dashboard is a static, client-side app (three HTML pages) backed by Supabase
(auth + Postgres + Storage). Because it ships no server, some hardening lives in
configuration you must apply outside the code. This file lists what the code
changes assume and what you still need to do.

## 1. Apply Row-Level Security (REQUIRED — do this first)

The Supabase **anon** key is public by design (it is in `shared.js` and visible
to anyone). The ONLY thing stopping a visitor from reading all candidate PII is
Row-Level Security. The per-company filtering in JavaScript is convenience, not
security.

1. Open Supabase → **SQL Editor**.
2. Paste the contents of [`supabase-rls.sql`](./supabase-rls.sql) and **Run**.
   It is idempotent — safe to re-run.
3. In `supabase-rls.sql`, **STEP 1**, add your staff emails to the `admins`
   table (the people who use `index.html` / `operations.html` and need to see
   all events). Company-portal users (in the `companies` table) are scoped
   automatically to their own rows.
4. Verify with the query at the bottom of the SQL file — every listed table must
   show `rowsecurity = true`. Then log in as a company user and confirm you can
   only see your own candidates.

> The SQL adds a `normalize_phone()` function that mirrors the JS
> `normalizePhone()` so event-table rows are matched to a company's assigned
> phones server-side. See the performance note in the file for indexing on large
> tables.

## 2. Restrict the Mapbox token (recommended)

The Mapbox token is a public `pk.` token — fine to expose, but it should be
URL-restricted so a scraper can't run up your bill:

- Mapbox account → **Tokens** → edit the token → add a **URL restriction** for
  the domain that serves this dashboard (your GitHub Pages URL).

## 3. Add Subresource Integrity to CDN scripts (follow-up)

We did **not** add `integrity=` hashes because they must be computed from the
exact files and a wrong hash blocks the script and breaks the page. When you can
reach the network, generate them and add `integrity="sha384-…" crossorigin="anonymous"`
to each `<script src="https://…">` tag:

```bash
for u in \
  https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js \
  https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js ; do
  echo "$u"; curl -sL "$u" | openssl dgst -sha384 -binary | openssl base64 -A; echo; done
```

cdnjs also shows the SRI hash next to each file on cdnjs.com. Pin
`@supabase/supabase-js@2` to an exact version (e.g. `@2.x.y`) before hashing it,
since SRI can't be used on a floating version.

## 4. Content-Security-Policy

A CSP is set via a `<meta http-equiv="Content-Security-Policy">` tag in each HTML
file (GitHub Pages can't send real HTTP headers). It restricts which origins can
load scripts/styles/connect, which blocks injected external scripts.

It intentionally allows `'unsafe-inline'` for scripts because the app uses inline
`<script>` blocks and inline `onclick` handlers — dropping that would require
rewriting every handler. The primary XSS defense is output escaping (below), with
CSP as defense-in-depth.

**After deploying, verify** the app still works end-to-end — especially the
Mapbox maps/geocoding and Supabase data loading. If the browser console shows a
CSP violation for a needed origin, add that origin to the matching directive in
the `<meta>` tag (it is duplicated in all three HTML files). If maps fail to
render you may need to add `'unsafe-eval'` to `script-src` (some Mapbox GL
builds require it).

## What changed in the code

- **`shared.js`** (new): single home for the Supabase config + `sb` client,
  `MAPBOX_TOKEN`, `normalizePhone()`, the `esc()` / `jsAttr()` HTML-escaping
  helpers, and `validateUploadFile()`. Removes the config/helper duplication that
  previously existed in all three HTML files. (CSS was **not** merged: `index.html`
  uses a different visual theme than the other two pages.)
- **XSS escaping**: every DB/API/user value rendered via `innerHTML` is now run
  through `esc()`, and values placed inside inline `onclick="fn('…')"` handlers
  through `jsAttr()` (JS-string + attribute safe). This closes the stored-XSS
  path through candidate notes, names, addresses and event/state names.
- **File uploads** now go through `validateUploadFile()` (size + extension +
  MIME allow-list) instead of trusting the filename extension.
- **localStorage cache removed**: candidate PII is no longer written to disk; the
  dashboard fetches fresh per session and keeps data only in memory.
- **`normalizePhone()` unified** to the version that handles float-formatted CSV
  phone values (`"123…​.0"`). `index.html` previously used a simpler variant, so
  phone matching there is now consistent with the other pages — verify dedup
  counts look right after deploying.
- **`.gitignore`** added.
