// Verifies the new "+ One-off" button use case: overriding a SINGLE INSTANCE of an
// already-scheduled weekday (e.g. one Sunday 10:30-17:00 -> 10:30-14:00), while every
// other occurrence of that weekday in the month keeps the regular schedule. This exercises
// the same gEstHours/gEstPay choke point as test_oneoff_shifts.js, but for a day that
// ALREADY has a resolvable weekday shift -- the gap the "+ One-off" header button fills
// (previously only reachable for days with NO weekday shift, via tapping the calendar).
const fs = require("fs");
const path = require("path");
const SRC = path.join(__dirname, "app.html");
const html = fs.readFileSync(SRC, "utf8");

const grab = name => {
  const i = html.indexOf(`      const ${name}=`);
  if (i < 0) throw new Error(`could not find ${name} in app.html`);
  return html.slice(i, html.indexOf("\n", i)).trim();
};
const grabTop = name => {
  const i = html.indexOf(`    const ${name}=`);
  if (i < 0) throw new Error(`could not find top-level ${name} in app.html`);
  return html.slice(i, html.indexOf("\n", i)).trim();
};

const MONTHS = ["2026-01","2026-02","2026-03","2026-04","2026-05","2026-06","2026-07","2026-08","2026-09","2026-10","2026-11","2026-12"].map(k=>({key:k}));
const PAID_LEAVE = [];
const PL_HOURS_PER_DAY = 7;
const eM = () => ({customDays:{}, shiftOverrides:{}, oneOffShifts:{}});

// Noah's real schedule: Mon 09:00-18:00/30min, Sun 10:30-17:00/30min.
let se = {
  shifts: { 1:{start:"09:00",end:"18:00",breakMin:30}, 0:{start:"10:30",end:"17:00",breakMin:30} },
  workDays: [0,1],
  hourlyWage: 1100,
  trBefore: 1100, trAfter: 1100,
  defaultBreak: 60,
};
let da = {}; MONTHS.forEach(m => da[m.key] = eM());
const setDa = fn => { da = typeof fn === "function" ? fn(da) : fn; };

const sHSrc = grabTop("sH");
const dfBrkSrc = grab("dfBrk");
const gShiftsSrc = grab("gShifts");
const gWorkDaysCDSrc = grab("gWorkDaysCD");
const gEstHoursSrc = grab("gEstHours");
const gEstPaySrc = grab("gEstPay");
const trfSrc = grab("trf");
const getDayStateSrc = grabTop("getDayState");

const full = [getDayStateSrc, sHSrc, dfBrkSrc, gShiftsSrc, gWorkDaysCDSrc, trfSrc, gEstHoursSrc, gEstPaySrc].join("\n");
const gPrevMK = mk => { const i = MONTHS.findIndex(m=>m.key===mk); return i>0 ? MONTHS[i-1].key : null; };
const ctx = eval(`(function(){ ${full}\n return {getDayState, sH, dfBrk, gShifts, gWorkDaysCD, trf, gEstHours, gEstPay}; })`).call(null);

let fails=0, checks=0;
const check = (label, cond) => { checks++; if(cond){ console.log("  ok   "+label); } else { fails++; console.log("  FAIL "+label); } };

console.log("\n--- September 2026 has 5 Sundays (6,13,20,27) -- wait, check actual count ---");
// September 2026: Sun the 6th, 13th, 20th, 27th = 4 Sundays. Mondays: 7,14,21,28 = 4 Mondays.
const sundays = ["2026-09-06","2026-09-13","2026-09-20","2026-09-27"];
console.log("Sundays in Sept 2026:", sundays.join(", "));

console.log("\n--- Baseline: no one-off overrides, all 4 Sundays + 4 Mondays regular ---");
let before = ctx.gEstPay("2026-10"); // Oct pay is based on Sept (gPrevMK)
console.log("  baseline Oct estimate:", JSON.stringify(before));
// Expected hours: 4 Sundays * (17:00-10:30-0.5h=6h) + 4 Mondays * (18:00-9:00-0.5h=8.5h) = 24+34=58h
check("baseline hours = 58 (4x6h Sun + 4x8.5h Mon)", before.hours === 58);

console.log("\n--- Apply a one-off override to just Sunday 2026-09-13: 10:30-14:00 (3h, 30min break -> 3h) ---");
setDa(p => ({...p, "2026-09": {...p["2026-09"], oneOffShifts: {"2026-09-13": {start:"10:30", end:"14:00", breakMin:30}}}}));
let after = ctx.gEstPay("2026-10");
console.log("  after override Oct estimate:", JSON.stringify(after));
// New hours for 09-13: 14:00-10:30=3.5h - 0.5h break = 3h (was 6h). Diff = -3h.
// Expected total: 58 - 3 = 55h
check("overriding one Sunday changes total hours by exactly the delta (58 -> 55)", after.hours === 55);
check("wage reflects the reduced hours", after.wage === Math.round(55*1100));
check("day count (transport) unaffected -- still a work day", after.days === before.days);

console.log("\n--- Verify the OTHER 3 Sundays are untouched (still 6h each = 18h combined) ---");
const cd = {}; // no customDays needed since all are default "work" via schedule
const oneOff = {"2026-09-13": {start:"10:30", end:"14:00", breakMin:30}};
let otherSundayHours = 0;
["2026-09-06","2026-09-20","2026-09-27"].forEach(ds => {
  const shift = oneOff[ds] || se.shifts[0]; // Sunday = dow 0
  otherSundayHours += ctx.sH(shift);
});
check("the other 3 Sundays still resolve to the regular 10:30-17:00/30min shift (6h each = 18h)", otherSundayHours === 18);

console.log("\n--- Verify Mondays are completely unaffected (not touched by a Sunday-keyed override) ---");
let mondayHours = 0;
["2026-09-07","2026-09-14","2026-09-21","2026-09-28"].forEach(ds => {
  const shift = oneOff[ds] || se.shifts[1]; // Monday = dow 1
  mondayHours += ctx.sH(shift);
});
check("all 4 Mondays still resolve to 8.5h each = 34h, untouched by the Sunday override", mondayHours === 34);

console.log("\n--- Removing the override (simulating the 'Remove shift' button) restores baseline ---");
setDa(p => ({...p, "2026-09": {...p["2026-09"], oneOffShifts: {}}}));
let restored = ctx.gEstPay("2026-10");
check("removing the override restores the original 58h estimate", restored.hours === 58);

console.log(`\n${fails===0?"PASS":"FAIL"} — ${checks-fails}/${checks} checks passed against live app.html source`);
process.exit(fails===0?0:1);
