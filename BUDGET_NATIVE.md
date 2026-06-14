# Budget — Native iOS + Mac App

A native SwiftUI app (iPhone + Mac Catalyst from one target) built on the **same Supabase blob**
as the web app (`app.html`), following NATIVE_APP_GUIDE.md / the Nudge architecture. Edits on
either side sync through the one `finance_data` row.

- **App name:** Budget · **Bundle ID:** `uk.flouty.Budget`
- **Project:** `ios/Budget/Budget.xcodeproj` (objectVersion 77, synchronized-folder format — drop a
  `.swift` file into `ios/Budget/Budget/` and it's picked up automatically, no pbxproj edits)
- **Reinstall script:** `reinstall_budget.sh` (mirrors `reinstall_nudge.sh`)

## Architecture
- **Lossless blob model.** The web app owns and keeps evolving the JSON schema, so the native app
  stores the whole blob as a `JSONValue` tree (`Models.swift`) and reads it through typed accessors.
  Native edits mutate the tree in place — **fields the web app adds are never dropped on write-back.**
- `Finance.swift` — a Swift port of the money math in `app.html` (payday dating, wage, paid leave,
  SUICA/commute, food, subscriptions, monthly income/spending, annual limit). Same numbers as the web.
- `BudgetStore.swift` — sync engine ported from `NudgeStore`: cache-first launch, 15s foreground
  poll, debounced `persist()` + awaited `persistNow()`, `hasPendingPush` conflict guard, rotating
  local backups (60, throttled).
- `Theme.swift` — the Latte palette. `ContentView.swift` — tab shell + Home dashboard.

## Status
- **Phase 1 — DONE.** Scaffold, models, sync, theme, and a working **Home** dashboard (next
  paycheck, left-to-spend for the current month, room-left-to-earn, saved/silver). Verified
  building + running on Mac Catalyst against live data.
- **Phase 2 — TODO.** Build out the remaining tabs natively with editing: Wage, Budget
  (calendar + fixed/subs/one-offs/mum), Passbook (transactions + upload + insights), Limit
  ("what to work"), Savings (cash + silver), Goals, Settings. Each writes via
  `store.setMonth(...)` / `store.setSetting(...)` (lossless).
- **Phase 3 — TODO.** Notifications (payday/limit), Face ID lock, widgets, polish.

## Build & run
```bash
# Compile-check (Mac Catalyst):
xcodebuild -project ios/Budget/Budget.xcodeproj -scheme Budget \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

# Install on iPhone + Mac (Noah runs this — needs the iPhone unlocked & Xcode signed in):
./reinstall_budget.sh                # silent (notifications on failure)
./reinstall_budget.sh --interactive  # modal dialogs
```

## Free-signing 7-day cycle
Uses your personal Apple ID (team `FMF6YAVA23`), no paid account. The app stops launching after
7 days — re-run `reinstall_budget.sh` to reset the clock. The script sets aside cached provisioning
profiles so a fresh 7-day one is minted, and restores them if the build fails. Same caveats as Nudge.

## Gotchas already handled / to watch (from the guide)
- No `Void` statements inside `@ViewBuilder` funcs (use static formatters etc.).
- Test on **iPhone**, not just Mac — vertical TextField focus, Face ID, touch bugs hide on Mac.
- Background notification actions must `await store.persistNow()` or the change is lost on suspend.
- Don't churn `syncState` on every poll (already guarded in `setSync`).
