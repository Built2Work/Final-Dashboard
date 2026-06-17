/* ============================================================================
 * make-demo-data.js — generate an anonymized demo-data.js from LIVE data
 * ----------------------------------------------------------------------------
 * Run this in your browser's DevTools console WHILE LOGGED IN to the real
 * dashboard (index.html), after the data has loaded. Open the Pipeline tab once
 * first so the CRM (companies + assignments) is populated.
 *
 * It reads the in-memory data, strips/【fakes】 all PII, and downloads a ready
 * `demo-data.js`. No raw PII ever leaves your browser — the anonymization runs
 * locally and only the scrubbed file is written. Drop the downloaded file into
 * the repo (replacing the placeholder) and push.
 *
 * Anonymization applied:
 *   • names        → deterministic fake names (stable per participant)
 *   • phones       → fake 555 numbers, kept CONSISTENT across all tables so the
 *                    cross-table joins + pipeline matching still work
 *   • emails       → blanked
 *   • street addr  → faked (city/state kept)
 *   • lat/lng      → jittered ~±0.02° so pins don't pinpoint homes
 *   • company names→ faked;  assignment notes/work_history → blanked
 *   • file_url     → dropped (points at real storage)
 * ==========================================================================*/
(function () {
  if (typeof rawWeb === 'undefined' || !rawWeb.length) {
    alert('No data in memory. Load the dashboard (and open the Pipeline tab once) before running this.');
    return;
  }
  function normPhone(p){return String(p==null?'':p).split('.')[0].replace(/[^0-9]/g,'').replace(/^1/,'').slice(-9);}

  var FIRST = ['James','Maria','David','Aisha','Robert','Linda','Carlos','Nia','Kevin','Sofia','Marcus','Emily','Tyler','Grace','Andre','Olivia','Hector','Diane','Sam','Priya','Jordan','Lena','Mike','Tara','Devin','Rosa','Chris','Bella','Omar','Janet','Luis','Maya','Brian','Nora','Eli','Tess'];
  var LAST  = ['Carter','Nguyen','Johnson','Patel','Reyes','Brooks','Diaz','Walker','Foster','Bennett','Hughes','Russo','Coleman','Ortiz','Pierce','Hayes','Khan','Murray','Snyder','Flores','Dawson','Bauer','Grant','Mercer','Vance','Pena','Sutton','Wells','Frazier','Lambert','Cohen','Park','Beck','Mraz','Hale','Ngata'];
  var STREETS = ['Oak St','Maple Ave','Cedar Ln','Pine Rd','Elm St','Birch Way','Walnut Dr','Sunset Blvd','Highland Ave','Riverside Dr','Park Pl','Lincoln Ave'];
  var CONAMES = ['Apex Builders','Summit Mechanical','Ironclad Logistics','Cornerstone Trades','Meridian Industrial','Vanguard Contracting','Keystone Fabrication','Pioneer Electric'];

  // Stable real-phone → fake-identity map (shared across all tables).
  var idMap = {};   // realNorm -> { fakePhone, fakeNorm, first, last }
  var seq = 0;
  function ident(realPhoneRaw) {
    var key = normPhone(realPhoneRaw);
    if (!key) key = '_blank_' + (seq);          // keep blanks distinct
    if (!idMap[key]) {
      var n = seq++;
      var fakePhone = '404555' + String(100 + n).padStart(4, '0');
      idMap[key] = {
        fakePhone: fakePhone,
        fakeNorm: normPhone(fakePhone),
        first: FIRST[n % FIRST.length],
        last:  LAST[(n * 7 + 3) % LAST.length]
      };
    }
    return idMap[key];
  }
  function jitter(v) {
    var f = parseFloat(v);
    if (isNaN(f)) return v;
    return (f + (Math.random() - 0.5) * 0.04).toFixed(5);
  }

  // ── web_registration ──
  var web = rawWeb.map(function (r) {
    var id = ident(r['Mobile Phone']);
    var out = Object.assign({}, r);
    out['Mobile Phone']   = id.fakePhone;
    out['First Name']     = id.first;
    out['Last Name']      = id.last;
    out['Email Address']  = '';
    out['Street Address'] = (Math.floor(Math.random() * 9900) + 100) + ' ' + STREETS[(seq + (r['State'] || '').length) % STREETS.length];
    if (out.lat != null && out.lat !== '') out.lat = jitter(out.lat);
    if (out.lng != null && out.lng !== '') out.lng = jitter(out.lng);
    return out;
  });

  // ── exc_truck_loading (phone = "Login Code") ──
  var exc = (typeof rawExc !== 'undefined' ? rawExc : []).map(function (r) {
    var out = Object.assign({}, r);
    out['Login Code'] = ident(r['Login Code']).fakePhone;
    return out;
  });

  // ── windows_trivia (phone = "QR Code Scan" / "Mobile Phone") ──
  var win = (typeof rawWin !== 'undefined' ? rawWin : []).map(function (r) {
    var out = Object.assign({}, r);
    var src = r['QR Code Scan'] || r['Mobile Phone'];
    var fp = ident(src).fakePhone;
    if ('QR Code Scan' in out) out['QR Code Scan'] = fp;
    if ('Mobile Phone' in out) out['Mobile Phone'] = fp;
    return out;
  });

  // ── companies ──
  var comps = (typeof companies !== 'undefined' ? companies : []).map(function (c, i) {
    return { id: c.id, name: CONAMES[i % CONAMES.length], email: 'demo' + (i + 1) + '@example.com' };
  });

  // ── candidate_assignments (phone already normalized in DB) ──
  var assigns = (typeof assignments !== 'undefined' ? assignments : []).map(function (a) {
    var out = Object.assign({}, a);
    out.phone        = ident(a.phone).fakeNorm;
    out.notes        = '';
    out.work_history = '';
    out.assigned_by  = 'demo@built2work.com';
    out.file_url     = null;
    return out;
  });

  var DEMO = { web: web, exc: exc, win: win, companies: comps, assignments: assigns };
  var header =
    '/* demo-data.js — anonymized snapshot generated by make-demo-data.js\n' +
    ' * Contains NO real PII: names/phones faked, emails/addresses scrubbed,\n' +
    ' * map coordinates jittered. Safe to commit and serve publicly. */\n';
  var content = header + 'window.DEMO = ' + JSON.stringify(DEMO) + ';\n';

  var blob = new Blob([content], { type: 'text/javascript' });
  var url = URL.createObjectURL(blob);
  var a = document.createElement('a');
  a.href = url; a.download = 'demo-data.js';
  document.body.appendChild(a); a.click(); a.remove();
  URL.revokeObjectURL(url);
  console.log('demo-data.js downloaded —', web.length, 'participants,', exc.length, 'exc,', win.length, 'trivia,', assigns.length, 'assignments.');
})();
