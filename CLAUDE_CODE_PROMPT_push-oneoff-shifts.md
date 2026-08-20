# Claude Code prompt — commit & push one-off shift feature

Copy everything in the fenced block below into Claude Code, run from
`/Users/noahflouty/Claude/finance-tracker`.

**Why this is needed:** the Cowork sandbox must not run mutating git commands against this
shared repo (see the `git-shared-repo-collision` project memory — a prior session already hit
a stale-lock problem here). All source edits are already written to disk and tested; nothing
has been committed yet.

---

```
Work in /Users/noahflouty/Claude/finance-tracker.

STEP 0 — CLEAR ANY STALE LOCK FIRST.
A Cowork session may have left a stale lock behind (a git status call from that sandbox
logged "unable to unlink .git/index.lock: Operation not permitted"). Before any git command:

  1. Confirm no real git process is running:  ps aux | grep -i "[g]it"
  2. Only if that returns nothing, remove any stale lock files:
       rm -f .git/index.lock
       find .git/objects -name 'tmp_obj_*' -delete 2>/dev/null
  3. Sanity check the repo:  git status && git fsck --no-progress --no-dangling

Do NOT delete any lock while a real git process is running.

STEP 1 — VERIFY BEFORE COMMITTING.
  git status
  git diff --stat

Expect exactly these modified files (plus two new .md files and two new test .js files,
untracked):
  app.html
  index.html
  ios/Budget/Shared/Finance.swift
  ios/Budget/Budget/BudgetStore.swift
  ios/Budget/Budget/BudgetTabView.swift
  HANDOFF_2026-08-20_oneoff-shifts.md              (new)
  CLAUDE_CODE_PROMPT_push-oneoff-shifts.md         (new)
  test_oneoff_shifts.js                            (new, regression test)

Ignore ios/Budget/Budget.xcodeproj/.../UserInterfaceState.xcuserstate — that is Xcode UI
state, do not commit it. If it is already tracked, leave it out of this commit.

Run the regression tests before committing — test_oneoff_shifts.js reads app.html directly,
so it will fail if the source drifted. Also re-run the existing flexible-shifts test to
confirm this change didn't disturb that machinery:
  node test_oneoff_shifts.js && node test_live_source.js
Both must print PASS. If either fails, STOP and report.

Assert app.html and index.html are identical; the change requires it:
  diff app.html index.html && echo "PARITY OK"
If that prints anything other than "PARITY OK", STOP and report.

STEP 2 — BUILD THE NATIVE APP.
Swift was never compiled in the Cowork sandbox (no swiftc there), so this is the first real
check. The new/changed native code is:
  - Finance.swift: estHours(_:_:) now checks oneOffShifts for the exact date before falling
    back to the weekday shift lookup; new public Calc.weekday(_:_:_:) wrapper around the
    previously-private jsDay
  - BudgetStore.swift: needsOneOffShiftPrompt, oneOffShift, hasOneOffShift, saveOneOffShift,
    removeOneOffShift — toggleDay itself is UNCHANGED
  - BudgetTabView.swift: new @State (oosEditDS, oosStart, oosEnd, oosBreak), oneOffShiftBox
    view, tapDay handler (replaces the direct store.toggleDay call in dayCell's Button),
    "1×" tag on calendar cells with a saved one-off shift

  xcodebuild -project ios/Budget/Budget.xcodeproj -scheme Budget \
    -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -40

If it fails, fix the compile errors before committing. Most likely snags, check these first:
  - Calc.weekday(_:_:_:) is a new public method — confirm it resolves where BudgetStore calls
    c.weekday(y, mo, d) (previously that code incorrectly called a private jsDay directly,
    which would not compile — the fix routes through the new public wrapper instead)
  - JSONValue.s(_:)/.d(_:) optional-chaining in BudgetTabView.tapDay: `sh?.s("start") ?? ""`
    where sh is JSONValue? — this pattern already exists elsewhere (SettingsView.swift's
    sh?.s("label")), so it should be familiar, but double-check it compiles here too
  - FieldStyle (defined in WageView.swift, used un-prefixed) is referenced in the new
    oneOffShiftBox view in BudgetTabView.swift

STEP 3 — TEST THE FEATURE IN THE SIMULATOR (if the build succeeds).
On the Budget tab, tap a date that isn't Monday or Sunday (or whatever the current weekly
schedule is) and currently shows no shift — confirm the "Choose the hours and break duration
for the shift on [date]" box appears, that saving it shows a "1×" tag on that date, and that
the Wage tab's Estimated Pay card for the following month reflects the added hours (not just
a transport-only bump). Re-tap the same date to confirm it reopens pre-filled for editing,
and that "Remove shift" clears it back to a blank day.

STEP 4 — COMMIT.
  git add app.html index.html ios/Budget/Shared/Finance.swift \
          ios/Budget/Budget/BudgetStore.swift ios/Budget/Budget/BudgetTabView.swift \
          HANDOFF_2026-08-20_oneoff-shifts.md CLAUDE_CODE_PROMPT_push-oneoff-shifts.md \
          test_oneoff_shifts.js
  git commit -m "Add one-off shifts for dates outside the weekly schedule (web + iOS)

Noah occasionally picks up shifts on days that aren't part of his regular
Mon/Sun schedule (e.g. a one-off Tuesday). Previously the Budget-tab calendar
had no way to record that specific date's hours: marking it 'work' fell back
to that weekday's shift, which didn't exist, so gEstHours/Calc.estHours
credited 0 hours while still charging a transport day for it — the exact bug
Noah hit in September, where a one-off shift only added the ¥1,100 transport
reimbursement to October's estimate.

New oneOffShifts structure, keyed by exact date inside each month's data
(separate from se.workDays/se.shifts and the existing per-weekday
shiftOverrides/freezeDOW machinery — neither is touched). Tapping a
non-schedule date on the Budget-tab calendar now opens a box pinned above the
grid: 'Choose the hours and break duration for the shift on [date]'. Saving
writes both customDays[date]='work' and oneOffShifts[date]={start,end,
breakMin}. Re-tapping a date that already has one reopens it for editing
instead of cycling past it (which would strand the entry); a Remove button
clears both together.

gEstHours/Calc.estHours check the exact date before falling back to the
weekday lookup — the single choke point all Estimated Pay consumers share
(homepage next-paycheck card, Wage tab, Budget-tab totals, AI advice prompt),
so the fix propagates everywhere automatically on both platforms.

Verified against the real shipped source (extracted from app.html/index.html
and executed, not transcribed): the exact September bug reproduces pre-fix
and resolves post-fix — 0h/transport-only becomes hours × hourlyWage credited
correctly, with noShiftDays dropping to 0 and transport unaffected. Existing
flexible-shifts/freezeDOW regression suite (31 checks) still passes
unchanged. app.html and index.html confirmed byte-identical."

STEP 5 — PUSH.
  git push origin HEAD

STEP 6 — CLEAN UP LOCKS AND STALE STATE.
After the push completes, leave the repo clean for next time:
  rm -f .git/index.lock .git/*.lock .git/refs/heads/*.lock 2>/dev/null
  find .git/objects -name 'tmp_obj_*' -delete 2>/dev/null
  git gc --prune=now --quiet
  git status

Report back: commit SHA, push result, xcodebuild result, simulator test result, and anything
you had to change.
```
