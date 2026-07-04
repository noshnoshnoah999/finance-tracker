# Claude Code — push prompt (2026-07-04)

A commit was made in Cowork but **not pushed** (the sandbox shares this repo's
`.git`, so pushing is left to you to avoid lock collisions).

## Do this
1. Confirm the working tree is clean and the latest commit is the one below:

   ```bash
   git status
   git log --oneline -1
   ```

   Expected HEAD:
   `e539c40  Limit simulator + Home nav fixes (web + iOS)`

2. If that is HEAD and the tree is clean, push:

   ```bash
   git push
   ```

3. If `git status` shows a lock file (`.git/index.lock` or `HEAD.lock`) left
   over from the sandbox, remove it first, then retry:

   ```bash
   rm -f .git/index.lock .git/HEAD.lock
   git push
   ```

## What's in the commit
Fixes to the Limit-tab shift simulator and Home navigation, in both the web
app (`app.html` / `index.html`) and the native iOS app (`ios/Budget/…`):
- Breaks only deducted for shifts **longer than 3h** (a 3h shift no longer drops to 2h).
- Shift simulator has a **month picker** (defaults to current month) instead of
  silently planning next month.
- iOS Home cards **Wages → / Budget → / Limit →** now navigate.

## Before shipping the iOS build
Open in Xcode and build — these Swift changes were **not** compiled in Cowork.
Tap-test: the three Home cards, and the new "Planning for" month picker in
Limit → "Can I work these shifts?".
