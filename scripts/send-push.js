// Daily background push for Finance Tracker.
// Runs in GitHub Actions: reads the user's synced data from Supabase, works out
// which time-sensitive reminders are due today, and sends one Web Push.
const webpush = require('web-push');

const SUPABASE_URL = 'https://ipjwpkqcuztahumijici.supabase.co';
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlwandwa3FjdXp0YWh1bWlqaWNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMTg0NjAsImV4cCI6MjA5MjU5NDQ2MH0.aCrIwHvNLkCtA_RXPdzIybRp2EMCrBeIVS5ABCtjl48';
const USER_KEY = 'f7e2a914-3b8c-4d5e-9a1f-6c2d7b0e8f3a';
const VAPID_PUBLIC = 'BBPHf6asV97ce62K0Emyf33g9Mx7gWagQxjSEPp4ZUa6VYUn7tiOm0qSGxDJgbNUbVZwi8Yx8LCyGBj9lTbVGgc';
const VAPID_PRIVATE = process.env.VAPID_PRIVATE_KEY;
const SUBJECT = 'mailto:noah@flouty.uk';
const PAID_LEAVE = ['2026-05-24','2026-05-25','2026-05-31','2026-06-01','2026-06-07'];

if (!VAPID_PRIVATE) { console.error('Missing VAPID_PRIVATE_KEY secret'); process.exit(1); }
webpush.setVapidDetails(SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

const pad = n => String(n).padStart(2, '0');
// Treat "today" in Japan time (paydays/SUICA are Japan-based)
function jstParts() {
  const d = new Date(Date.now() + 9 * 3600 * 1000);
  return { y: d.getUTCFullYear(), mo: d.getUTCMonth() + 1, day: d.getUTCDate(), dow: d.getUTCDay() };
}
// Payday = 15th, pulled back to Friday if it lands on a weekend (matches the app)
function gPD(y, mo) {
  const dt = new Date(Date.UTC(y, mo - 1, 15));
  const dw = dt.getUTCDay();
  if (dw === 6) return 14;
  if (dw === 0) return 13;
  return 15;
}

(async () => {
  const url = `${SUPABASE_URL}/rest/v1/finance_data?select=data&user_key=eq.${USER_KEY}`;
  const res = await fetch(url, { headers: { apikey: ANON, Authorization: `Bearer ${ANON}` } });
  if (!res.ok) { console.error('Supabase read failed', res.status, await res.text()); process.exit(1); }
  const rows = await res.json();
  const data = rows[0] && rows[0].data;
  if (!data) { console.log('No data row.'); return; }
  const se = data.settings || {};
  const months = data.data || {};
  if (!se.notifs) { console.log('Notifications off — nothing to send.'); return; }
  const sub = se.pushSub;
  if (!sub || !sub.endpoint) { console.log('No push subscription stored yet (open the app once with notifications on).'); return; }

  const { y, mo, day } = jstParts();
  const mk = `${y}-${pad(mo)}`;
  const todayStr = `${y}-${pad(mo)}-${pad(day)}`;
  const tomorrow = new Date(Date.UTC(y, mo - 1, day + 1));
  const tomStr = `${tomorrow.getUTCFullYear()}-${pad(tomorrow.getUTCMonth() + 1)}-${pad(tomorrow.getUTCDate())}`;
  const pd = gPD(y, mo);
  const dleft = pd - day;
  const tmd = months[mk] || {};
  const pf = tmd.paidFixed || {};
  const mc = tmd.mumChecked || [];

  if (process.env.TEST === 'true') {
    await webpush.sendNotification(sub, JSON.stringify({ title: 'Finance Tracker ✓', body: 'Background push is working!', tag: 'ft-test' }));
    console.log('Sent test push.');
    return;
  }

  const list = [];
  if (dleft === 0) list.push('💰 Payday today — log your hours');
  else if (dleft === 1) list.push('💰 Payday tomorrow');
  if (dleft >= 1 && dleft <= 3 && !pf['suica']) list.push(`🚇 Top up your SUICA (payday in ${dleft}d)`);
  if (dleft === 2) { const sorted = Object.values(pf).some(Boolean); if (!sorted) list.push('📋 Sort your bills before payday'); }
  if (dleft <= 0 && dleft >= -1 && mc.length === 0 && (se.mumItems || []).length > 0) list.push('👩 Send Mum her money');
  if (PAID_LEAVE.includes(todayStr)) list.push('🏖️ Paid leave today');
  else if (PAID_LEAVE.includes(tomStr)) list.push('🏖️ Paid leave tomorrow');

  if (list.length === 0) { console.log(`Nothing due (mk=${mk}, payday=${pd}, dleft=${dleft}).`); return; }

  const payload = JSON.stringify({ title: 'Finance Tracker', body: list.join(' · '), tag: 'ft-daily' });
  try {
    await webpush.sendNotification(sub, payload);
    console.log('Sent:', list.join(' · '));
  } catch (e) {
    console.error('Push send failed:', e.statusCode, e.body || e.message);
    process.exit(1);
  }
})();
