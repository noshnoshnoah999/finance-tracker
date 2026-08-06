# Claude Code prompt — commit & push flexible Work Schedule

Copy everything in the fenced block below into Claude Code, run from
`/Users/noahflouty/Claude/finance-tracker`.

**Why this is needed:** the Cowork sandbox could not write to the shared `.git` directory, so
nothing has been committed yet. A stale `.git/index.lock` was left behind and must be cleared
first. All source edits are already on disk and tested.

---

```
Work in /Users/noahflouty/Claude/finance-tracker.

STEP 0 — CLEAR THE STALE LOCK FIRST.
A Cowork session left a stale lock behind. Before any git command:

  1. Confirm no real git process is running:  ps aux | grep -i "[g]it"
  2. Only if that returns nothing, remove the stale files:
       rm -f .git/index.lock
       rm -f .git/objects/5c/tmp_obj_H91JJF
  3. Sanity check the repo:  git status && git fsck --no-progress --no-dangling

Do NOT delete any lock while a real git process is running.

STEP 1 — VERIFY BEFORE COMMITTING.
  git status
  git diff --stat

Expect exactly these modified files (plus the two new .md files, untracked):
  app.html
  index.html
  ios/Budget/Shared/Models.swift
  ios/Budget/Shared/Finance.swift
  ios/Budget/Budget/BudgetStore.swift
  ios/Budget/Budget/SettingsView.swift
  HANDOFF_2026-08-06_flexible-shifts.md            (new)
  CLAUDE_CODE_PROMPT_push-flexible-shifts.md       (new)
  test_backfill.js                                 (new, regression test)
  test_live_source.js                              (new, regression test)

Run the regression tests before committing — test_live_source.js reads app.html directly,
so it will fail if the source drifted:
  node test_backfill.js && node test_live_source.js
Both must print PASS. If either fails, STOP and report.

Ignore ios/Budget/Budget.xcodeproj/.../UserInterfaceState.xcuserstate — that is Xcode UI
state, do not commit it. If it is already tracked, leave it out of these commits.

Assert app.html and index.html are identical; the change requires it:
  diff app.html index.html && echo "PARITY OK"
If that prints anything other than "PARITY OK", STOP and report.

STEP 2 — BUILD THE NATIVE APP.
Swift was never compiled (the Cowork sandbox has no swiftc), so this is the first real check:

  xcodebuild -project ios/Budget/Budget.xcodeproj -scheme Budget \
    -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -40

If it fails, fix the compile errors before committing. The new native code is:
  - Models.swift: DOW_LABELS / DOW_FULL / DOW_ORDER globals
  - Finance.swift: shifts(_:) now unions base keys with shiftOverrides keys
  - BudgetStore.swift: freezeDOW(_:_:), removeShift(_:), addShift(_:)
  - SettingsView.swift: dynamic schedule card, @State newShiftDow / pendingRemove,
    delete button + confirmation alert, add-day Picker, Weekly total row

STEP 3 — COMMIT IN TWO COMMITS.

Commit A (the parity fix, kept separate so it can be reverted independently):
  git add index.html
  git commit -m "Port Amazon (Subscribe & Save) Dad's Contributions line into index.html

index.html was missing the Amazon line and updated Total row that app.html
received in 13b3740, leaving the two web builds out of sync."

Careful: index.html also contains the schedule change. If splitting cleanly is awkward,
skip Commit A and fold everything into Commit B with both points in the message. Do not
spend long on it.

Commit B:
  git add app.html index.html ios/Budget/Shared/Models.swift ios/Budget/Shared/Finance.swift \
          ios/Budget/Budget/BudgetStore.swift ios/Budget/Budget/SettingsView.swift \
          HANDOFF_2026-08-06_flexible-shifts.md CLAUDE_CODE_PROMPT_push-flexible-shifts.md \
          test_backfill.js test_live_source.js
  git commit -m "Make Work Schedule flexible: add and remove shift days (web + iOS)

The Work Schedule card hardcoded Mon/Tue/Sun in both UIs. Shift days are now
added and removed freely, and se.workDays is kept in lockstep with the shift
list so the calendar, transport cost and pay estimate follow automatically.

Removing or adding a day would otherwise rewrite history, because getDayState
resolves customDays then PAID_LEAVE then workDays: a past day that was 'work'
only via workDays membership flips the moment that membership changes. New
freezeDOW pins every past date of the affected weekday (through today) to its
current state before workDays is touched, skipping explicit customDays entries
and PAID_LEAVE dates. Removal also copies the shift into that month's
shiftOverrides so pinned days keep crediting hours, and gShifts / Calc.shifts
now union base and override keys so a removed day still resolves for past
months.

Verified: no date on or before today changes state or credited hours; future
months drop the day with no 'no shift time set' warnings.

Also de-hardcodes the Budget tab per-month shift editor, and ports the Amazon
(Subscribe & Save) line into index.html so the two web builds match."

STEP 4 — PUSH.
  git push origin HEAD

STEP 5 — CLEAN UP LOCKS AND STALE STATE.
After the push completes, leave the repo clean for next time:
  rm -f .git/index.lock .git/*.lock .git/refs/heads/*.lock 2>/dev/null
  find .git/objects -name 'tmp_obj_*' -delete 2>/dev/null
  git gc --prune=now --quiet
  git status

Report back: commit SHAs, push result, xcodebuild result, and anything you had to change.
```
