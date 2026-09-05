# Handoff — "+ One-off" reworked into arm-then-pick (web + iOS)

**Date:** 2026-09-05 (second session that day — supersedes the flow shipped in `f3005f7`)
**Status:** Committed from Cowork. Web tested (58 checks). **iOS not compiled here** (no Swift toolchain) — Noah must rebuild the native app (`reinstall_budget.sh`) to get it.

## What was wrong with the first attempt (f3005f7)

The "+ One-off" button opened the editor on **today's date**, with a date field inside the box to change it. For Noah that meant: clicking it on Sat 5 Sep opened a blank form for a Saturday he doesn't work. It read as "add a new shift", not "edit an existing one", and the path to "change this Sunday's end time to 14:00" was buried behind a date field most people won't find. His words: *"there is no way for me to change it, its still stuck on 17:00 end."*

Root cause was a process failure, not a coding one: I asked him **how the button should be triggered** and built exactly that, without checking the resulting flow actually solved the underlying task. The capability was present; it was unreachable.

Also relevant: clicking a scheduled day on the calendar cycles it Work → Holiday → Paid leave → Off, which is what he'd instinctively try first — so the natural gesture actively did the wrong thing.

## The flow now (chosen by Noah)

1. Click **"+ One-off"** in the Work Schedule header. It turns green and reads **"Pick a day…"**; the hint line under it changes to "Tap any day to edit its shift times".
2. Click **any** day — one the weekly schedule already covers (Sunday 6th) or one it doesn't (a one-off Tuesday). It does **not** cycle that day's state while armed.
3. The editor opens **pre-filled with that date's real times** (existing one-off → else that weekday's schedule/override → else blank for an unscheduled day). Change end to 14:00, Save.
4. Clicking the button again cancels arming. Changing month also disarms.

Tapping a day when **not** armed behaves exactly as before (cycle states; re-tap a `1×` day to edit it). Nothing about the existing calendar behaviour was removed.

## Implementation

**Web (`app.html`/`index.html`, kept byte-identical):**
- New `oosPick` state. Header button toggles it (`c.greenD` when armed) instead of opening the box.
- `toggleDay` gains a first branch: `if(oosPick){setOosPick(false);openOneOffFor(ds);return;}` — intercepts before any state cycling.
- Hint line is conditional and turns green/bold when armed.
- Editor box: the `<input type="date">` is **gone** (the day is chosen on the calendar now — two ways to pick a date was the confusion). It now shows `dsLabel(ds)` → "Sunday 6 September".
- Removed `oneOffMinDate`/`oneOffMaxDate` (dead once the picker went). `oneOffAvailable` stays — the button is still hidden on wholly-past months.
- "Remove shift" now reads **"Reset to regular"** on a day the weekly schedule covers, since that's what it does there (deletes the one-off, day falls back to the normal schedule). `removeOneOff` itself was already correct for both cases and is unchanged.

**iOS/macOS (`BudgetTabView.swift`) — mirrors the web exactly:**
- `@State oosPick`; button toggles it, `T.greenD` when armed; reset in `.onChange(of: bm)`.
- `tapDay` gains the same first-line interception.
- `oneOffShiftBox` lost its `DatePicker` (and with it `dsToDate`/`dateToDs`, which existed only to bridge "YYYY-MM-DD" ↔ `Date` for that picker) and gained `dsLabel` + `monthFull`.
- `isScheduled` drives the "Reset to regular" / "Remove shift" label.
- `BudgetStore.swift` and `Finance.swift` **unchanged** — `saveOneOffShift`/`removeOneOffShift`/`estHours` were already date-generic and correct.

## Testing

| Suite | Result |
| --- | --- |
| `test_oneoff_prefill.js` (**new**, 9 checks) | PASS — proves tapping a scheduled Sunday pre-fills 10:30/17:00/30m rather than blanks; Monday pulls its own 09:00–18:00; an unscheduled Tuesday correctly opens blank with the default break; a saved one-off re-opens its own saved times; a per-month weekday override wins over the base schedule |
| `test_oneoff_on_scheduled_day.js` (7) | PASS |
| `test_oneoff_shifts.js` (11) | PASS |
| `test_live_source.js` (31) | PASS |
| Babel JSX parse of the shipped `<script type="text/babel">` block | OK |
| `diff app.html index.html` | identical |

The calc engine was not touched in this rework — `gEstHours`/`gEstPay` already prioritise `oneOffShifts[date]` over the weekday default, which is why every downstream number (homepage next-paycheck card, Wage tab, Budget totals, AI advice, Limit page, iOS `projectedMonthlyPay`, iOS widget) reacts automatically. That was verified separately earlier today.

**Still not verified:** the Swift does not compile in this sandbox. Brace/paren balance checked (254/254, 1039/1039) and every new symbol cross-referenced against existing usage (`T.greenD`, `Calc.weekday`, `Calc.shifts`, `FieldStyle`). Build in Xcode before trusting it.

## Known gaps

1. `dsLabel` hard-codes English month/day names on both platforms (the app is English-only, so this is consistent with the rest of the file, but it is not localised).
2. While armed there is no visible affordance on the day cells themselves (no highlight/hover) — only the button and hint line indicate the mode. If it still feels unclear in use, highlighting selectable cells is the next step.
3. "Scheduled this month"/"Scheduled wage" on the **web** card remain template-only figures that ignore one-offs — deliberate, Noah decided to leave them (see `shim-template-not-actual` memory). The native card doesn't show those rows at all.
