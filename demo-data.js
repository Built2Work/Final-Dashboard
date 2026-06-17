/* ============================================================================
 * demo-data.js — anonymized static snapshot for demo.html
 * ----------------------------------------------------------------------------
 * This file defines `window.DEMO`, the ONLY data source for the login-free demo
 * dashboard. It contains NO real participant data: names, phones, emails and
 * addresses are all synthetic, and map coordinates are fictional.
 *
 * The object below is generated deterministically (seeded) so the demo looks the
 * same every load. To populate it with REAL-but-anonymized numbers from your
 * live dashboard, run `make-demo-data.js` in the browser console while logged in
 * (see README → "Demo") and replace this file with the file it downloads.
 *
 * Shape (mirrors the Supabase rows the dashboard expects):
 *   window.DEMO = { web:[…], exc:[…], win:[…], companies:[…], assignments:[…] }
 * ==========================================================================*/
(function () {
  // Deterministic PRNG so the synthetic demo is stable build-to-build.
  function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;var t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return ((t^t>>>14)>>>0)/4294967296;};}
  var rnd = mulberry32(20260617);
  function pick(arr){return arr[Math.floor(rnd()*arr.length)];}
  function chance(p){return rnd()<p;}
  function rint(lo,hi){return lo+Math.floor(rnd()*(hi-lo+1));}
  // Normalized phone key — mirrors normalizePhone() in shared.js.
  function normPhone(p){return String(p==null?'':p).split('.')[0].replace(/[^0-9]/g,'').replace(/^1/,'').slice(-9);}

  var EVENTS = [
    {name:'Atlanta Workforce Expo',        date:'2026-03-12', base:[33.749,-84.388],  states:['GA','AL','TN','SC']},
    {name:'Dallas Construction Career Fair',date:'2026-04-09', base:[32.7767,-96.797], states:['TX','OK','LA','AR']},
    {name:'Phoenix Skilled Trades Day',    date:'2026-05-21', base:[33.448,-112.074], states:['AZ','NV','NM','CA']}
  ];
  var FIRST = ['James','Maria','David','Aisha','Robert','Linda','Carlos','Nia','Kevin','Sofia','Marcus','Emily','Tyler','Grace','Andre','Olivia','Hector','Diane','Sam','Priya','Jordan','Lena','Mike','Tara','Devin','Rosa','Chris','Bella','Omar','Janet','Luis','Maya','Brian','Nora','Eli','Tess'];
  var LAST  = ['Carter','Nguyen','Johnson','Patel','Reyes','Brooks','Diaz','Walker','Foster','Bennett','Hughes','Russo','Coleman','Ortiz','Pierce','Hayes','Khan','Murray','Snyder','Flores','Dawson','Bauer','Grant','Mercer','Vance','Pena','Sutton','Wells','Frazier','Lambert','Cohen','Park','Beck','Mraz','Hale','Ngata'];
  var STREETS = ['Oak St','Maple Ave','Cedar Ln','Pine Rd','Elm St','Birch Way','Walnut Dr','Sunset Blvd','Highland Ave','Riverside Dr','Park Pl','Lincoln Ave'];
  var CITIES = {GA:'Atlanta',AL:'Birmingham',TN:'Chattanooga',SC:'Greenville',TX:'Dallas',OK:'Tulsa',LA:'Shreveport',AR:'Little Rock',AZ:'Phoenix',NV:'Las Vegas',NM:'Albuquerque',CA:'Los Angeles'};
  var GENDERS = ['Male','Female','Female','Male','Prefer not to say'];
  var JOBS = ['Currently employed in construction and/or a trade','Currently employed in another industry','Unemployed and looking for work','Student','Retired','Other'];
  var INDUSTRIES = ['Construction','Manufacturing','Logistics','Hospitality','Retail','Healthcare','Education','Transportation',''];
  var JI = ['Yes','Yes','Maybe','No','Yes','Maybe','No Answer'];
  // Cert column names exactly as the dashboard reads them (CERT_COLS in demo.html).
  var CERT_COLS = ['Trade Certifications or Licenses'].concat(
    Array.from({length:15},function(_,i){return 'Trade Certifications or Licenses_'+(i+1);})
  );
  var TRIVIA_COLS = ['Trivia Auto Mechanic Score','Trivia Civil Construction Score','Trivia Electrical Score','Trivia Plumbing Score','Trivia Welding Score','Trivia Construction Labor Score','Trivia HVAC Score','Trivia Warehouse Score','Trivia Heavy Equipment Technician Score'];

  var web = [], exc = [], win = [];
  var N = 90;
  for (var i = 0; i < N; i++) {
    var ev = EVENTS[i % EVENTS.length];
    var phone = '404555' + String(100 + i).padStart(4, '0'); // fictional 555 numbers
    var st = pick(ev.states);
    var jobIsTrade = chance(0.42);
    var row = {
      'Date': ev.date,
      'Event Name': ev.name,
      'Mobile Phone': phone,
      'DOB': (2026 - rint(18, 64)) + '-' + String(rint(1,12)).padStart(2,'0') + '-' + String(rint(1,28)).padStart(2,'0'),
      'First Name': pick(FIRST),
      'Last Name': pick(LAST),
      'Street Address': rint(100,9999) + ' ' + pick(STREETS),
      'City': CITIES[st] || '',
      'State': st,
      'Email Address': '',                                   // emails removed
      'Gender': pick(GENDERS),
      'Job Status': jobIsTrade ? JOBS[0] : pick(JOBS),
      'Student': chance(0.15) ? 'Yes' : 'No',
      'Interested in Construction Jobs': pick(JI),
      'What industry do you work in?': pick(INDUSTRIES),
      'What industry do you work in': '',
      // map coords spread around the event city (fictional jitter)
      'lat': (ev.base[0] + (rnd() - 0.5) * 0.6).toFixed(5),
      'lng': (ev.base[1] + (rnd() - 0.5) * 0.6).toFixed(5)
    };
    // Certifications — trades-employed folks tend to hold a few more.
    CERT_COLS.forEach(function (c, idx) {
      row[c] = chance(jobIsTrade ? 0.10 : 0.04) ? 'Yes' : '';
    });
    web.push(row);

    // ~55% also played the EXC truck-loading game.
    if (chance(0.55)) {
      var safety = rint(35, 99), prod = rint(35, 99);
      exc.push({
        'Date': ev.date, 'Event Name': ev.name, 'Login Code': phone,
        'Total Score': Math.round((safety + prod) / 2),
        'Safety Score': safety, 'Productivity Score': prod
      });
    }
    // ~45% also played trivia (a few categories each).
    if (chance(0.45)) {
      var t = { 'Date': ev.date, 'Event Name': ev.name, 'QR Code Scan': phone, 'Mobile Phone': phone };
      TRIVIA_COLS.forEach(function (c) { t[c] = chance(0.5) ? rint(2, 20) : ''; });
      win.push(t);
    }
  }

  // ── CRM: fictional companies + a read-only pipeline of anonymized assignments
  var companies = [
    { id: 'demo-co-1', name: 'Apex Builders',      email: 'demo1@example.com' },
    { id: 'demo-co-2', name: 'Summit Mechanical',  email: 'demo2@example.com' },
    { id: 'demo-co-3', name: 'Ironclad Logistics', email: 'demo3@example.com' }
  ];
  var STATUSES = ['Not Contacted', 'Contacted', 'Interviewing', 'Hired', 'Rejected'];
  var HOPEFUL = ['Electrician Apprentice', 'CDL Driver', 'Welder', 'HVAC Tech', 'Heavy Equipment Operator', 'Warehouse Lead', 'Plumber Apprentice'];
  var CURRENT = ['Retail Associate', 'Warehouse Worker', 'Student', 'Line Cook', 'Laborer', 'Unemployed'];
  var assignments = [];
  for (var k = 0; k < 14; k++) {
    var comp = companies[k % companies.length];
    var d = new Date(2026, 4, 20 + (k % 8), 9 + k, 15);
    assignments.push({
      id: 'demo-assign-' + (k + 1),
      phone: normPhone(web[k]['Mobile Phone']),
      company_id: comp.id,
      status: STATUSES[k % STATUSES.length],
      hopeful_job: pick(HOPEFUL),
      pay_scale: '$' + rint(18, 34) + '/hr',
      current_job: pick(CURRENT),
      work_history: '',
      notes: '',                                    // notes blanked for the demo
      assigned_by: 'demo@built2work.com',
      assigned_at: d.toISOString(),
      updated_at: d.toISOString(),
      file_url: null
    });
  }

  window.DEMO = { web: web, exc: exc, win: win, companies: companies, assignments: assignments };
})();
