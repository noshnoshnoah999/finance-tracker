# Push prompt for Claude Code

Copy everything below into Claude Code (running locally against
`/Users/noahflouty/Claude/finance-tracker` or wherever your local clone lives).

---

A Cowork session committed a change to this repo already (commit `f3005f7`,
"Add "+ One-off" button to override a single date's shift on an
already-scheduled weekday"). Your job is just to push it — do not re-do the
work, do not amend the commit, do not re-run the diff logic. Steps:

1. `cd` into the repo and run `git log --oneline -5` to confirm `f3005f7` is
   present as the tip of `main` (or already merged/pushed if someone beat you
   to it — check `git log origin/main..HEAD` first; if it's empty, stop, it's
   already pushed).
2. Run `git status` and confirm there are no unexpected local modifications
   beyond the usual Xcode `ios/Budget/Budget.xcodeproj/project.xcworkspace/xcuserdata/*/UserInterfaceState.xcuserstate`
   noise (that file is IDE window state, never commit it, never worry about it).
3. `git push` to `origin main`.
4. **Before you finish**, remove any stale `.git` lock files this repo may
   have accumulated, so the next session (Cowork or local) starts clean:
   - `.git/index.lock`
   - `.git/HEAD.lock`
   - `.git/objects/maintenance.lock`
   - any `.git/objects/**/tmp_obj_*` leftovers
   Only remove these if they exist and no git process is currently running
   (check with `ps aux | grep git`) — they're artifacts of this
   sandbox/local-terminal sharing the same `.git` directory, not signs of a
   real problem, but they block the next `git` command in whichever
   environment hits them first if left behind.
5. If the iOS side hasn't been opened in Xcode since this change, open
   `ios/Budget/Budget.xcodeproj` and build once — the Cowork session that
   wrote `BudgetTabView.swift` could not compile Swift (no toolchain in that
   sandbox) and only checked it by hand (brace balance + cross-referencing
   existing types). Report back if it fails to build; the relevant new code
   is the "+ One-off" button and `oneOffShiftBox` changes near the top of
   the "Work Schedule" section of `BudgetTabView.swift`.

That's it — no other changes needed.
