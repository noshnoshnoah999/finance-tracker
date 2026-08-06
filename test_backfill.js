// Verifies the history-freeze backfill in app.html / index.html.
//
// INVARIANT UNDER TEST: after removing a weekday from the Work Schedule, every date on
// or before today must resolve to the same day-state and the same credited hours as it
// did before the removal. Dates after today are expected to change (that is the point).
const MONTHS = ["2026-01","2026-02","2026-03","2026-04","2026-05","2026-06","2026-07","2026-08","2026-09","2026-10","2026-11","2026-12"];
const PAID_LEAVE = ["2026-05-24","2026-05-25","2026-05-31","2026-06-01","2026-06-07"];
const PL_HOURS_PER_DAY = 7;
const dstr = d => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
const getDayState = (ds, dt, customDays, wd) => {
  const ov = (customDays||{})[ds]; if (ov) return ov;
  const isSched = wd.includes(dt.getDay());
  if (PAID_LEAVE.includes(ds)) return "pl";
  if (isSched) return "work";
  return "none";
};
const sH = sh => { if(!sh) return 0; const [a,b]=sh.start.split(":").map(Number),[cv,dv]=sh.end.split(":").map(Number); return (cv+dv/60)-(a+b/60)-(sh.breakMin/60); };

// gShifts, transcribed from app.html (union of base schedule + month overrides).
const gShifts = (mk, base, data) => {
  const ov = (data[mk]||{}).shiftOverrides || {}; const r = {};
  new Set([...Object.keys(base), ...Object.keys(ov)]).forEach(d => {
    const b = base[d], o = ov[d];
    if (b && o) r[d] = {...b, ...o}; else if (b) r[d] = b; else if (o && o.start && o.end) r[d] = o; });
  return r;
};
// freezeDOW, transcribed from app.html.
const freezeDOW = (dow, data, base, today) => {
  const out = JSON.parse(JSON.stringify(data)); const keep = base[dow];
  MONTHS.forEach(mk => {
    const [y,m] = mk.split("-").map(Number);
    const cur = {...((out[mk]||{}).customDays||{})};
    const ovr = {...((out[mk]||{}).shiftOverrides||{})};
    let changed=false, hasPast=false;
    const d = new Date(y,m-1,1), en = new Date(y,m,0);
    while (d<=en) {
      if (d.getDay()===dow && d<=today) { hasPast=true; const ds=dstr(d);
        if (!cur[ds] && !PAID_LEAVE.includes(ds)) { cur[ds]="work"; changed=true; } }
      d.setDate(d.getDate()+1); }
    if (hasPast && keep && !ovr[dow]) { ovr[dow] = {...keep}; changed=true; }
    if (changed) out[mk] = {...(out[mk]||{}), customDays: cur, shiftOverrides: ovr};
  });
  return out;
};
// Per-date walk: returns {state, hours} for every date of the year.
const walk = (base, data, wd) => { const m = {};
  MONTHS.forEach(mk => { const [y,mo]=mk.split("-").map(Number);
    const sh = gShifts(mk, base, data); const cd = (data[mk]||{}).customDays||{};
    const d = new Date(y,mo-1,1), en = new Date(y,mo,0);
    while (d<=en) { const ds=dstr(d); const st=getDayState(ds,d,cd,wd);
      let h=0, warn=false;
      if (st==="work") { const s=sh[d.getDay()]; if (s) h=sH(s); else warn=true; }
      else if (st==="pl") h=PL_HOURS_PER_DAY;
      m[ds] = {state:st, hours:h, warn}; d.setDate(d.getDate()+1); } });
  return m; };

// ── Scenario: Noah's real settings, removing Tuesday ──
const base = { 1:{start:"09:00",end:"16:00",breakMin:60,label:"Mon"},
               2:{start:"09:00",end:"12:00",breakMin:0,label:"Tue"},
               0:{start:"10:30",end:"17:00",breakMin:60,label:"Sun"} };
const baseAfter = {1:base[1], 0:base[0]};
const TODAY = new Date(2026,7,6); TODAY.setHours(0,0,0,0);   // 6 Aug 2026
const wdBefore = [0,1,2], wdAfter = [0,1];

const data = {}; MONTHS.forEach(mk => data[mk] = {customDays:{}, shiftOverrides:{}});
data["2026-07"].customDays["2026-07-14"] = "none";  // a Tuesday marked off by hand
data["2026-06"].customDays["2026-06-15"] = "none";  // a Monday marked off by hand
data["2026-03"].shiftOverrides["2"] = {start:"09:00",end:"14:00",breakMin:0}; // longer Tue in March

const before = walk(base, data, wdBefore);
const frozen = freezeDOW(2, data, base, TODAY);
const after  = walk(baseAfter, frozen, wdAfter);

let fails=0, checks=0;
const eq = (label,a,b) => { checks++; if (JSON.stringify(a)!==JSON.stringify(b)) { fails++; console.log(`  FAIL ${label}\n       before=${JSON.stringify(a)}\n       after =${JSON.stringify(b)}`); } };

// 1. Every date <= today identical.
let diffs = [];
Object.keys(before).forEach(ds => {
  const [y,m,d] = ds.split("-").map(Number);
  if (new Date(y,m-1,d) <= TODAY && JSON.stringify(before[ds]) !== JSON.stringify(after[ds]))
    diffs.push(`${ds} ${JSON.stringify(before[ds])} -> ${JSON.stringify(after[ds])}`);
});
eq("no date on or before 2026-08-06 changed", [], diffs);

// 2. Monthly rollups for past months.
console.log("Monthly rollups (dates <= today only):");
MONTHS.filter(mk => mk <= "2026-08").forEach(mk => {
  const sum = src => { let days=0,hrs=0,warns=0;
    Object.keys(src).filter(ds => { const [y,m,d]=ds.split("-").map(Number); return ds.slice(0,7)===mk && new Date(y,m-1,d)<=TODAY; })
      .forEach(ds => { if (src[ds].state==="work") days++; hrs+=src[ds].hours; if (src[ds].warn) warns++; });
    return {days, hrs:Math.round(hrs*100)/100, warns}; };
  const b = sum(before), a = sum(after);
  eq(`${mk} rollup`, b, a);
  console.log(`  ${mk}  workdays ${b.days}->${a.days}   hours ${b.hrs}->${a.hrs}   noShiftWarnings ${b.warns}->${a.warns}`);
});

// 3. Future months should drop Tuesdays and raise NO warnings.
console.log("\nFuture months (expected to change):");
["2026-09","2026-10","2026-11","2026-12"].forEach(mk => {
  const sum = src => { let days=0,hrs=0,warns=0;
    Object.keys(src).filter(ds => ds.slice(0,7)===mk).forEach(ds => { if (src[ds].state==="work") days++; hrs+=src[ds].hours; if (src[ds].warn) warns++; });
    return {days, hrs:Math.round(hrs*100)/100, warns}; };
  const b = sum(before), a = sum(after);
  eq(`${mk} raises no 'no shift set' warning`, 0, a.warns);
  console.log(`  ${mk}  workdays ${b.days}->${a.days}   hours ${b.hrs}->${a.hrs}   noShiftWarnings ${a.warns}`);
});

console.log("\nSpecific guards:");
eq("hand-marked Tue 2026-07-14 stays 'none'", "none", frozen["2026-07"].customDays["2026-07-14"]);
eq("hand-marked Mon 2026-06-15 untouched", "none", frozen["2026-06"].customDays["2026-06-15"]);
eq("Tue 2026-08-04 (past) frozen as work", "work", frozen["2026-08"].customDays["2026-08-04"]);
eq("Tue 2026-08-11 (future) not written", undefined, frozen["2026-08"].customDays["2026-08-11"]);
eq("Mon 2026-07-06 not written (wrong weekday)", undefined, frozen["2026-07"].customDays["2026-07-06"]);
eq("July gets a Tue shiftOverride", {start:"09:00",end:"12:00",breakMin:0,label:"Tue"}, frozen["2026-07"].shiftOverrides["2"]);
eq("pre-existing March override NOT clobbered", {start:"09:00",end:"14:00",breakMin:0}, frozen["2026-03"].shiftOverrides["2"]);
eq("no override written for future-only month 2026-09", undefined, (frozen["2026-09"].shiftOverrides||{})["2"]);
const plTue = PAID_LEAVE.filter(ds => { const [y,m,d]=ds.split("-").map(Number); return new Date(y,m-1,d).getDay()===2; });
eq(`PAID_LEAVE Tuesdays (${plTue.join(",")||"none"}) not overwritten`, [], plTue.filter(ds => (frozen[ds.slice(0,7)].customDays||{})[ds]==="work"));
eq("freeze is idempotent", frozen, freezeDOW(2, frozen, baseAfter, TODAY));

console.log(`\n${fails===0 ? "PASS" : "FAIL"} — ${checks-fails}/${checks} checks passed`);
process.exit(fails===0 ? 0 : 1);
