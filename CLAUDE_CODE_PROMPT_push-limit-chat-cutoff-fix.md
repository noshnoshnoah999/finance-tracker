# Claude Code Prompt — Push Limit chat cut-off fix

Please run the following in the `finance-tracker` repo:

1. Confirm the working tree and the latest commit:
   ```
   git status
   git log --oneline -3
   ```
   You should see commit `d05cea5` — "Fix Limit chat reply being cut off on iOS/macOS". If it's already pushed, stop and tell me.

2. Push to the remote:
   ```
   git push origin main
   ```

3. **After pushing, remove any stale git locks so the next session is smoother:**
   ```
   rm -f .git/*.lock .git/objects/maintenance.lock 2>/dev/null
   find .git/objects -name 'tmp_obj_*' -delete 2>/dev/null
   git status
   ```
   (These locks/temp files can linger because the sandbox and local terminal share the same `.git`.)

4. Confirm the push landed:
   ```
   git log origin/main --oneline -1
   ```

## Context
- Single-file change: `ios/Budget/Budget/LimitView.swift`.
- Wrapped the Limit-page follow-up chat message list in a `ScrollView` inside the existing `maxHeight: 320` frame. Long Claude replies were being clipped because the `VStack` had a hard height cap with no scroll.
- macOS is Mac Catalyst (same target, same file) — one fix covers iOS and macOS.
- Web (`app.html` / `index.html`) already had `maxHeight:320 + overflowY:auto`, so no web change was needed. Parity is preserved.
