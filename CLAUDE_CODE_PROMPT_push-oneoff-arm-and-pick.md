# Push prompt for Claude Code — "+ One-off" arm-then-pick rework

Paste everything below into Claude Code running against
`/Users/noahflouty/Claude/finance-tracker`.

---

A Cowork session has already committed this work as `8b73421` ("Rework "+ One-off"
into arm-then-pick so an existing shift can actually be edited"). Do not redo it,
do not amend it. Your job is to push it and rebuild the native app. Steps:

1. `git log --oneline -3` and confirm `8b73421` is at the tip of `main`. Then
   `git log origin/main..HEAD --oneline` — if that is empty it is already pushed,
   so skip to step 4.
2. `git status` — the only expected local modification is
   `ios/Budget/Budget.xcodeproj/project.xcworkspace/xcuserdata/*/UserInterfaceState.xcuserstate`
   (Xcode window state — never commit it) and an untracked `_to_delete/`
   directory (git lock leftovers — safe to delete).
3. `git push` to `origin main`, then confirm the web app redeploys.
4. **Rebuild the native app** — the Cowork sandbox has no Swift toolchain, so
   `ios/Budget/Budget/BudgetTabView.swift` was written and hand-checked but never
   compiled. Run `./reinstall_budget.sh` (or open
   `ios/Budget/Budget.xcodeproj` and build). If it fails to compile, the new code
   is all in `BudgetTabView.swift`:
   - new `@State private var oosPick`
   - the `Button(oosPick ? "Pick a day…" : "+ One-off")` in the Work Schedule header
   - the `if oosPick { … }` first line of `tapDay`
   - `dsLabel` / `monthFull` and the rewritten `oneOffShiftBox` (its `DatePicker`,
     `dsToDate` and `dateToDs` were deleted — make sure nothing still references them)
   Report the exact compiler error rather than guessing at a fix.
5. Sanity-check the feature once built, on Sunday 6 September:
   click "+ One-off" (it should turn green and read "Pick a day…"), then click
   the 6th. The editor must open showing "Sunday 6 September" with 10:30 and
   17:00 already filled in — not blank. Change the end to 14:00, Save, and
   confirm the Wage tab / next-paycheck estimate drops by 3 hours of pay.
6. **Before finishing**, clear any stale git locks so the next session starts
   clean — `.git/index.lock`, `.git/HEAD.lock`, `.git/objects/maintenance.lock`
   and any `.git/objects/**/tmp_obj_*`. Only remove them if no git process is
   running (`ps aux | grep git`). They are artifacts of the Cowork sandbox and
   your local terminal sharing one `.git`, not a real problem, but left behind
   they block whichever environment runs `git` next. The `_to_delete/` folder
   in the repo root holds ones already moved aside — it can be deleted entirely.

Nothing else needs changing.
