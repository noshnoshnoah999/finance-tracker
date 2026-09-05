// Tests openOneOffFor — the function behind "+ One-off → tap a day". The whole point of the
// 2026-09-05 rework is that picking a day the weekly schedule ALREADY covers must open the
// editor pre-filled with that day's real times (so Noah can change 17:00 to 14:00), not blank
// fields. Blank fields were the original defect: the button opened on today (a Saturday he
// doesn't work), which read as "add a new shift" rather than "edit this one".
const fs = require("fs"), path = require("path");
const SRC = path.join(__dirname, "app.html");
const html = fs.readFileSync(SRC, "utf8");
const grab = n => { const i = html.indexOf(`      const ${n}=`); if (i<0) throw new Error(n); return html.slice(i, html.indexOf("\n", i)).trim(); };
const grabTop = n => { const i = html.indexOf(`    const ${n}=`); if (i<0) throw new Error(n); return html.slice(i, html.indexOf("\n", i)).trim(); };

const eM = () => ({customDays:{}, shiftOverrides:{}, oneOffShifts:{}});
// Noah's real schedule: Mon 09:00-18:00/30m, Sun 10:30-17:00/30m. No Tuesday.
let se = { shifts:{ 1:{start:"09:00",end:"18:00",breakMin:30}, 0:{start:"10:30",end:"17:00",breakMin:30} },
           workDays:[0,1], hourlyWage:1100, defaultBreak:60 };
let da = { "2026-09": eM() };
const bm = "2026-09";
let oosEdit = null;
const setOosEdit = v => { oosEdit = v; };

const src = [grabTop("sH"), grab("dfBrk"), grab("gShifts"), grab("openOneOffFor")].join("\n");
const ctx = eval(`(function(){ ${src}\n return {openOneOffFor, gShifts, dfBrk}; })`).call(null);

let fails=0, checks=0;
const check=(l,c)=>{checks++; console.log((c?"  ok   ":"  FAIL ")+l); if(!c)fails++;};

console.log("\n--- Sunday 2026-09-06: covered by the weekly schedule (this is Noah's case) ---");
ctx.openOneOffFor("2026-09-06");
console.log("  editor opened with:", JSON.stringify(oosEdit));
check("date is the day that was tapped", oosEdit.ds === "2026-09-06");
check("start pre-filled from the Sunday schedule (10:30), NOT blank", oosEdit.start === "10:30");
check("end pre-filled from the Sunday schedule (17:00), NOT blank", oosEdit.end === "17:00");
check("break pre-filled from the Sunday schedule (30), not the 60 default", oosEdit.breakMin === 30);

console.log("\n--- Monday 2026-09-14: different weekday, must pull ITS own times ---");
ctx.openOneOffFor("2026-09-14");
check("Monday pre-fills 09:00-18:00, not Sunday's times", oosEdit.start==="09:00" && oosEdit.end==="18:00");

console.log("\n--- Tuesday 2026-09-15: NOT in the schedule — blank is correct here ---");
ctx.openOneOffFor("2026-09-15");
check("unscheduled day opens blank, ready for a brand-new one-off", oosEdit.start==="" && oosEdit.end==="");
check("unscheduled day gets the default break (60)", oosEdit.breakMin === 60);

console.log("\n--- A date that already has a saved one-off must re-open THAT, not the weekday default ---");
da["2026-09"].oneOffShifts = {"2026-09-06":{start:"10:30",end:"14:00",breakMin:30}};
ctx.openOneOffFor("2026-09-06");
check("re-opening 09-06 shows the saved 14:00 end, not the schedule's 17:00", oosEdit.end === "14:00");

console.log("\n--- A per-month weekday override must win over the base schedule ---");
da["2026-09"].oneOffShifts = {};
da["2026-09"].shiftOverrides = {0:{start:"11:00",end:"16:00",breakMin:45}};
ctx.openOneOffFor("2026-09-20");
check("Sunday pre-fills from the month's override (11:00-16:00/45m)",
      oosEdit.start==="11:00" && oosEdit.end==="16:00" && oosEdit.breakMin===45);

console.log(`\n${fails===0?"PASS":"FAIL"} — ${checks-fails}/${checks} checks passed against live app.html source`);
process.exit(fails===0?0:1);
