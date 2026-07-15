# Claude Code — Commit, Build & Push Prompt (2026-07-15, Free to Spend + rebuild)

New Cowork session, new uncommitted work on top of `5e371f4` (chat truncation
fix, already committed/pushed). Two things happened:

1. Noah reversed an earlier decision: the Budget tab's "Estimated Pay" line
   should now feed into Free to Spend / Total for unlogged months (not just
   be a display-only line like before).
2. Noah reported the Wage tab card-duplication fix from `8bc0a70` still
   wasn't showing — turns out he's testing on the **native iOS/macOS app**,
   which needs an actual Xcode rebuild to pick up Swift changes (no
   hot-reload). That fix is correctly in the code, it just was never built
   onto his device. **This prompt's build/reinstall step is not optional —
   it's the actual fix for that half of his report.**

Cowork could NOT commit — `.git/index.lock` exists and isn't removable from
the Cowork sandbox (permission-restricted on that mount). There's also a
stray `node_modules/` in the repo root (temporary babel syntax-check
install) that couldn't be removed for the same reason — please delete it.

## Steps

1. From the repo root (`~/Claude/finance-tracker`), clear the stale lock:
   ```
   rm -f .git/index.lock .git/HEAD.lock
   ```
2. Remove the leftover `node_modules/` (not part of the app):
   ```
   rm -rf node_modules package.json package-lock.json
   ```
3. Review the diff:
   ```
   git status
   git diff --stat
   ```
   Expect exactly: `app.html`, `index.html`, `ios/Budget/Shared/Finance.swift`,
   `ios/Budget/Budget/BudgetTabView.swift`.

4. Commit:
   ```
   git add app.html index.html ios/Budget/Shared/Finance.swift ios/Budget/Budget/BudgetTabView.swift CLAUDE_CODE_PROMPT.md
   git commit -m "Estimated Pay now feeds Free to Spend / Budget Total for unlogged months

Reverses the earlier 'display-only' decision (8bc0a70) after Noah saw it in
practice and wanted the projection to actually count toward his budget
planning, not just be informational.

Web (app.html/index.html): new bdEstForTotals — when this month's wage is
¥0 and there's no payslip override, bdI (Budget tab income total) swaps in
gEstPay(bm).wage instead of the real ¥0. bdFr (Free to Spend) inherits this
automatically since it's derived from bdI. The Estimated Pay line item
itself (added in 8bc0a70) is unchanged — it was already showing the right
number, only the Total/Free to Spend math needed updating.

iOS (Finance.swift): new Calc.projectedMonthlyPay(mk) — same fallback
logic as web, wraps monthlyPay(mk) but substitutes estimatedPay(mk).wage +
transport(mk) when wage(mk)==0 and no override. income(mk)/freeToSpend(mk)
now call this instead of monthlyPay(mk) directly.
BudgetTabView.incomeCard's Total also switched to projectedMonthlyPay.

Deliberately did NOT touch the Home tab's 'Next Paycheck' widget
(ContentView.swift / BudgetWidgets.swift) — still shows the real,
unprojected figure. Different context (upcoming paycheck vs budget
planning), Noah didn't ask for that one, left as a scope decision.

Reverts to real numbers automatically the instant hours/override are
logged for that month — same mechanism as the Wage tab estimate card."
   ```

5. **Build and install on device — this is required, not optional:**
   ```
   ./reinstall_budget.sh
   ```
   (or open `ios/Budget/Budget.xcodeproj` in Xcode and run to Noah's iPhone
   + Mac directly if the script has issues). This is the actual fix for the
   Wage tab bug Noah reported as "still broken" — that fix (`8bc0a70`) was
   already correct in the committed Swift, it just was never compiled onto
   his device. Confirm the build succeeds before reporting back.

6. Push:
   ```
   git push origin main
   ```
7. After push, clear any leftover locks:
   ```
   rm -f .git/*.lock .git/refs/**/*.lock 2>/dev/null; true
   ```
8. Report back: commit hash, build result (success/failure), push result.

## After push/build — verify on device

- **iOS/macOS app** (the thing Noah's actually been screenshotting): open
  Wage tab on a future unlogged month — should now show ONE blue "Estimated
  Pay" card only, header says "Estimated Pay ¥X", no duplicate beige card
  underneath. This was already fixed in code; today's build is what makes
  it visible.
- **Budget tab, same month:** Income card shows Wage ¥0, then blue
  "Estimated Pay (if hours match schedule) ~¥72,800" line, Transport
  Received, then **Total should now be ¥83,800** (72,800+11,000), not
  ¥11,000.
- **Free to Spend:** should now be a realistic (possibly positive) number
  for that month instead of a large negative like -¥68,723, reflecting
  projected income minus expenses.
- Log real hours for that month on the Wage tab — Estimated Pay
  everywhere (Wage tab card, Budget tab line, Total, Free to Spend) should
  disappear/revert to the real numbers.
- **Web app:** same checks — hard refresh first since the web app deploys
  faster (Cmd+Shift+R or reopen tab). Should already reflect all fixes
  including the earlier `8bc0a70` card-merge, since it doesn't need a build
  step like iOS does.
