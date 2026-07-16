# Handoff — Estimated Pay feature (2026-07-15)

Paste this into a new session to pick up where Cowork left off. Everything
below is already committed AND pushed to `main` (confirmed clean working
tree at commit `62351f0`), but the **iOS/macOS native app has not been
rebuilt onto Noah's device yet** — that's the single most important open
item, see "What's actually still broken" below.

## What this feature does

Adds a rough pay projection for months where Noah hasn't logged real hours
yet, so he can plan expenses ahead instead of seeing ¥0 until payday. Shows
up in three places, all governed by the same rule: **a month is "unlogged"
when `hours===0` AND `wageOverride<=0`; the moment either is set, every
Estimated Pay display for that month disappears and reverts to the real
number.**

1. **Wage tab** — blue "Estimated Pay" card (wage + transport breakdown,
   replaces the old always-on real-numbers card for that month).
2. **Budget tab, Income card** — a line item: "Estimated Pay (if hours
   match schedule) ~¥X".
3. **Budget tab, Total / Free to Spend** — these now use the estimate as if
   it were real income for unlogged months (this was reversed mid-session,
   see below — originally display-only, Noah changed his mind after seeing
   it in practice).

## Core calculation logic (same on web + iOS, must stay in sync)

Web: `gEstHours`/`gEstPay` in `app.html` (mirrored in `index.html`, kept
byte-identical).
iOS: `estHours`/`estimatedPay` in `ios/Budget/Shared/Finance.swift`.

Walks `prevMK(mk)`'s calendar (arrears convention — same as how the rest of
the Wage tab already works: month `mk`'s wage/transport reflect the
*previous* month's work, paid this month). For each day:
- `"work"` state (from `getDayState`/`dayState`, respects `customDays`
  overrides from the Budget tab calendar) → look up that weekday's shift
  from `se.shifts`/`shifts(mk)`, add `sH(shift)`/`shiftHours(shift)` (already
  subtracts break minutes).
- `"pl"` state (paid leave) → flat `PL_HOURS_PER_DAY`/`Calc.plHoursPerDay`
  (7h), same convention as existing `gPLHours`.
- Weekday marked "work" with no shift time set in Settings → contributes 0h,
  counted separately as `noShiftDays` (shown as a ⚠ warning, not silently
  dropped).

Hours × `se.hourlyWage` = wage. Work-day count × `trf(mk)`/`transportRate`
= transport. `total = wage + transport`.

**Fully live-computed on every render** — no cached/stored field. Toggling a
day between working/off on the Budget tab automatically re-syncs everything
downstream, by design.

## Where Free to Spend / Total wiring lives (the reversed decision)

- Web: `app.html`, search for `bdEstForTotals` (~line 581). `bdI` (income
  total) swaps in `gEstPay(bm).wage` for the real `bdW` when wage is 0 and
  no override. `bdFr` (Free to Spend) is derived from `bdI`, so it inherits
  this automatically — no separate change needed there.
- iOS: `Finance.swift`, new `Calc.projectedMonthlyPay(mk)` — wraps
  `monthlyPay(mk)` but substitutes `estimatedPay(mk).wage + transport(mk)`
  under the same condition. `income(mk)`/`freeToSpend(mk)` call this instead
  of `monthlyPay(mk)` directly. `BudgetTabView.incomeCard`'s `total` also
  uses `projectedMonthlyPay`.
- **Deliberately NOT touched:** the Home tab's "Next Paycheck" widget
  (`ContentView.swift`, `BudgetWidgets.swift`) — still shows the real,
  unprojected number. Different context (upcoming paycheck vs. budget
  planning), Noah never asked for that one to change. If asked to project
  it too, that's a new decision, not a bug fix — confirm scope first.

## What's actually still broken (read this before assuming anything is a bug)

**The iOS/macOS native app needs an Xcode rebuild + reinstall to pick up any
Swift change.** There's no hot-reload/cache-refresh like the web app has. On
2026-07-15, Noah reported the Wage tab still showing an old duplicate-card
bug after a "hard refresh" — that turned out to be because he was testing
the **native app**, not web, and the fix (already correct in committed
Swift) had never been compiled onto his device. Don't waste time
re-diagnosing the calculation logic if Noah reports something "not working"
on iOS/macOS — first ask whether the app has actually been rebuilt via
`./reinstall_budget.sh` (repo root) or a fresh Xcode run since the fix was
committed.

**No Xcode/Swift compiler available in Cowork** — all iOS changes this
session are logic-reviewed and brace/paren-balance-checked only, never
actually compiled. Worth an explicit Xcode build check (does it even
compile) before further trusting the Swift, not just a reinstall-and-eyeball
pass.

**Web app has no deploy pipeline config found in the repo** (no
netlify.toml/vercel.json, only a GitHub Actions workflow for a daily push
reminder). If Noah reports the *web* app not reflecting a pushed commit,
check hard-refresh/PWA-reinstall first — same class of caching issue, just
lower stakes than the iOS rebuild requirement.

## Why I kept getting corrected this session — read before repeating

1. First pass: shipped the Estimated Pay card but left the OLD always-on
   real-numbers card rendering underneath it for the same month — nobody
   caught that duplication until Noah screenshotted it. Lesson: when adding
   a conditional "projected" view alongside an existing "actual" view,
   explicitly grep for and gate every other place the raw real numbers
   render, not just the one place you're adding to.
2. Second: assumed "display-only, don't touch Free to Spend" was a
   permanent decision after Noah initially chose that option — he reversed
   it two messages later once he saw the number in practice. Lesson: a
   scope decision made before the user has seen the real UI is provisional;
   don't be surprised if it flips once they do.
3. Third: when Noah said a fix "still isn't working" after a hard refresh, I
   almost re-investigated the calculation logic again before realizing he
   was on native iOS, not web, and the real issue was a missing rebuild, not
   a code bug. Lesson: before re-debugging logic that's already been
   verified correct in source, confirm *which platform/build* the user is
   actually looking at.

## Suggested next steps for a new session

1. Confirm with Noah whether Claude Code has run `./reinstall_budget.sh`
   (or an Xcode build) since commit `62351f0` — if not, that's step one,
   not a code investigation.
2. Once rebuilt, walk through the verification checklist in
   `CLAUDE_CODE_PROMPT.md` (same file, already has one) with Noah directly
   rather than assuming — screenshots have been the reliable signal this
   session, ask for one after each fix before declaring it done.
3. Per standing project instructions: always report back understanding
   before changing anything, confirm before touching real budget math
   (Free to Spend already got reversed once), and keep web + iOS changes
   paired in every commit.
