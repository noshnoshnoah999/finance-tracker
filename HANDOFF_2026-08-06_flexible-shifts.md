# Handoff — Flexible Work Schedule (add / remove shift days)

**Date:** 2026-08-06
**Session:** Cowork
**Status:** Code complete, tested, **NOT committed** (sandbox could not write to `.git` — see Blocker)

---

## What Noah asked for

> "I don't like how these three shifts are fixed because I don't really work on Tuesdays,
> so I want to be able to remove shifts and also add new shifts on different days."

Plus, on follow-up:

> "When you change the things about the Tuesday work shifts I still want to count any shifts
> that I worked previously on Tuesday as a workday and I wanted to include it in the transport
> cost calculation, because in July I did work a few Tuesday shifts."

---

## The real problem (not just a UI change)

The Work Schedule card only *looked* fixed because both UIs hardcoded the day list —
`[1,2,0]` in `app.html`, `["1","2","0"]` in `SettingsView.swift`. The data layer
(`gEstHours`, `sHIM`, `avgShiftPay`, `Finance.swift`) already iterated `Object.keys(shifts)`
and handled arbitrary days fine.

The trap was a **second, separate setting**: `se.workDays` (default `[0,1,2]`), which decides
which weekdays the calendar treats as work days, and therefore drives transport cost and the
estimated-pay projection. It had **no editing UI anywhere**, web or native.

`getDayState` resolves in this order:

```
customDays[date]  →  PAID_LEAVE  →  workDays.includes(dow)  →  "none"
```

So a past worked Tuesday that was never explicitly marked in `customDays` is "work" **only**
because `2` sits in `workDays`. Removing `2` would silently flip every past Tuesday to
"none" — retroactively cutting July's work-day count, transport and hours.

The reverse is equally bad: **adding** Wednesday would retroactively turn all 31 past
Wednesdays in 2026 into work days, inflating Jan–Jul. (Found by the test harness, not by
reading — see Testing.)

---

## Design decisions (confirmed with Noah before building)

| Decision | Choice |
| --- | --- |
| Shifts vs. workDays | **Shifts define work days.** `se.workDays` is kept in lockstep with `Object.keys(se.shifts)`. One list, cannot drift. |
| Multiple shifts per weekday | **No.** Keeps the existing object-keyed-by-day model — no migration, no risk to saved data. |
| Past days not actually worked | **Freeze all past days as they currently render.** History stays byte-identical; Noah fixes any over-counted days himself on the Budget tab calendar. |
| History cutoff | **Today (2026-08-06), inclusive.** Tue 4 Aug stays a work day; Tue 11 Aug onward do not. |

---

## Implementation

### New shared constants

`app.html` / `index.html` (near `PAID_LEAVE`) and `ios/Budget/Shared/Models.swift`:

```
DOW_LABELS = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
DOW_FULL   = ["Sunday", ... ,"Saturday"]
DOW_ORDER  = [1,2,3,4,5,6,0]     // display order only, Monday first
```

Keys of `se.shifts` are JS `getDay()` numbers: `0` = Sunday … `6` = Saturday.

### `freezeDOW(dow, val)` — the history guard

Runs **before** a weekday joins or leaves `workDays`. Pins every past date of that weekday
(through today) to the state it has right now:

- removing a day → pass `"work"` (they'd otherwise drop to "none")
- adding a day → pass `"none"` (they'd otherwise jump to "work")

Skips dates that already carry an explicit `customDays` entry, and skips `PAID_LEAVE` dates.

On **removal** there is a second leak: those pinned "work" days would credit 0 hours once the
times are gone from `se.shifts`, and would trip the "⚠ no shift time set" warning on the Wage
tab. So removal also copies the shift into that month's `shiftOverrides`.

### `gShifts` / `Calc.shifts(_:)` — now a UNION

Previously both walked only the **base** schedule keys, so an override for a weekday no longer
in the base was ignored. Both now iterate `base.keys ∪ overrides.keys`, with a
`start`/`end`-present guard so a partial override can't produce a malformed shift object.
**This is required for the freeze to work** — without it, past months lose the removed day's hours.

### Files changed

| File | Change |
| --- | --- |
| `app.html` | `DOW_*` consts + `dstr`; `gShifts` union; `freezeDOW` / `rmShift` / `addShift`; `nSD` state; dynamic Settings → Work Schedule card with `×` delete + "Add a day…" picker; Budget-tab per-month shift editor de-hardcoded (was `[1,2,0]` at two spots) |
| `index.html` | Identical — now byte-for-byte equal to `app.html` |
| `ios/Budget/Shared/Models.swift` | `DOW_LABELS` / `DOW_FULL` / `DOW_ORDER` |
| `ios/Budget/Shared/Finance.swift` | `shifts(_:)` union fix |
| `ios/Budget/Budget/BudgetStore.swift` | `freezeDOW(_:_:)`, `removeShift(_:)`, `addShift(_:)` |
| `ios/Budget/Budget/SettingsView.swift` | Dynamic schedule card, delete button + confirm alert, add-day `Picker`, Weekly total row; `newShiftDow` / `pendingRemove` state |

### Also fixed this session

`index.html` was missing the **Amazon (Subscribe & Save)** line in Dad's Contributions that
`app.html` got in commit `13b3740` — a pre-existing web-to-web parity gap. The two files are
now identical.

---

---

## Part 2 — Configurable default break (`se.defaultBreak`)

**Asked for:** "I want to be able to change the default break, between 60 mins and 30 mins.
Not just here [Limit page] but in the whole app."

The per-shift break box was *already* editable everywhere (Settings, Budget tab per-month
editor, simulator rows). What was hardcoded at 60 was the **default given to newly created
shifts**, in 9 places. All now read a single setting.

**Decisions (confirmed):** a real setting, not a hardcoded flip to 30; and it applies to
**new shifts only** — existing Mon/Sun shifts keep their saved 60 min, so logged hours,
pay estimates and ¥1,030,000 headroom do not move.

### Wiring

`se.defaultBreak` seeded at `60` in `DS` (web) / `DS.defaultBreak` (Swift). Read through:

- web `dfBrk()` — clamps 0–480, falls back to 60
- native `Calc.defaultBreak` — same clamp and fallback

Replaced: web `addShift` (new schedule day), simulator `shiftH` fallback, simulator
"+ Add a shift", the Claude-advice prompt string, and the help text (now shows the live
value + "change it in Settings"); native `BudgetStore.addShift`, `LimitView` sim-shift add,
and the same help text.

**Deliberately left at literal 60:** the `DS.shifts` seed (`app.html` L91/L93). That is
brand-new-install data representing Noah's original Mon/Sun shifts, written before any
setting could exist.

### UI

Settings → Work Schedule gains a "Default break for new shifts" row: a numeric field plus
quick **30** / **60** buttons, with a note that existing shifts are unaffected. Same on
both platforms.

### Third bug the tests caught

`Number(null) === 0` and `Number("") === 0`, both finite — so a JSON `null` arriving from
sync would have silently meant *"no break at all"*, quietly inflating every new shift's
hours. `dfBrk()` now guards `null` / `undefined` / `""` explicitly before the numeric
coercion. The Swift side was already safe: `JSONValue.double` returns `nil` for `.null`.

### Known cosmetic quirk (not fixed)

The shared `NI` numeric input renders `value={value||""}`, so a `defaultBreak` of **0**
shows as an empty box. Pre-existing behaviour affecting every numeric field in the app;
fixing it means touching them all, which is not worth the risk here. The 30/60 quick
buttons make it a non-issue in practice.

---

## Testing

Two Node harnesses (in the Cowork outputs folder, not committed):

- `test_backfill.js` — transcribed logic, 23 checks
- `test_live_source.js` — **extracts `freezeDOW` / `rmShift` / `addShift` / `gShifts` /
  `dfBrk` verbatim from `app.html` and executes them**, so it tests shipped source rather
  than a copy. 31 checks, including the full `defaultBreak` fallback matrix
  (`undefined` / `null` / `""` / `"abc"` / `Infinity` / negative / absurd / `0`).

Both PASS. Invariant asserted: *no date on or before today changes state or credited hours.*

Rollups with Tuesday removed (dates ≤ today):

```
2026-01  workdays 12->12   hours 58->58     warnings 0->0
2026-03  workdays 15->15   hours 82.5->82.5 warnings 0->0
2026-07  workdays 11->11   hours 55->55     warnings 0->0
2026-08  workdays  3->3    hours 14.5->14.5 warnings 0->0
```

Future months correctly drop Tuesdays and raise **zero** "no shift set" warnings.

**The tests earned their keep three times** — they caught (1) the missing `shiftOverrides`
copy, which silently zeroed past hours, (2) the symmetric add-a-day bug that would have
rewritten 31 past Wednesdays, and (3) the `Number(null) === 0` hole in `dfBrk()`. None of
the three was visible by reading the diff.

**Not verified:** Swift does not compile in the Linux sandbox (no `swiftc`). Brace/paren
balance checked on all four Swift files. **Build in Xcode before trusting the native side.**

---

## Blocker — stale git lock

A `git stash` attempted from the sandbox failed against the shared `.git` directory. It
created `.git/index.lock` (0 bytes) which the sandbox **cannot delete**
(`Operation not permitted`). There is also a stale `.git/objects/5c/tmp_obj_H91JJF`.

**No work was lost** — `git stash list` is empty and all edits are intact on disk.

Removing the lock and committing must happen locally. See
`CLAUDE_CODE_PROMPT_push-flexible-shifts.md`.

*Lesson, matching the existing `git-shared-repo-collision` memory: run **no** mutating git
commands from the Cowork sandbox. Read-only inspection only; hand commits to Claude Code.*

---

## Known gaps / follow-ups (not done, deliberately)

1. **Dead code**: `app.html` lines ~578–586 compute `pTotalH` / `pTotalDays` / `pW` / `pNT` /
   `pR` / `pFA` / `pFH` / `pHasInput` from hardcoded `pH.pMon` / `pTue` / `pSun`. **None of it
   reaches JSX** — superseded by the `simShifts` simulator (which already offers all 7 days).
   Left in place to keep this diff minimal. Worth deleting in a separate cleanup commit;
   it hardcodes exactly the assumption this change removes.
2. **iOS has no per-month shift override editor.** The web Budget tab lets you change a shift
   for a single month; the native app has no equivalent UI. Pre-existing gap, not introduced here.
   `Finance.swift` reads the overrides correctly, so native numbers stay right.
3. **Noah should review past Tuesdays.** Every past Tuesday is now pinned as worked. If some
   weren't actually worked, they were *already* being over-counted before this change — the
   freeze preserves that, it doesn't create it. Fix on the Budget tab calendar per month.
