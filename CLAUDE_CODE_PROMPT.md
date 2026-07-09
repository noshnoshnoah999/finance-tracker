# Claude Code — Push Prompt (2026-07-09) — Savings sync / keyboard / Face ID

The Cowork session already committed locally (`e40eacc`). It could NOT delete two stale
git lock files due to a sandbox permission quirk. Do this:

1. From the repo root (`~/Claude/finance-tracker`), remove any stale locks first:
   ```
   rm -f .git/HEAD.lock .git/index.lock
   ```
2. Confirm the working tree is clean and the commit is there:
   ```
   git status
   git log --oneline -1        # expect e40eacc (or later) — savings sync / keyboard / face id
   ```
3. Push:
   ```
   git push origin main
   ```
4. After the push completes, clean up any stale/leftover lock files again so the next
   session starts smoothly:
   ```
   rm -f .git/*.lock .git/refs/**/*.lock 2>/dev/null; true
   ```

## What this commit contains
- Savings tab now respects the Budget "not saving"/"not investing" toggle (web + iOS):
  opted-out months contribute ¥0; fixes the phantom ¥10,000 / ¥1,429 / ¥17,143.
- Web: new keyboard "Done" bar for numeric inputs (iOS already had one).
- iOS: 60-second Face ID grace period — only locks if backgrounded ≥60s.

## After push — please build & test on device (not done in Cowork; no Xcode there)
- Face ID: background <60s → reopen with no prompt; background ≥60s → Face ID required;
  cold launch → Face ID required.
- Savings tab: a "not saving" month shows the pill + note and no input, Total = ¥0.
- Web keyboard bar: on a real iPhone, focus an amount field → "Done" appears above the
  keyboard and dismisses it.
