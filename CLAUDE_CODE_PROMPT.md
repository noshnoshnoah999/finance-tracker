# Claude Code — Commit & Push Prompt (2026-07-15, Estimated Pay fixes)

New Cowork session, new uncommitted work — the Limit-chat feature from the
previous prompt is already committed (`4f932ee` etc.), that's done. This is a
follow-up fixing bugs in the Estimated Pay feature (from `e06708d`) that
Noah spotted after using it. Cowork could NOT commit — `.git/index.lock`
exists and isn't removable from the Cowork sandbox (permission-restricted on
that mount), and a stray `node_modules/` (temporary babel syntax-check
install) is stuck there too.

## Steps

1. From the repo root (`~/Claude/finance-tracker`), clear any stale lock first:
   ```
   rm -f .git/index.lock .git/HEAD.lock
   ```
2. Remove the leftover `node_modules/` (temporary babel install used only to
   syntax-check app.html's JS — never part of the app, don't commit it):
   ```
   rm -rf node_modules package.json package-lock.json
   ```
3. Review the diff before staging:
   ```
   git status
   git diff --stat
   ```
   Expect changes in exactly: `app.html`, `index.html`,
   `ios/Budget/Budget/WageView.swift`, `ios/Budget/Budget/BudgetTabView.swift`.
   Also an untracked `HANDOFF_2026-07-15_limit-chat.md` from the prior
   session — stage that too, it's a real handoff doc, not scratch.
4. Stage and commit:
   ```
   git add app.html index.html ios/Budget/Budget/WageView.swift ios/Budget/Budget/BudgetTabView.swift HANDOFF_2026-07-15_limit-chat.md CLAUDE_CODE_PROMPT.md
   git commit -m "Fix Estimated Pay: remove duplicate card, add Budget tab line

Noah reported 3 issues after using the new Estimated Pay feature:

1. Wage tab collapsed row didn't say 'Estimated Pay', just showed a number.
2. Number shown looked like transport-only, not wage+transport.
3. Budget tab (Income card) didn't show any estimate at all.

Root causes:
- #1/#2 were actually a stale cache on Noah's device — the committed code
  already computed the full wage+transport total correctly (confirmed via
  his screenshot: the new Estimated Pay card itself showed the right
  numbers, ¥72,800 wage + ¥11,000 transport = ¥83,800, but the OLD
  always-on 'Wage/Transport/Total Pay' breakdown card was ALSO still
  rendering underneath it, showing the real ¥0 wage + real ¥11,000
  transport — which is what his screenshot of the collapsed row/header
  actually reflected before a fresh reload picked up the new card).
- The real bug: that old breakdown card (Wage/Transport/Total Pay +
  Commute/Taxable) was never hidden when the new Estimated Pay card
  appears, so both showed at once for unlogged months — confusing.
- #3: Budget tab's Income card was never touched by the original Estimated
  Pay work — it only ever showed real wage (¥0 until hours logged).

Fixes (web + iOS):
- Wage tab: old Wage/Transport/Total Pay + Commute/Taxable cards now hidden
  (!showEst) whenever the Estimated Pay card is showing. Collapsed header
  now explicitly labeled 'Estimated Pay' next to the total instead of just
  a '~' prefix.
- Budget tab (Income card): new 'Estimated Pay (if hours match schedule)'
  line, shown only when wage=0 and no override — DISPLAY ONLY, confirmed
  with Noah not to feed into Free to Spend or any real total, so actual
  budget math stays untouched until real hours are logged.
- All estimate displays still disappear immediately once real hours or a
  payslip override are entered for that month (confirmed this is correct,
  intentional behavior, not a bug)."
   ```
5. Push:
   ```
   git push origin main
   ```
6. After push, clear any leftover locks so the next session is smooth:
   ```
   rm -f .git/*.lock .git/refs/**/*.lock 2>/dev/null; true
   ```

## After push — rebuild on your Mac and TEST on device
(No Xcode in Cowork, so the Swift is logic-reviewed and brace/paren-balance
checked only, not compiled.)

- **Web:** hard-refresh (Cmd+Shift+R) or reopen the tab first — the
  duplicate-card bug may partly have been a stale load. Open Wage tab on a
  future unlogged month: should see ONE blue "Estimated Pay" card only (no
  second beige Wage/Transport card underneath). Collapsed row should read
  "Estimated Pay ¥83,800" (or similar) not just a bare number.
- **iOS:** rebuild fresh install (or force-quit + reopen) since native apps
  don't have a browser-cache equivalent, but the two cards need the new
  `!showEst` gate compiled in. Same check: only the blue estimate card shows
  for unlogged months.
- **Budget tab (both):** select a future unlogged month — Income card should
  show "Wage ¥0" then a blue "Estimated Pay (if hours match schedule)
  ~¥72,800" line right below it, then Transport Received as before. "Free to
  Spend" at the bottom should be unaffected by this line (still based on
  real ¥0 wage).
- Log real hours for that month — everywhere the estimate showed, it should
  disappear and the real breakdown should take over (confirm this still
  works correctly, it's existing `showEst`/`hD` gating logic, unchanged).
