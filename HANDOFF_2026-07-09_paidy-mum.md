# Handoff — Paidy Tracking + Send-to-Mum Settings (Web + iOS/macOS)

**Date:** 2026-07-09
**Author:** Claude (Cowork)
**Repo:** `finance-tracker` · branch `main`
**Files touched:** `app.html`, `index.html` (identical), `ios/Budget/**` (7 files + 1 new)

---

## What was built

Two features, on **both** the web app (`app.html`/`index.html`) and the native SwiftUI app (`ios/Budget/`):

1. **Send to Mum — Settings block** with add/edit/remove and a per-item month window (start month/year → end month/year; blank end = ongoing).
2. **Paidy Tracking** — a dedicated tab tracking Apple Paidy installment plans, a home summary card, and a **derived** Fixed-Expenses "Paidy" line.

---

## Decisions locked with Noah (this session)

- **Mum window:** each item can be open-ended OR have a fixed end. Blank end = ongoing.
- **Paidy nav:** new bottom tab `paidy` (web); "Paidy" link in the **More** screen + Home card (iOS).
- **Fixed "Paidy" line is DERIVED** from `paidyPlans` — single source of truth. It auto-drops as plans finish. No manual ¥9,916 anymore.
- **The ¥9,916 to Mum IS the two Paidy plans** (Noah sends Mum the money; she pays both on her Paidy account). It is therefore counted **once**, via the derived Fixed line. "Send to Mum" is a **reminder layer only** — it never subtracted from the budget (confirmed in code: `bdMTDisplay` is not in the `bdFr` free-to-spend formula), so behaviour is unchanged.
- **Old seeded mum item removed:** `DS.mumItems` is now `[]`. The old `{MacBook Air Payment, ¥6783}` was a duplicate/partial and is gone. Noah will re-add mum items via the new Settings UI if needed.
- **iOS/macOS parity:** full add/edit built natively. Compile verification happens on the Mac via Claude Code (no Swift toolchain in the Cowork sandbox).

## Confirmed Paidy data (stored in `DS.paidyPlans`)

| Plan | Financed | Installments | Monthly | Paid (override) | Start | Payoff |
|---|---|---|---|---|---|---|
| iPhone 17 Pro 256GB | ¥112,800 | 36 | ¥3,133 | 4 | Mar 2026 | Feb 2029 |
| MacBook Air 13" Midnight | ¥162,800 | 24 | ¥6,783 | 6 | Jan 2026 | Dec 2027 |

Verified programmatically (today = 2026-07-09):
- iPhone: 4 paid, 32 left, **¥100,268** remaining.
- MacBook: 6 paid, 18 left, **¥122,102** remaining.
- **Total remaining Paidy debt: ¥222,370.**
- Derived Fixed line: **¥9,916** now → **¥3,133** once MacBook finishes (Jan 2028) → **¥0** after iPhone finishes (Mar 2029).

> ⚠️ The **start months (Mar 2026 iPhone / Jan 2026 MacBook) were inferred** by back-dating from Noah's stated paid counts. `paidCountOverride` (4, 6 — Noah-confirmed) is authoritative for the paid count. The start date only affects the **projected payoff month**. If a payoff date looks off, correct the start month in the Paidy tab.

---

## Web implementation (`app.html` / `index.html`)

- `DS`: `mumItems:[]`; new `paidyPlans:[...]`; fixed line 1 gets `paidyDerived:true`.
- Helpers (top-level): `MO_SHORT`, `paidyCalc(p,now)`, `nextPayLabel(now,day)`, `paidyMonthlyForMonth(plans,mk)`.
- Derived fixed: injected into the three amount read-sites — `nonCardBills`, `fxAmt` (budget tab), `cmFx` (home). All three now branch on `f.paidyDerived`.
- Mum window filter: `mumInWindow(it)` applied in `allMumItems`.
- Settings: new "Send to Mum" block (name + ¥ + start/end month-year selects + add/edit/remove) and the Fixed "Paidy" line shows "from Paidy tab" and is not directly editable (Open button jumps to Paidy tab).
- New tab: `"paidy"` added to `tabs` after `savings`; full Paidy render block (summary + per-plan cards with progress/payoff + add/edit/remove).
- Home: Paidy summary card (total remaining + combined monthly + next 27th), taps to the Paidy tab.
- **Migration (`migrateSe`)**: on load, cached settings get `paidyPlans` seeded if absent, and any fixed line whose name matches `/paidy/i` gets `paidyDerived:true`. This makes the derived logic take effect for returning users (Noah's cached `fixed` line predates the flag).
  - *Minor caveat:* the `/paidy/i` name match would also flag any future fixed item containing "paidy" in its name. Noah only has the one, so safe.

**Verification done:** `@babel/standalone` transform → SYNTAX OK. Paidy math cross-checked in Node against the handoff figures. `app.html` and `index.html` are byte-identical.

---

## iOS / macOS implementation (`ios/Budget/`)

State is a shared JSON blob synced via Supabase, so `paidyPlans` and the new `mumItems` fields flow to native automatically. Native work was: read the data, add the derived-fixed + window logic, and build the UI.

- **`Shared/Finance.swift`**: `fixedAmount` branches on `paidyDerived` → `paidyMonthly(mk)`. Added `paidyPlans`, `paidyMonthly`, `paidyCalc` (+ `PaidyState`), `paidyNextPayLabel`, `mumActive`. `sendToMum` now filters by `mumActive`.
- **`Shared/Models.swift`**: added `MO_SHORT`.
- **`Budget/BudgetStore.swift`**: `openPaidy` flag; add/update/remove for `mumItems` and `paidyPlans`.
- **`Budget/ContentView.swift`**: "Paidy" link in MoreView + `navigationDestination` deep link; `paidySummary` Home card.
- **`Budget/PaidyView.swift`** (NEW): summary + per-plan cards with inline edit + add-plan form. Auto-included via the project's `PBXFileSystemSynchronizedRootGroup` (no pbxproj edit needed).
- **`Budget/SettingsView.swift`**: "Send to Mum" section (add/edit/remove + windows); Fixed list shows the Paidy line as "from Paidy" (derived, non-deletable, chevron to Paidy).
- **`Budget/Notifications.swift`**: the "Send to Mum?" reminder now only fires when at least one mum item is active that month.
- **`Budget/BudgetTabView.swift`**: `mumCard` filters items by `mumActive`.

**Verification done:** brace/paren balance checked on all 8 files (all balanced). **No Swift toolchain in the sandbox — the real `xcodebuild` compile MUST run on the Mac.** See Claude Code prompt.

### ⚠️ iOS sync-ordering note
iOS reads `paidyPlans` from the synced blob. The web `migrateSe` seeds+saves `paidyPlans` on first web load. **Open the web app once (so it saves the migrated blob) before relying on the iOS numbers** — otherwise iOS sees `paidyPlans:[]`, the derived Fixed line reads ¥0, and the budget is understated until sync. Alternative hardening (optional, not done): give the iOS `paidyPlans` accessor a `DS`-style fallback default.

---

## Known compile-risk spots for Claude Code to watch (iOS)

- `updatePaidyPlan(...)` uses `Int??` params for nullable-optional fields; call sites pass `.some(value)`. Should type-check via optional promotion, but confirm at build.
- `PaidyView.editFields` bindings (`numBinding`/`intBinding`/`intOptBinding`) — confirm `TextField(text:)` + keyboard modifiers compile on macOS target too (`.keyboardType` is iOS-only; if the macOS target breaks, guard with `#if os(iOS)`).

---

## Update (later same day): paid count now auto-calculates

**Problem found on device:** the Paidy cards showed MacBook 5/24 and iPhone 3/36 — stale hand-seeded `paidCountOverride` values from the pre-correction handoff were baked into the synced blob and overrode the correct counts.

**Long-term fix (Noah picked "most logical"):** the paid count is now **auto-calculated** from start date + payment day by default, so it self-updates every month and never goes stale. Manual override remains only for genuine exceptions (skipped/early payment), with a visible **"auto" / "manual"** tag and a **↻ auto** reset.

- Noah confirmed: payments post **on the 27th, never skipped** → auto-calc is fully reliable. The existing `dayBump` (`day >= paymentDay`) is correct.
- `DS.paidyPlans` seed: `paidCountOverride: null` for both plans.
- **One-time migration** (`migrateSe`, `paidyMigV=1`): clears the stale override on the existing blob so auto-calc takes over. User-set overrides *after* the migration are preserved.
- `paidyCalc` now returns `isAuto`; UI shows the tag (web + iOS).
- Verified in Node (today 2026-07-09): auto-calc → MacBook **6**, iPhone **4**. ✓

## Follow-ups / not done

- Optional: iOS `paidyPlans` fallback default (see sync note).
- Optional: inline edit of mum items on iOS Settings (currently add + remove; web has full inline edit).
- Re-confirm inferred Paidy **start months** if payoff dates look wrong.
