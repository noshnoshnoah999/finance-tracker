# Claude Code Prompt — Push the Estimated Pay view fix

## What already happened
Cowork committed the fix for the Wage tab hiding "Estimated Pay" behind a transport-only total. The commit is already made locally:

- Commit: `1c2f955` — "Fix Wage tab hiding Estimated Pay behind transport-only total (iOS)"
- One file changed: `ios/Budget/Budget/WageView.swift` (8 insertions, 4 deletions)
- iOS-only by design: the web app already branched on `hD` not `total`, so it never had this bug and needs no change.

## Your task

1. Confirm state before pushing:
   ```
   git -C . status --short
   git -C . log --oneline -3
   ```
   You should see `1c2f955` on top of `b1f69c3`. The three untracked `.md` files (HANDOFF_* and CLAUDE_CODE_PROMPT_* including this one) are fine — do NOT commit them unless Noah asks.

2. Push to `main`:
   ```
   git -C . push origin main
   ```

3. **Clear any stale git locks** afterward so the next session runs cleanly (the Cowork sandbox shares this `.git` and can leave locks it can't delete):
   ```
   rm -f .git/index.lock .git/HEAD.lock .git/objects/maintenance.lock
   find .git -name '*.lock' -delete
   ```

4. Confirm the push succeeded (`git -C . status` shows "up to date with origin/main") and report back to Noah.

## Rules
- Safety & security first. Do not touch or print any secrets/keys.
- Do NOT modify code in this pass — this is push + lock cleanup only.
- If the push is rejected (remote has commits you don't have), STOP and report — do not force-push. Noah will decide.
- Report what you did and the final `git status` when done.
