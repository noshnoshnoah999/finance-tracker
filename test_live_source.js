// Extracts freezeDOW / rmShift / addShift / gShifts VERBATIM from app.html and executes
// them against a mock store, so the test exercises the shipped source rather than a
// transcription of it. Re-runs the same invariant: nothing on or before today changes.
const fs = require("fs");
const SRC = require("path").join(__dirname, "app.html");
const html = fs.readFileSync(SRC, "utf8");

const grab = name => {
  const i = html.indexOf(`      const ${name}=`);
  if (i < 0) throw new Error(`could not find ${name} in app.html`);
  return html.slice(i, html.indexOf("\n", i)).trim();
};
const grabTop = name => {
  const i = html.indexOf(`    const ${name}=`);
  if (i < 0) throw new Error(`could not find ${name} in app.html`);
  return html.slice(i, html.indexOf("\n", i)).trim();
};

const MONTHS = ["2026-01","2026-02","2026-03","2026-04","2026-05","2026-06","2026-07","2026-08","2026-09","2026-10","2026-11","2026-12"].map(k=>({key:k}));
const PAID_LEAVE = ["2026-05-24","2026-05-25","2026-05-31","2026-06-01","2026-06-07"];
const PL_HOURS_PER_DAY = 7;
const eM = () => ({customDays:{}, shiftOverrides:{}});

// Mutable mock state + React-style setters.
let se = { shifts: { 1:{start:"09:00",end:"16:00",breakMin:60,label:"Mon"},
                     2:{start:"09:00",end:"12:00",breakMin:0,label:"Tue"},
                     0:{start:"10:30",end:"17:00",breakMin:60,label:"Sun"} },
           workDays: [0,1,2] };
let da = {}; MONTHS.forEach(m => da[m.key] = eM());
da["2026-07"].customDays["2026-07-14"] = "none";
da["2026-06"].customDays["2026-06-15"] = "none";
da["2026-03"].shiftOverrides["2"] = {start:"09:00",end:"14:00",breakMin:0};
const setDa = fn => { da = typeof fn === "function" ? fn(da) : fn; };
const setSe = fn => { se = typeof fn === "function" ? fn(se) : fn; };
let confirmed = true;
const window = { confirm: () => confirmed };

// Real source, evaluated in this scope.
const src = [grabTop("DOW_LABELS"), grabTop("DOW_FULL"), grabTop("DOW_ORDER"), grabTop("dstr"),
             grab("gShifts"), grab("freezeDOW"), grab("rmShift"), grab("addShift")].join("\n");
console.log("Evaluating verbatim source from app.html:");
[ "DOW_LABELS","DOW_FULL","DOW_ORDER","dstr","gShifts","freezeDOW","rmShift","addShift" ]
  .forEach(n => console.log("  loaded " + n));
const ctx = eval(`(function(){ ${src}\n return {gShifts, freezeDOW, rmShift, addShift, DOW_ORDER, DOW_LABELS}; })`).call(
  null);

// Local copies of the pure read helpers (unchanged by this feature).
const dstr = d => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
const getDayState = (ds, dt, cd, wd) => { const ov=(cd||{})[ds]; if(ov) return ov;
  if (PAID_LEAVE.includes(ds)) return "pl"; if (wd.map(Number).includes(dt.getDay())) return "work"; return "none"; };
const sH = sh => { if(!sh) return 0; const [a,b]=sh.start.split(":").map(Number),[cv,dv]=sh.end.split(":").map(Number); return (cv+dv/60)-(a+b/60)-(sh.breakMin/60); };
const walk = () => { const m={};
  MONTHS.forEach(mo => { const mk=mo.key; const [y,mm]=mk.split("-").map(Number);
    const sh = ctx.gShifts(mk); const cd = (da[mk]||{}).customDays||{};
    const d=new Date(y,mm-1,1), en=new Date(y,mm,0);
    while (d<=en) { const ds=dstr(d); const st=getDayState(ds,d,cd,se.workDays);
      let h=0,warn=false;
      if (st==="work") { const s=sh[d.getDay()]; if(s) h=sH(s); else warn=true; }
      else if (st==="pl") h=PL_HOURS_PER_DAY;
      m[ds]={state:st,hours:h,warn}; d.setDate(d.getDate()+1); } });
  return m; };

const TODAY = new Date(); TODAY.setHours(0,0,0,0);
console.log(`\nSystem date for cutoff: ${dstr(TODAY)}`);

const before = walk();
ctx.rmShift(2);                       // ← the real removal path, confirm() stubbed true
const after = walk();

let fails=0, checks=0;
const eq=(l,a,b)=>{checks++; if(JSON.stringify(a)!==JSON.stringify(b)){fails++;console.log(`  FAIL ${l}\n       expected=${JSON.stringify(a)}\n       actual  =${JSON.stringify(b)}`);}};

const diffs=[];
Object.keys(before).forEach(ds=>{ const [y,m,d]=ds.split("-").map(Number);
  if (new Date(y,m-1,d)<=TODAY && JSON.stringify(before[ds])!==JSON.stringify(after[ds]))
    diffs.push(`${ds} ${JSON.stringify(before[ds])} -> ${JSON.stringify(after[ds])}`); });
eq("no date on or before today changed", [], diffs);

eq("Tuesday removed from se.shifts", undefined, se.shifts[2]);
eq("Tuesday removed from se.workDays", [0,1], se.workDays.map(Number).sort());
eq("Mon + Sun shifts survive", ["0","1"], Object.keys(se.shifts).sort());
eq("hand-marked Tue 2026-07-14 still 'none'", "none", da["2026-07"].customDays["2026-07-14"]);
eq("pre-existing March override not clobbered", {start:"09:00",end:"14:00",breakMin:0}, da["2026-03"].shiftOverrides["2"]);
eq("July gained a Tue shiftOverride", {start:"09:00",end:"12:00",breakMin:0,label:"Tue"}, da["2026-07"].shiftOverrides["2"]);
const plTue = PAID_LEAVE.filter(ds=>{const[y,m,d]=ds.split("-").map(Number);return new Date(y,m-1,d).getDay()===2;});
eq(`PAID_LEAVE Tuesdays (${plTue.join(",")||"none"}) untouched`, [], plTue.filter(ds=>(da[ds.slice(0,7)].customDays||{})[ds]==="work"));

// Future months must raise no "no shift time set" warnings.
let futureWarn=0;
Object.keys(after).forEach(ds=>{const[y,m,d]=ds.split("-").map(Number); if(new Date(y,m-1,d)>TODAY && after[ds].warn) futureWarn++;});
eq("no 'no shift set' warnings in the future", 0, futureWarn);

// Re-adding Wednesday should work and not disturb history.
const histBeforeAdd = walk();
ctx.addShift(3);
eq("Wednesday added to shifts", true, !!se.shifts[3]);
eq("Wednesday added to workDays", true, se.workDays.map(Number).includes(3));
let pastChangedByAdd=0;
const histAfterAdd = walk();
Object.keys(histBeforeAdd).forEach(ds=>{const[y,m,d]=ds.split("-").map(Number);
  if(new Date(y,m-1,d)<=TODAY && JSON.stringify(histBeforeAdd[ds])!==JSON.stringify(histAfterAdd[ds])) pastChangedByAdd++;});
eq("adding a day does not rewrite the past", 0, pastChangedByAdd);

console.log(`\n${fails===0?"PASS":"FAIL"} — ${checks-fails}/${checks} checks passed against live app.html source`);
process.exit(fails===0?0:1);
