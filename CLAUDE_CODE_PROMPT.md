# Claude Code — Push Prompt (2026-07-09) — Savings sync / keyboard Done / Face ID

Cowork committed some work locally (`e40eacc`, `dd7afce`) but a shared-`.git` lock
blocked the LAST batch, so four files are staged-but-uncommitted. Finish it:

1. From the repo root (`~/Claude/finance-tracker`), remove stale locks FIRST:
   ```
   rm -f .git/HEAD.lock .git/index.lock
   ```
2. Check state:
   ```
   git status
   git log --oneline -3
   ```
   You should see `dd7afce` and `e40eacc` already committed, plus these still modified:
   - ios/Budget/Budget/WageView.swift
   - ios/Budget/Budget/SavingsView.swift
   - ios/Budget/Budget/BudgetTabView.swift
   - ios/Budget/Budget/ContentView.swift
   - CLAUDE_CODE_PROMPT.md (this file)
3. Commit the remaining files:
   ```
   git add ios/Budget/Budget/WageView.swift ios/Budget/Budget/SavingsView.swift \
           ios/Budget/Budget/BudgetTabView.swift ios/Budget/Budget/ContentView.swift \
           CLAUDE_CODE_PROMPT.md
   git commit -m "Keyboard Done bar on every numeric screen; update push prompt"
   ```
4. Push:
   ```
   git push origin main
   ```
5. After push, clear any leftover locks so next session is smooth:
   ```
   rm -f .git/*.lock .git/refs/**/*.lock 2>/dev/null; true
   ```

## What all this contains
- **Savings sync (web + iOS):** Budget "not saving"/"not investing" toggle wins;
  opted-out months = ¥0. Fixes phantom ¥10,000 / ¥1,429 / ¥17,143.
- **Keyboard Done bar:** web got a global bar; iOS now applies `.keyboardDoneBar()`
  directly to every screen with numeric fields (Wage, Savings, Budget, Paidy, Limit,
  Goals, Settings). The old TabView-level toolbar didn't reach screens in their own
  NavigationStack — that's why many fields had no Done button.
- **Face ID:** 60-second grace period — only locks if backgrounded ≥60s.

## After push — BUILD & TEST on device (no Xcode in Cowork; Swift is static-reviewed only)
- Open EACH screen with a number field (Wage, Savings, Budget cards, Paidy add-plan,
  Limit, Goals, Settings) → tap a numeric field → confirm "Done" appears above the keypad
  and dismisses it. Paidy add-plan screen was the reported failure — verify it now works.
- Face ID: background <60s → no prompt; ≥60s → Face ID; cold launch → Face ID.
- Savings tab: an opted-out month shows "not saving" and no input; Total = ¥0.
