# Claude Code — Commit & Push Prompt (2026-07-15, updated)

Cowork could NOT commit this session — `.git/index.lock` exists and is not
removable from the Cowork sandbox (permission-restricted on that mount), and a
stray `node_modules/` (from a babel syntax check) is similarly stuck there.
Two separate pieces of work are staged and waiting: the Estimated Pay feature,
and a small payday-notification wording tweak made just after. Please stage,
commit, and push from your side.

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
   `ios/Budget/Budget/WageView.swift`, `ios/Budget/Budget/Notifications.swift`,
   `CLAUDE_CODE_PROMPT.md`. Xcode `xcuserdata`/`xcshareddata` noise can be
   ignored/staged as usual.
4. Stage and commit as TWO separate commits (cleaner history — these are
   unrelated changes):

   **Commit 1 — Estimated Pay feature:**
   ```
   git add app.html index.html ios/Budget/Shared/Finance.swift ios/Budget/Budget/WageView.swift
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

   **Commit 2 — Payday notification wording:**
   ```
   git add app.html index.html ios/Budget/Budget/Notifications.swift
   git commit -m "Payday notification: swap 'log your hours' for expense-check reminder

Web reminder banner and iOS push notification on payday now say
'check your fixed and one-off expenses' instead of 'log your hours'."
   ```

   **Then stage the prompt file itself and any Xcode noise:**
   ```
   git add CLAUDE_CODE_PROMPT.md
   git add ios/Budget/Budget.xcodeproj  # xcuserdata/xcshareddata noise, same as prior commits
   git commit -m "Update push prompt"
   ```
5. Push:
   ```
   git push origin main
   ```
6. After push, clear any leftover locks so the next session is smooth:
   ```
   rm -f .git/*.lock .git/refs/**/*.lock 2>/dev/null; true
   ```

## What's in these changes
- **Estimated Pay (web + iOS):** new `gEstHours`/`gEstPay` (web) and
  `Calc.EstPay`/`estimatedPay` (iOS). Wage tab shows an "Estimated Pay" card
  (wage + transport breakdown) for any month with `hours===0` and
  `wageOverride===0`. No new stored fields — everything derives live from
  `se.workDays`/`se.shifts`/`da[mk].customDays`.
- **Payday notification wording (web + iOS):** the payday-today
  reminder/notification no longer says "log your hours" — it now says
  "check your fixed and one-off expenses!" Web: `app.html`/`index.html` line
  ~482 (`reminders` array). iOS: `Notifications.swift` line ~95 (scheduled
  local push, title unchanged "💰 Pay Day!").

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
- Payday notification: on payday, confirm the push says "Today is your
  payday! Check your fixed and one-off expenses!" (no mention of hours).
  Web Wage tab banner should read "Payday is today — check your fixed and
  one-off expenses!"
