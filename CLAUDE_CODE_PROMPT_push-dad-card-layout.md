# Claude Code prompt — push the Dad card layout fix

Work in `~/Claude/finance-tracker`.

Two new commits are waiting to be pushed. They change `app.html`, `index.html`,
`ios/Budget/Budget/BudgetTabView.swift`, and append sections to
`HANDOFF_2026-08-28_requested-and-auto-fx.md`.

What they do, all in the Dad's Contributions card:
- Remove the description text under the title on iOS/macOS (web never had one).
- Move each item's name onto its own line so it can't be clipped at phone width. The
  `£ / ¥ / Requested? / Edit / ×` controls sit on the line below.
- Give the Amazon (Subscribe & Save) line its own `Requested?` button. It is a derived
  aggregate with no item id, so it uses the fixed key `"amazon"` in the same per-month
  `dadRequested` map.
- Add a "Left to Request" row under Total: the £ still to ask Dad for this month (every
  unmarked item plus the unmarked Amazon line's £ equivalent). Display only, £ not yen.

Please do the following, in order, and stop and tell me if anything looks wrong:

1. **Clear stale locks first.** Check `ps aux | grep -i git` shows no real git process, then
   remove any `.git/*.lock`, `.git/refs/**/*.lock` and `.git/objects/**/tmp_obj_*`. Delete the
   `_to_delete/` folder at the repo root if it has reappeared.
2. `git status` and `git log --oneline -3` — show me the state before touching anything.
3. **Build the iOS and Mac Catalyst targets in Xcode before pushing.** The Swift was written in a
   Linux sandbox with no Swift toolchain, so it has never been compiled. Only
   `ios/Budget/Budget/BudgetTabView.swift` changed — the `dadCard` function. Last time a deleted
   local left a dangling reference, so watch for that class of error. If it fails, fix it, commit
   the fix, and tell me what was wrong. Do not push a build-broken tree.
4. `git push origin main` (check the branch name, don't assume).
5. Confirm the GitHub Pages deploy ran, and give me the pushed commit SHAs.
6. **Clean up afterwards so next time is smoother:** remove any lock files git left behind
   (`.git/index.lock`, `.git/HEAD.lock`, `.git/objects/maintenance.lock`, any
   `.git/objects/**/tmp_obj_*`, `.git/refs/**/*.lock`) and confirm `git status` runs clean with no
   stale locks remaining.

## What to check in the app after deploy

- Dad's Contributions has no description paragraph under the title.
- On a phone-width screen every item name shows in full — `Commuter pass` and
  `Japanese lessons` in particular, which were previously cut off.
- The card doesn't scroll sideways.
- The Amazon line has a `Requested?` button, and marking it is remembered per month.
- "Left to Request" sits under Total, shows £ only, drops as you mark things, and reads
  £0.00 in green once everything is marked.
- Tapping `Requested?` still changes no number anywhere except "Left to Request".
