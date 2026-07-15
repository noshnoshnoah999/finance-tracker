# Claude Code — Commit & Push Prompt (2026-07-15)

Cowork could NOT commit this session — `.git/index.lock` exists and is not
removable from the Cowork sandbox (permission-restricted on that mount), and a
stray `node_modules/` (from a babel syntax check) is similarly stuck there.
Nothing has been committed yet. Please stage, commit, and push from your side.

## Steps

1. From the repo root (`~/Claude/finance-tracker`), clear any stale locks first:
   ```
   rm -f .git/index.lock .git/HEAD.lock
   ```
2. Remove the leftover `node_modules/` (a temporary babel install used only to
   syntax-check app.html's JS — not part of the app, never should be committed):
   ```
   rm -rf node_modules package.json package-lock.json
   ```
3. Review the diff before staging:
   ```
   git status
   git diff --stat
   ```
   Expect changes in: `app.html`, `index.html`, `ios/Budget/Shared/Finance.swift`,
   `ios/Budget/Budget/WageView.swift`, `CLAUDE_CODE_PROMPT.md`. Xcode
   `xcuserdata`/`xcshareddata` noise can be ignored/staged as usual.
4. Stage and commit:
   ```
   git add app.html index.html ios/Budget/Shared/Finance.swift ios/Budget/Budget/WageView.swift CLAUDE_CODE_PROMPT.md
   git add ios/Budget/Budget.xcodeproj  # xcuserdata/xcshareddata noise, same as prior commits
   git commit -m "Add Estimated Pay to Wage tab (web + iOS)

Computes a rolling estimate for any month with no logged hours/override yet,
using the set weekly schedule (se.shifts) + Budget tab calendar (customDays)
+ paid leave (flat 7h/day). Live-computed every render from workDays/shifts/
customDays, so toggling a day on the Budget tab re-syncs the estimate
automatically — no cached/stale state. Follows the existing arrears
convention (month mk's estimate reflects prevMK's schedule, same as
wage/transport/paid-leave elsewhere on this tab). Flags scheduled work days
whose weekday has no shift time set, instead of silently showing 0h.
Estimate disappears once real hours or a payslip override are entered for
that month."
   ```
5. Push:
   ```
   git push origin main
   ```
6. After push, clear any leftover locks so the next session is smooth:
   ```
   rm -f .git/*.lock .git/refs/**/*.lock 2>/dev/null; true
   ```

## What's in this change
- **Web (app.html/index.html):** new `gEstHours`/`gEstPay` helpers near the
  existing `gWorkDaysCD`/`gWorkDays`. Wage tab now shows an "Estimated Pay"
  card (wage + transport breakdown) for any month with `hours===0` and
  `wageOverride===0`. Collapsed header shows `~¥X` instead of `—` for those
  months.
- **iOS (Finance.swift/WageView.swift):** mirrors the web logic exactly —
  `Calc.EstPay` struct + `estimatedPay(mk)` in Finance.swift, matching card
  UI in WageView.swift (blue card, same breakdown, same no-shift warning).
- **No new stored fields** — everything is derived live from
  `se.workDays`/`se.shifts`/`da[mk].customDays`, so there's nothing to keep
  in sync manually.

## After push — rebuild on your Mac and TEST on device
(No Xcode in Cowork, so the Swift is logic-reviewed and pattern-matched
against existing code only, not compiled.)
- Open Wage tab on a future month with no hours logged — should show blue
  "Estimated Pay" card with wage + transport breakdown.
- Go to Budget tab, flip a day from off → work (or vice versa) in that same
  month's arrears period, come back to Wage tab — estimate should update.
- Log real hours (or a payslip override) for a month — its Estimated Pay
  card should disappear and the real breakdown should show instead.
- If a scheduled work day's weekday has no shift time set in Settings, the
  card should show a ⚠ warning line instead of silently under-counting.
