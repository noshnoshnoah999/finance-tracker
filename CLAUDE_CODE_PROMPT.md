# Claude Code — commit, push & verify (2026-07-09)

Cowork built the **Paidy Tracking + Send-to-Mum Settings** feature across the web
app and the native iOS/macOS app, but did **NOT commit** — a stale
`.git/index.lock` (the sandbox shares this repo's `.git`) blocked it, and the
sandbox can't remove that lock. So the commit + push happens here.

## 1. Clear any stale lock, then check state
```bash
cd /path/to/finance-tracker   # your local repo
rm -f .git/index.lock .git/HEAD.lock
git status
```
You should see these modified files plus one new file:
- `app.html`, `index.html`
- `ios/Budget/Budget/BudgetStore.swift`
- `ios/Budget/Budget/BudgetTabView.swift`
- `ios/Budget/Budget/ContentView.swift`
- `ios/Budget/Budget/Notifications.swift`
- `ios/Budget/Budget/SettingsView.swift`
- `ios/Budget/Shared/Finance.swift`
- `ios/Budget/Shared/Models.swift`
- **new:** `ios/Budget/Budget/PaidyView.swift`
- **new:** `HANDOFF_2026-07-09_paidy-mum.md`

## 2. Commit
```bash
git add -A
git commit -m "Paidy tracking + Send-to-Mum settings (web + iOS/macOS)

- New Paidy tab: tracks installment plans (iPhone/MacBook), progress, payoff.
- Paid count AUTO-CALCULATES from start date + payment day (self-updating monthly);
  manual override only for exceptions, with an 'auto'/'manual' tag + reset-to-auto.
- Fixed 'Paidy' line now DERIVED from paidyPlans (single source of truth; auto-drops as plans finish).
- Send-to-Mum block in Settings with per-item month window (blank end = ongoing).
- Home Paidy summary card. iOS parity: PaidyView + store mutations + nav + settings.
- Web migration seeds paidyPlans, flags the cached fixed Paidy line, and clears the
  stale hand-seeded paid-count override (one-time, paidyMigV=1) so counts auto-calc."
```

## 3. Build the iOS/macOS app to VERIFY (not compiled in Cowork)
The Swift was written carefully and brace/paren-balanced, but **never compiled** —
there is no Swift toolchain in the Cowork sandbox. Build it and fix any errors:
```bash
cd ios/Budget
xcodebuild -project Budget.xcodeproj -scheme Budget -destination 'generic/platform=iOS' build | tail -40
```
Watch specifically for (see handoff "compile-risk spots"):
- `updatePaidyPlan(...)` `Int??` optional-optional params at the call sites in
  `PaidyView.swift` (they pass `.some(value)`).
- `.keyboardType(...)` is iOS-only — if a **macOS** target is in the scheme and
  breaks, wrap those modifiers in `#if os(iOS)`.
`PaidyView.swift` is auto-included via the project's synchronized file group — no
pbxproj edit needed, but confirm it appears in the build.

If the build fails, fix, re-run, and **amend the commit** (`git add -A && git commit --amend --no-edit`).

## 4. Push
```bash
cd /path/to/finance-tracker
git push
```

## 5. Tap-test after install
- **Paidy tab (web) / More → Paidy (iOS):** iPhone shows **4/36**, MacBook **6/24**
  (auto-calculated from the schedule — both tagged "auto"); total remaining ≈ **¥222,370**.
  These auto-increment on the 27th each month — no manual bumping. Add/edit/remove a test plan;
  set a manual "Paid so far" and confirm the tag flips to "manual" and "↻ auto" resets it.
- **Home:** Paidy summary card shows and taps through.
- **Settings → Fixed Expenses:** the "Paidy" line reads **¥9,916** and is marked
  derived (not directly editable).
- **Settings → Send to Mum:** add an item with a start/end window; confirm it only
  appears in the Budget "Send to Mum" card within that window.

## ⚠️ Sync ordering (important)
Open the **web app once** before trusting iOS numbers. The web migration seeds
`paidyPlans` into the synced blob on first load; until it does, iOS sees no plans
and the derived Fixed line reads ¥0 (budget understated). See the handoff for detail.

## 6. Leave it clean for next time
```bash
rm -f .git/index.lock .git/HEAD.lock 2>/dev/null || true
git status   # should be clean
```
