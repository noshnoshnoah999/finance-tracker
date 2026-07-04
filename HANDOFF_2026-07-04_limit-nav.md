# Handoff — Limit simulator + Home nav fixes (2026-07-04)

Commit: `e539c40` — **committed, NOT pushed** (push from Claude Code, see prompt below).

## What was reported
Three things "still not fixed":
1. In "Can I work these shifts?", entering **2pm–5pm** still showed **2.0h**.
2. The Monday shift showed **×5 this month** when July has only 4 Mondays.
3. The **Budget →**, **Wages →**, and **Limit →** cards on Home didn't navigate.

## Root causes (all in the native iOS app; web was mostly fine)
1. **Break auto-deduction.** New sim shifts default to `breakMin: 60`, and any shift `>= 3h` deducted the break. 3h − 60m = 2.0h. Also wrong under Japan's Labor Standards Act Art. 34 (no break required under 6h).
2. **Wrong month.** `occurrences()` counted `MONTHS[currentMonthNumber]` = **next month (August)**, which has 5 Mondays, while every label said "this month". Same off-by-one (`nMK`) existed in web.
3. **No navigation wiring.** iOS `TabView` had **no `selection` binding** and the cards had **no tap gesture** — there was no way to switch tabs. (Web already had working `setTab` handlers, so this was iOS-only.)

## Changes
### Bug 1 — break threshold (web + iOS)
- Threshold changed from `>= 3` to `> 3`. A 3-hour-or-under shift keeps its full time; breaks still apply to longer shifts.
- Files: `app.html` / `index.html` (`shiftH`, shiftLines label), `ios/.../LimitView.swift` (`shiftHours`, advisor line), helper text updated in both.

### Bug 2 — month picker (web + iOS)
- Simulator now has a **"Planning for" month picker**: current month → December, **defaults to the current month**.
- All "this month" labels now show the chosen month's name.
- Web: new `simPlanMK` state + `planMK`/`planLabel`/`planMonths` in the simulator block; gate changed from `nMK` to `cMN>=1`.
- iOS: new `@State planMK` + `currentMK`/`effectivePlanMK`/`planMonths`/`planLabel` helpers; `occurrences()` uses `effectivePlanMK`.

### Bug 3 — Home navigation (iOS only)
- `BudgetStore`: added `@Published selectedTab: Int` and `@Published openLimit: Bool`.
- `ContentView`: `TabView(selection: $store.selectedTab)` with `.tag(0…4)` (Home 0, Wage 1, Budget 2, Savings 3, More 4).
- Home cards get `.contentShape(Rectangle()).onTapGesture`: Wages→1, Budget→2, Limit→4 + `openLimit=true`.
- `MoreView`: added `@EnvironmentObject store` + `.navigationDestination(isPresented: $store.openLimit) { LimitView() }` so the Limit card deep-links through the More tab.

## Verification done
- Brace/paren balance check passed on all 3 Swift files.
- Node date math: July 2026 = **4 Mondays** (default now correct); 2pm–5pm = **3.0h**; 9am–5pm (8h) still 7.0h with break.
- **Not yet built in Xcode** — no Swift compiler in this environment. Build + tap-test on device before shipping.

## Follow-ups / watch-outs
- `openLimit` is reset by the `navigationDestination` binding on back-nav. Edge case: if you switch tabs while Limit is pushed then return to More, it stays pushed (harmless).
- Saved/Silver Home cards still don't navigate — not in scope this session.
- Confirm on device that the iOS month `Menu` picker matches the app's warm-tan theme.
