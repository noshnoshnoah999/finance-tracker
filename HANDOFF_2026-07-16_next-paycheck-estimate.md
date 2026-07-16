# Handoff — Next Paycheck estimate fallback (2026-07-16)

## What changed

The "Next Paycheck" hero card (homepage, web + iOS) and the iOS home-screen
widget were showing **Wage = ¥0** for any month where KOT hours hadn't been
logged yet, even though Transport already correctly estimated from the
calendar. Reported via screenshot: August pay showed ¥11,000 total, all of
it Transport, Wage blank.

Root cause: these two views called the raw wage getters (`gW` on web,
`c.wage(mk)` on iOS) directly. They never used the estimated-pay fallback
(`gEstPay` / `Calc.estimatedPay`) that the Budget tab already relies on for
projecting unlogged months from schedule + calendar. See
[[estimated-pay-feature]] memory for how that estimate function works.

## Files touched

- `app.html` / `index.html` (kept byte-identical) — Next Paycheck hero,
  `_pcWage` now falls back to `gEstPay(payMK).wage` when `gW(_pcD)===0` and
  no `wageOverride` is set. Label shows "Wage (est.)" when estimated.
- `ios/Budget/Budget/ContentView.swift` — `nextPaycheck()`, same fallback
  using `c.estimatedPay(payMK)`. Label shows "Wage (est.)" when estimated.
- `ios/Budget/BudgetWidgets/BudgetWidgets.swift` — `computeEntry()`, same
  fallback. Widget has no line-item breakdown so no "(est.)" label there —
  just shows the projected total.

## Behavior

- Transport was already calendar-derived (`gTr`/`c.transport`) and did not
  need a change — it displayed correctly in the reported screenshot.
- Fallback triggers only when wage is ¥0 AND there's no manual
  `wageOverride` — matches the existing Budget tab convention exactly
  (`bdEstForTotals` in app.html, `projectedMonthlyPay` in Finance.swift).
- Reverts to real numbers automatically the instant KOT hours or a wage
  override are entered for that month — no separate toggle needed.
- If there's no shift schedule set for the relevant weekday either, the
  estimate itself is ¥0 and the card falls back to "Log your hours to see
  this →", same as before (per user decision — estimate-first, not always-prompt).

## Status at end of session

- Code changes complete and verified (diffs read back, logic checked against
  `taxable()`/`monthlyPay()` composition to confirm no regression in total).
- **NOT committed yet.** `.git/index.lock` was present (stale, 0 bytes) when
  I tried to commit from the sandbox — did not remove it per the
  [[git-shared-repo-collision]] safety rule; left it for Claude Code to
  handle per user's explicit instruction.
- **NOT tested on-device.** No build/run was performed — this is Swift/JS
  logic mirrored from existing, already-tested estimate functions, but the
  actual widget/card rendering with real KOT-unlogged data should be
  spot-checked next session.

## Next steps

1. Run the Claude Code prompt below to commit + push.
2. Build and check the widget + homepage card on-device (or simulator) for
   a month with no KOT hours logged, confirm "Wage (est.)" / estimated
   total appears and matches the Wage tab's own estimate for that month.
3. Confirm the widget refreshes correctly (it has a 3-hour timeline policy,
   so may take a refresh cycle to show updated logic after install).
