# Handoff — One-off override for an ALREADY-SCHEDULED day (web + iOS)

**Date:** 2026-09-05
**Session:** Cowork
**Status:** Code complete, tested, **NOT committed by this session directly** — see push prompt at the bottom (per this project's git-lock-collision rule, Cowork commits, Claude Code pushes). All web edits verified byte-identical between `app.html`/`index.html`. iOS edits are NOT compiled (no Swift toolchain in this sandbox) — manually checked for brace balance and type correctness; **must be built in Xcode before trusting it**.

## What Noah asked for

His regular schedule includes Sunday 10:30–17:00 (30min break). He wanted to change ONE specific Sunday's hours (e.g. to 10:30–14:00) as a one-off, without touching the recurring Sunday schedule or any other Sunday that month.

## Why the existing "one-off shifts" feature (2026-08-20) didn't cover this

That feature's entry point — tapping a calendar day — only opens the one-off editor when the tapped date's weekday has **no resolvable shift** (`!hasResolvableShift` in `toggleDay`). Sunday already has a resolvable shift (it's in the regular schedule), so tapping a Sunday only ever cycled its day-state (work → hol → pl → off); there was no UI path to override just its hours for one date.

The underlying data model and calc engine (`oneOffShifts[date]`, and `gEstHours`/`gEstPay` checking the exact date before falling back to the weekday default) already supported this correctly — confirmed by reading `gEstHours`'s line `const sh=oo||shifts[d.getDay()]`, which checks the one-off first regardless of whether the weekday also has a shift. The only gap was the UI entry point.

## Design (confirmed with Noah before building)

| Decision | Choice |
| --- | --- |
| Trigger | A new "+ One-off" button in the Work Schedule card header (both web Budget tab and iOS), NOT a change to tap/long-press behavior on the calendar grid — regular taps keep cycling work→hol→pl→off exactly as before. |
| Date selection | A date picker inside the same one-off editor box (web: `<input type="date">`; iOS: `DatePicker`), not a separate flow. Defaults to today (or the 1st of the viewed month if that month is in the future). |
| Time range | Current month and future months only. The button is hidden entirely when the viewed month (`bm`) is wholly in the past. This matches the existing rule that `oneOffShifts` only ever affects **projected/estimated** pay, never the manually-typed current-month logged-hours total. |
| Pre-fill | Opening the editor for a date pre-fills from whatever shift already resolves for that date (an existing one-off first, else the weekday's regular/overridden schedule) — so the user edits from a real baseline, not blank fields. |

## Implementation

### Web (`app.html`/`index.html`)
- New helpers (added right after `gShifts`, ~line 524): `oneOffMinDate()` (today, or month-start for a future `bm`), `oneOffMaxDate()` (last real day of `bm`), `oneOffAvailable()` (true iff `bm >= current month`), `openOneOffFor(ds)` (opens `oosEdit` pre-filled for any date, bypassing the old `hasResolvableShift` gate — this is the one new capability).
- Work Schedule card header (Budget tab, ~line 1225): new "+ One-off" button, shown only when `oneOffAvailable()`.
- The existing `oosEdit` box gained a `<input type="date">` field (bounded by `oneOffMinDate()`/`oneOffMaxDate()`) and a caption clarifying "This changes only [date] — every other [Weekday] keeps the regular schedule."
- `saveOneOff`/`removeOneOff`/`toggleDay`'s existing interception (re-tapping a work day that already has a one-off) were **not changed** — they already worked generically by exact date, whether or not that weekday also has a regular shift.

### iOS (SwiftUI)
- `BudgetStore.swift`: **no changes** — `oneOffShift`/`saveOneOffShift`/`removeOneOffShift` already operate generically by date, mirroring the web exactly.
- `Finance.swift`: **no changes** — `Calc.shifts`/`Calc.weekday` already existed and were reused as-is.
- `BudgetTabView.swift`: new `oneOffAvailable`, `oneOffMinDate`, `oneOffMaxDate`, `openOneOffFor` (mirror the web helpers exactly); new "+ One-off" button in the Work Schedule card header; `oneOffShiftBox` gained a `DatePicker` (bound via new `dsToDate`/`dateToDs` static helpers that convert "YYYY-MM-DD" strings using `Calendar.current` at **noon local time**, deliberately not UTC, so the date shown always matches the intended calendar day regardless of timezone — this was a real bug I caught and fixed during implementation, not a hypothetical) and the same "only this date" caption.

### Files changed
| File | Change |
| --- | --- |
| `app.html` | `oneOffMinDate`/`oneOffMaxDate`/`oneOffAvailable`/`openOneOffFor` helpers; "+ One-off" header button; date field + caption in `oosEdit` box |
| `index.html` | Identical — byte-for-byte equal to `app.html`, confirmed via diff |
| `ios/Budget/Budget/BudgetTabView.swift` | Same four helpers (Swift); "+ One-off" header button; `DatePicker` + caption in `oneOffShiftBox`; new `dsToDate`/`dateToDs`/`dowFull` |
| `ios/Budget/Budget/BudgetStore.swift` | Unchanged |
| `ios/Budget/Shared/Finance.swift` | Unchanged |

## Testing

- `test_oneoff_shifts.js`, `test_live_source.js` (both pre-existing) — re-run, still PASS (11/11, 31/31). Confirms the calc engine (untouched by this change) still works.
- `test_oneoff_on_scheduled_day.js` (**new**, 7 checks) — reproduces Noah's exact request: a September 2026 Sunday (10:30–17:00) overridden to 10:30–14:00 via `oneOffShifts`. Verifies: (1) baseline October estimate is 58h across 4 Sundays + 4 Mondays, (2) after the override the estimate drops by exactly 3h (58→55h) — the delta between the old 6h shift and new 3h shift, (3) wage reflects the reduced hours, (4) transport/day-count is unaffected (still a work day), (5) the other 3 Sundays are untouched (still 6h each), (6) all 4 Mondays are completely untouched, (7) removing the override restores the 58h baseline.

```
$ node test_oneoff_shifts.js        → PASS 11/11
$ node test_live_source.js          → PASS 31/31
$ node test_oneoff_on_scheduled_day.js → PASS 7/7
$ diff app.html index.html          → identical
```

**Not verified:** Swift does not compile in this sandbox. Checked brace/paren balance (258/258, 1063/1063) and cross-referenced every new type/accessor against existing usage (`JSONValue.s()`/`.d()`, `Calc.shifts`/`.weekday`/`.daysIn`, `T.blueD`, `FieldStyle()`). **Build in Xcode before trusting the native side.**

## Known gaps / follow-ups (not done, deliberately)

1. Past months are blocked entirely (button hidden) rather than offering a read-only view of what would have been possible — matches the "current/future only" decision, but if Noah ever wants to correct a past estimate mistake, this needs revisiting deliberately (per this project's own memory rule about not blindly trusting stale entries).
2. No confirmation dialog on overwriting an existing one-off via the date picker (picking a date that already has a saved one-off silently loads it for editing — same as the existing tap-to-reopen behavior, not a new risk, but noting it since the button makes it easier to stumble into).
3. iOS `DatePicker` style (`.compact`, forced `.colorScheme(.dark)` to read against the blue box background) hasn't been visually checked in Xcode — matches the web's dark-on-blue box aesthetic in intent, but worth a visual pass once built.
