# Claude Code prompt — push the "Requested?" + auto-FX work

Paste the block below into Claude Code, run from `~/Claude/finance-tracker`.

---

Work in `~/Claude/finance-tracker`.

There is one commit already made in this repo that has **not** been pushed:

- `5a807ca` — *Dad's Contributions: replace Free? with a per-month Requested? tracker; auto-refresh GBP to JPY daily*

It changes `app.html`, `index.html`, and six Swift files under `ios/Budget/`. Full detail is in
`HANDOFF_2026-08-28_requested-and-auto-fx.md`.

Please do the following, in order, and stop and tell me if any step looks wrong rather than
forcing past it:

1. **Clear stale locks first.** A previous session ran git from a sandbox that cannot delete
   files, so `.git/index.lock`, `.git/HEAD.lock` and `.git/objects/maintenance.lock` may be
   present with no git process running. Confirm no git process is actually running
   (`ps aux | grep -i git`), then remove any stale `.git/*.lock` and
   `.git/objects/**/tmp_obj_*` files.

2. **Delete the `_to_delete/` folder** at the repo root. It holds two stale `index.lock` copies
   that the sandbox could not remove. It is untracked — just delete it.

3. `git status` and `git log --oneline -3` — show me the state before you touch anything.

4. **Commit the two new docs** if they are not already in: `HANDOFF_2026-08-28_requested-and-auto-fx.md`
   and `CLAUDE_CODE_PROMPT_push-requested-and-auto-fx.md`. Message:
   `Add handoff and push prompt for Requested? tracker and auto-refreshing FX rate`
   Leave `ios/Budget/Budget.xcodeproj/.../UserInterfaceState.xcuserstate` **uncommitted** — it is
   Xcode window state, not code.

5. **Build the iOS/macOS target in Xcode before pushing.** The Swift changes were written in a
   Linux sandbox with no Swift toolchain, so they have never been compiled. Build both the iOS
   and Mac Catalyst destinations. Files touched:
   `ios/Budget/Shared/Finance.swift`, `ios/Budget/Budget/BudgetStore.swift`,
   `ios/Budget/Budget/BudgetTabView.swift`, `ios/Budget/Budget/ContentView.swift`,
   `ios/Budget/Budget/SettingsView.swift`, `ios/Budget/Budget/BudgetApp.swift`.
   If it fails to compile, fix it, commit the fix, and tell me what was wrong. Do not push a
   build-broken tree.

6. `git push origin main` (check the branch name first — do not assume).

7. Confirm the GitHub Pages deploy kicked off, and tell me the pushed commit SHAs.

8. **Clean up afterwards so next time is smoother:** remove any lock files git left behind
   (`.git/index.lock`, `.git/HEAD.lock`, `.git/objects/maintenance.lock`, any
   `.git/objects/**/tmp_obj_*`, `.git/refs/**/*.lock`), and confirm `git status` runs clean with
   no stale locks remaining.

## What to sanity-check in the running app after the deploy

- Budget tab → Dad's Contributions shows `Requested?` on all six rows, no `Free?` anywhere.
- Tapping `Requested?` changes **no number** on the page.
- Marking items in one month and switching months: the other month is unmarked, and going back
  keeps the marks.
- Settings → Exchange Rate: the rate updates on its own when you open the app on a new day. The
  `Live rate` button still forces a refresh, and the number is still hand-editable.
- Income card no longer has a `Dad (free spend)` row, and Home's Left-to-Spend no longer has a
  `From Dad` row. **Income and Free to Spend will be lower than before** for any month that had
  Free-marked items — that is the intended change, not a bug.
