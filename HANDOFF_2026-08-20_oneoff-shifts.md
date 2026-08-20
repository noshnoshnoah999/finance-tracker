# Handoff — One-off shifts on non-schedule days (web + iOS)

**Date:** 2026-08-20
**Session:** Cowork
**Status:** Code complete, tested, **NOT committed** (sandbox must not run mutating git commands — see `git-shared-repo-collision` memory). All edits are written to disk and verified byte-identical between `app.html`/`index.html`.

---

## What Noah asked for

His regular schedule is Monday 09:00–18:00 (30min break) and Sunday 10:30–17:00 (30min break) — no Tuesday. He picks up occasional one-off shifts on days that aren't part of that schedule (e.g. a one-off Tuesday) and wanted a way to record that specific date's hours and break, distinct from his weekly schedule, that flows through to pay/transport estimates everywhere in the app.

He'd already hit the bug live: a one-off shift he logged in September only added ¥1,100 (the transport reimbursement) to October's estimated pay — 0 wage credited — because there was nowhere to store an exact-date shift.

## The real problem

`gEstHours` (web) / `Calc.estHours` (Swift) is the single function that turns a month's calendar (`customDays`) + weekly schedule (`se.shifts` / `shifts(mk)`) into projected hours for "Estimated Pay" (used on the homepage next-paycheck card, Wage tab, Budget-tab totals, and the AI advice prompt). For a `"work"` day it only ever looked up `shifts[d.getDay()]` — the weekday's shift. A day marked "work" whose weekday has no shift defined (like a one-off Tuesday, since Tuesday isn't in the schedule) fell through to `noShiftDays++` and contributed 0 hours, while the separate work-day count (`gWorkDaysCD`) still counted it for transport. That's the exact ¥1,100-transport-only symptom Noah saw.

Note: this only affects **projected/estimated** hours for a future/unlogged month. The **current month's logged hours** (`d.hours`) is a single number Noah types in by hand from his KOT timesheet — confirmed with him that he'll still add a one-off shift's hours into that manual total himself; the app doesn't (and per his confirmation, shouldn't) auto-add it.

## Design (confirmed with Noah before building)

| Decision | Choice |
| --- | --- |
| Entry point | Budget tab calendar. Tapping a date that isn't part of the weekly schedule (no resolvable shift) and has no saved one-off yet opens a box pinned above the calendar grid. |
| Multiple one-offs | Unlimited, fully independent per exact date. Re-tapping a date that already has a one-off reopens the box pre-filled for editing. |
| Data model | Brand-new structure, `oneOffShifts` — keyed by exact date (`"YYYY-MM-DD"`) inside each month's data object, holding `{start, end, breakMin}`. Completely separate from `se.workDays`, `se.shifts`, and the existing per-weekday `shiftOverrides`/`freezeDOW` machinery (see `shift-days-workdays-coupling` memory) — none of that is touched. |

## Implementation

### New data field
`oneOffShifts: {}` added to the default month object (`eM()` in web, and Swift's `JSONValue` tree just round-trips the new key automatically — no `Models.swift` change needed).

### The choke-point fix
`gEstHours(mk, cd, shifts, wd, oneOff)` (web, `app.html`/`index.html`) and `Calc.estHours` (Swift, `Finance.swift`) now check `oneOff[ds]` (the exact date) **before** falling back to `shifts[d.getDay()]` (the weekday). Only if both miss does the day count as `noShiftDays`. `gEstPay`/`Calc.estimatedPay` pass the previous month's `oneOffShifts` through. This is the single choke point — fixing it here automatically fixes the homepage next-paycheck card, Wage tab estimate, Budget-tab totals card, and the AI advice prompt (`buildEstimateLines`) on both platforms, since they all call through `gEstPay`/`estimatedPay`.

### Calendar UI (web: `renderCal` in `app.html`/`index.html`; native: `BudgetTabView.swift`)
- Tapping a `"none"` day whose weekday **has** a resolvable shift: unchanged, becomes `"work"` immediately.
- Tapping a `"none"` day whose weekday has **no** resolvable shift and no saved one-off: opens the box — "Choose the hours and break duration for the shift on `[date]`" — with start/end time fields and a break-minutes field (defaulting to `se.defaultBreak`/`Calc.defaultBreak`). Nothing is written until Save.
- Saving writes `customDays[date]="work"` **and** `oneOffShifts[date]={start,end,breakMin}` together, and re-syncs the stored work-day count (drives transport/SUICA), same as the existing toggle path.
- Tapping a `"work"` day that has a saved one-off entry reopens the box pre-filled, instead of cycling to `"hol"` (which would strand the `oneOffShifts` entry with nothing pointing at it). A "Remove shift" button clears both `customDays[date]` and `oneOffShifts[date]`, returning the day to `"none"`.
- Calendar cells with a one-off shift show a small "1×" tag (like the existing PL/HOL/OFF tags) so they're visually distinguishable from regular schedule work days.

### Native (Swift) specifics
- `BudgetStore.swift`: `needsOneOffShiftPrompt`, `oneOffShift`, `hasOneOffShift`, `saveOneOffShift`, `removeOneOffShift` — mirror the web functions exactly. `toggleDay` itself is **unchanged**; the interception happens at the view layer (`BudgetTabView.tapDay`) before calling `store.toggleDay`, to avoid touching the existing, already-tested day-cycling logic.
- `Finance.swift`: added a public `Calc.weekday(y,m,d)` wrapper around the previously-private `jsDay`, since `BudgetStore` needed to look up a date's weekday without duplicating the JS-getDay() math.
- `BudgetTabView.swift`: new `@State` (`oosEditDS`, `oosStart`, `oosEnd`, `oosBreak`), `oneOffShiftBox` view, `tapDay` handler, `dayCell` updated to pass through state, reset on month change (`onChange(of: bm)`).
- No `WageView.swift` or `LimitView.swift` changes needed — both already call through `Calc.estimatedPay`/`projectedMonthlyPay`, which now sees the fix automatically.

### Files changed
| File | Change |
| --- | --- |
| `app.html` | `eM()` gains `oneOffShifts:{}`; `gEstHours`/`gEstPay` check the exact date first; `renderCal` gains the one-off box, `toggleDay` interception, `saveOneOff`/`removeOneOff`, "1×" tag; new `[oosEdit,setOosEdit]` state |
| `index.html` | Identical — byte-for-byte equal to `app.html`, confirmed via diff |
| `ios/Budget/Shared/Finance.swift` | `estHours` checks `oneOffShifts` for the exact date first; new public `Calc.weekday()` wrapper |
| `ios/Budget/Budget/BudgetStore.swift` | `needsOneOffShiftPrompt`, `oneOffShift`, `hasOneOffShift`, `saveOneOffShift`, `removeOneOffShift` |
| `ios/Budget/Budget/BudgetTabView.swift` | One-off shift box UI, `tapDay` interception, "1×" tag on the calendar, new `@State` |
| `ios/Budget/Shared/Models.swift` | **Unchanged** — the JSON tree is lossless, so the new `oneOffShifts` key round-trips with no model change needed |

## Testing

Two Node harnesses, run against the **real shipped source** (extracted verbatim from `app.html`/`index.html` and executed, not a transcription):

- `test_oneoff_shifts.js` (new) — 11 checks. Reproduces Noah's exact September bug (0 credited hours, transport still charged) against the pre-fix code path, then proves the fix: the one-off shift credits its own hours (a 09:00–17:00/60min shift = 7h), `noShiftDays` drops to 0, wage increases by exactly `hours × hourlyWage`, transport is unaffected, and a stray `oneOffShifts` entry with no matching `customDays` "work" mark is correctly ignored. Run against both `app.html` and `index.html` — both PASS.
- `test_live_source.js` (existing, from the Aug 6 flexible-shifts session) — 31 checks covering `freezeDOW`/`rmShift`/`addShift`/`gShifts`/`dfBrk`. Re-run to confirm this change didn't disturb that machinery. Both PASS.

```
$ node test_oneoff_shifts.js
PASS — 11/11 checks passed against live app.html source

$ node test_live_source.js
PASS — 31/31 checks passed against live app.html source
```

Web file parity verified with `diff app.html index.html` after the patch — identical.

**Not verified:** Swift does not compile in this sandbox (no `swiftc`). Checked brace/paren balance on all three edited Swift files (all balanced) and manually cross-referenced every new type/accessor against existing usage elsewhere in the codebase (e.g. `JSONValue.s()`/`.d()` optional-chaining, `FieldStyle`, `T.blueD`, `.buttonStyle(.borderedProminent)`) rather than guessing. **Build in Xcode before trusting the native side** — see the push prompt below.

## Known gaps / follow-ups (not done, deliberately)

1. **No delete-safety confirmation on "Remove shift".** Unlike the "remove a weekly schedule day" flow (which has a confirm alert on iOS), removing a one-off shift is immediate on both platforms. Low risk since it only affects one date, but worth a confirm dialog if Noah wants one.
2. **The "1×" tag is terse.** If Noah wants something clearer (e.g. a tooltip showing the actual hours on tap-and-hold), that's a follow-up, not done here to keep the diff minimal.
3. **iOS one-off box styling is a plain blue card**, matching the web box's color but not pixel-identical to any existing native pattern (there wasn't a directly analogous "colored info box with inline form" component to copy). Worth a visual check once built in Xcode.
