// Extracts getDayState / sH / dfBrk / gShifts / gWorkDaysCD / gEstHours / gEstPay VERBATIM
// from app.html and executes them against a mock store, so this tests shipped source rather
// than a transcription of it. Exercises the exact bug Noah reported: a one-off shift marked
// on a non-schedule weekday in September was crediting 0 hours (only the ¥1,100 transport
// reimbursement showed up in the October estimate) because gEstHours only ever looked up
// shifts[d.getDay()], with nowhere to store an exact-date shift.
const fs = require("fs");
const path = require("path");
const SRC = path.join(__dirname, "app.html");
const html = fs.readFileSync(SRC, "utf8");

const grabTop = name => {
  const i = html.indexOf(`    const ${name}=`);
  if (i < 0) throw new Error(`could not find top-level ${name} in app.html`);
  return html.slice(i, html.indexOf("\n", i)).trim();
};
const grab = name => {
  const i = html.indexOf(`      const ${name}=`);
  if (i < 0) throw new Error(`could not find ${name} in app.html`);
  return html.slice(i, html.indexOf("\n", i)).trim();
};

const MONTHS = ["2026-01","2026-02","2026-03","2026-04","2026-05","2026-06","2026-07","2026-08","2026-09","2026-10","2026-11","2026-12"].map(k=>({key:k}));
const PAID_LEAVE = ["2026-05-24","2026-05-25","2026-05-31","2026-06-01","2026-06-07"];
const PL_HOURS_PER_DAY = 7;
const eM = () => ({customDays:{}, shiftOverrides:{}, oneOffShifts:{}});

// Mock settings: regular Mon + Sun schedule, no Tuesday — matches Noah's real schedule
// (Mon 09:00-18:00/30min break, Sun 10:30-17:00/30min break).
let se = {
  shifts: { 1:{start:"09:00",end:"18:00",breakMin:30}, 0:{start:"10:30",end:"17:00",breakMin:30} },
  workDays: [0,1],
  hourlyWage: 1100,
  trBefore: 1100, trAfter: 1100,
  defaultBreak: 60,
};
let da = {}; MONTHS.forEach(m => da[m.key] = eM());
const setDa = fn => { da = typeof fn === "function" ? fn(da) : fn; };
const setSe = fn => { se = typeof fn === "function" ? fn(se) : fn; };

// Real source, evaluated in this scope so gWorkDaysCD/trf's closures over `se`/`da` resolve.
const sHSrc = grabTop("sH");
const dfBrkSrc = grab("dfBrk");
const gShiftsSrc = grab("gShifts");
const gWorkDaysCDSrc = grab("gWorkDaysCD");
const gEstHoursSrc = grab("gEstHours");
const gEstPaySrc = grab("gEstPay");
const trfSrc = grab("trf");
const getDayStateSrc = grabTop("getDayState");

console.log("Evaluating verbatim source from app.html:");
["getDayState","sH","dfBrk","gShifts","gWorkDaysCD","trf","gEstHours","gEstPay"].forEach(n=>console.log("  loaded "+n));

const full = [getDayStateSrc, sHSrc, dfBrkSrc, gShiftsSrc, gWorkDaysCDSrc, trfSrc, gEstHoursSrc, gEstPaySrc].join("\n");

const gPrevMK = mk => { const i = MONTHS.findIndex(m=>m.key===mk); return i>0 ? MONTHS[i-1].key : null; };

const ctx = eval(`(function(){ ${full}\n return {getDayState, sH, dfBrk, gShifts, gWorkDaysCD, trf, gEstHours, gEstPay}; })`).call(null);

let fails=0, checks=0;
const eq=(l,a,b)=>{checks++; if(JSON.stringify(a)!==JSON.stringify(b)){fails++;console.log(`  FAIL ${l}\n       expected=${JSON.stringify(a)}\n       actual  =${JSON.stringify(b)}`);} else {console.log(`  ok   ${l}`);}};

console.log("\n--- Scenario: one-off Tuesday shift in September, isolated day-level check ---");
// Isolate a single day using gEstHours directly on a fixture month with an EMPTY weekly
// schedule, so the only "work" day in the whole month is the one-off Tuesday — no Mon/Sun
// noise to separate out. Mirrors gEstPay's own call shape (cd, shifts, wd, oneOff).
const isoWD = []; // no regular schedule days at all
const isoShifts = {}; // gShifts() equivalent — no weekday shifts defined
const isoCDBefore = { "2026-09-08": "work" }; // Tuesday marked work via the calendar tap
const isoOOSNone = {};
const before = ctx.gEstHours("2026-09", isoCDBefore, isoShifts, isoWD, isoOOSNone);
console.log(`  Without a one-off entry: hours=${before.hours}, noShiftDays=${before.noShiftDays}`);
eq("bug reproduced: 0 credited hours with no one-off entry", 0, before.hours);
eq("bug reproduced: noShiftDays counts the orphan work day", 1, before.noShiftDays);

const isoOOSAfter = { "2026-09-08": {start:"09:00", end:"17:00", breakMin:60} };
const after = ctx.gEstHours("2026-09", isoCDBefore, isoShifts, isoWD, isoOOSAfter);
console.log(`  With a one-off entry: hours=${after.hours}, noShiftDays=${after.noShiftDays}`);
eq("one-off shift credits its own hours (7h)", 7, after.hours);
eq("no more 'no shift time set' warning for that day", 0, after.noShiftDays);

console.log("\n--- Full-pipeline check via gEstPay: September one-off feeds October's estimate ---");
da["2026-09"].customDays = { "2026-09-08": "work" };
da["2026-09"].oneOffShifts = {};
const estBefore = ctx.gEstPay("2026-10");
da["2026-09"].oneOffShifts = { "2026-09-08": {start:"09:00", end:"17:00", breakMin:60} };
const estAfter = ctx.gEstPay("2026-10");
console.log(`  before: hours=${estBefore.hours}, wage=${estBefore.wage}, transport=${estBefore.transport}, noShiftDays=${estBefore.noShiftDays}, total=${estBefore.total}`);
console.log(`  after:  hours=${estAfter.hours}, wage=${estAfter.wage}, transport=${estAfter.transport}, noShiftDays=${estAfter.noShiftDays}, total=${estAfter.total}`);
eq("hours increase by exactly 7h once the one-off is saved", 7, estAfter.hours - estBefore.hours);
eq("wage increases by 7h x hourlyWage", Math.round(7*se.hourlyWage), estAfter.wage - estBefore.wage);
eq("noShiftDays drops from 1 to 0", [1,0], [estBefore.noShiftDays, estAfter.noShiftDays]);
eq("transport (day count) is unaffected by the one-off save", estBefore.transport, estAfter.transport);
eq("total increases by exactly the new wage", estAfter.wage - estBefore.wage, estAfter.total - estBefore.total);

console.log("\n--- Regression: regular Mon/Sun schedule days still resolve via weekday shift, unaffected ---");
da["2026-09"].customDays["2026-09-08"] = "work"; // keep the Tuesday marked, plus normal Mon/Sun via se.workDays
const est2 = ctx.gEstPay("2026-10");
eq("regular schedule days still contribute on top of the one-off (58h Mon/Sun + 7h one-off)", 65, est2.hours);

console.log("\n--- Regression: a one-off entry for a date NOT marked customDays 'work' must be ignored ---");
const isoCDEmpty = {}; // Tuesday no longer marked work
const est3 = ctx.gEstHours("2026-09", isoCDEmpty, isoShifts, isoWD, isoOOSAfter);
eq("stray oneOffShifts entry with no customDays 'work' contributes nothing", 0, est3.hours);

console.log(`\n${fails===0?"PASS":"FAIL"} — ${checks-fails}/${checks} checks passed against live app.html source`);
process.exit(fails===0?0:1);
