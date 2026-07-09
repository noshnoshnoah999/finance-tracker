# Claude Code — commit, push & verify (2026-07-09)

The **Paidy Tracking + Send-to-Mum** feature is already committed locally as
`ddac5b5` (NOT yet pushed). Cowork then made **follow-up fixes** (auto-calc paid
count, "Payments made" relabel + layout fix, and promoting Paidy to a top-level
nav tab) that are **still uncommitted** — the sandbox can't run git (stale
`.git/index.lock` it lacks permission to remove). **Fold these into `ddac5b5`,
then push.**

## 1. Clear any stale lock, then check state
```bash
cd /path/to/finance-tracker   # your local repo
rm -f .git/index.lock .git/HEAD.lock
git log --oneline -1      # expect: ddac5b5 Paidy tracking + Send-to-Mum settings (web + iOS/macOS)
git status                # expect main ahead of origin/main by 1, plus the modified files below
```
Outstanding (uncommitted) follow-up changes:
- `app.html`, `index.html` — auto-calc + "Payments made" relabel + Paidy form layout fix
- `ios/Budget/Budget/ContentView.swift` — Paidy as 6th TabView tab (index 4, More→5), deep-link reindex
- `ios/Budget/Budget/PaidyView.swift` — isAuto tag, relabel, layout fix
- `ios/Budget/Budget/SettingsView.swift` — Settings "Open Paidy" reindex
- `CLAUDE_CODE_PROMPT.md` — this file

## 2. Fold into the existing commit (amend)
```bash
git add -A
git commit --amend -m "Paidy tracking + Send-to-Mum settings (web + iOS/macOS)

- New Paidy tab (top-level nav): tracks installment plans (iPhone/MacBook), progress, payoff.
- Paid count AUTO-CALCULATES from start date + payment day (self-updating monthly);
  manual override only for exceptions, with an 'auto'/'manual' tag + reset-to-auto.
- Fixed 'Paidy' line DERIVED from paidyPlans (single source of truth; auto-drops as plans finish).
- Send-to-Mum block in Settings with per-item month window (blank end = ongoing).
- Home Paidy summary card. iOS parity: PaidyView + store mutations + nav + settings.
- Web migration seeds paidyPlans, flags the cached fixed Paidy line, and clears the
  stale hand-seeded paid-count override (one-time, paidyMigV=1) so counts auto-calc.
- Paidy form UX: 'Payments made' (a count, not ¥) with hint; Start row split so the
  Month picker no longer wraps and the payment-day field is labeled.
- iOS/Mac TabView: Paidy at index 4, More→5; deep links + Settings 'Open' reindexed;
  removed the redundant Paidy link from the custom MoreView."
```
> ⚠️ Amending is safe here because `ddac5b5` was **never pushed**. Do NOT amend if
> `git status` shows it already on `origin/main`.

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
