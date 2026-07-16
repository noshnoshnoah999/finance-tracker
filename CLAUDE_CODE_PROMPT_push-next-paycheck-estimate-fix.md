Commit and push the pending changes in this repo (Budget App / finance-tracker).

Context: I (working via Cowork) fixed a bug where the "Next Paycheck" homepage
card (web + iOS) and the iOS home-screen widget showed Wage = ¥0 for any
month with no KOT hours logged yet, instead of an estimate. The fix makes
those two views fall back to the existing schedule+calendar wage estimate
(gEstPay / Calc.estimatedPay) when wage is 0 and there's no manual override —
same convention the Budget tab already uses. Full detail in
HANDOFF_2026-07-16_next-paycheck-estimate.md.

Steps:

1. Run `git status` first. You may see a stale `.git/index.lock` — if so,
   confirm no other git process is genuinely running (check for other open
   terminals/processes touching this repo), then remove the lock file and
   proceed. This is a known sandbox/local-terminal shared-repo quirk, not
   data corruption.

2. Review the diff for these files (already staged or modified, not yet
   committed):
   - app.html
   - index.html
   - ios/Budget/Budget/ContentView.swift
   - ios/Budget/BudgetWidgets/BudgetWidgets.swift

3. Also check these untracked handoff/prompt files from earlier sessions —
   add and commit them too if they aren't already committed:
   - HANDOFF_2026-07-15_estimated-pay.md
   - HANDOFF_2026-07-15_totals-card.md
   - HANDOFF_2026-07-16_next-paycheck-estimate.md
   - CLAUDE_CODE_PROMPT_debug-estimated-pay.md
   - CLAUDE_CODE_PROMPT_push-estimated-pay-fix.md
   - CLAUDE_CODE_PROMPT_push-limit-chat-cutoff-fix.md
   - CLAUDE_CODE_PROMPT_push-next-paycheck-estimate-fix.md (this file)

   Check git log first — some of these may reference work already pushed in
   an earlier session. Only commit what isn't already captured in history.

4. Commit the code changes with a message like:

   "Fix Next Paycheck wage showing ¥0 before KOT hours logged

   Homepage card (web + iOS) and iOS widget now fall back to the
   schedule+calendar wage estimate (gEstPay/estimatedPay) when no hours
   or override are logged for the pay month, same as the Budget tab
   already does. Transport was already calendar-derived and unaffected.
   Reverts to real numbers automatically once KOT hours are entered."

   Commit the handoff/prompt markdown files separately or together, your call.

5. Push to the remote (`git push`).

6. IMPORTANT — after committing and pushing, remove any leftover git locks
   (`.git/index.lock` or similar stale lock files) so the next session
   starts clean without needing to debug this again.

7. Report back: what was committed, the commit hash(es), and confirm the
   push succeeded.

Do not run a build or execute any code beyond git operations — this is a
git-only task. No API keys or secrets are involved.
