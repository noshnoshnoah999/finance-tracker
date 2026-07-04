# Session Handoff — 2026-07-04 (Cowork)

Session covering the 3 tasks from Noah's 2026-07-04 bug/change list. **No commits made yet
— Noah asked to hold all commits until the end / until the native side is built in Xcode.**

## Task 1 — Rearrangeable Budget tab cards ✅ (web verified, native pending build)

UX decided with Noah: **edit-mode drag handles**, order **synced across devices**, **all 9
cards movable**.

The 9 Budget-tab cards (verified in code): `work` (Work Schedule), `income`, `dad` (Dad's
Contributions), `extra` (Extra money), `fixed` (Fixed Expenses), `subscribe` (Subscribe &
Save), `oneoff` (One-off Expenses), `mum` (Send to Mum), `free` (Free to Spend).

### Web — `app.html` (+ mirrored byte-identical to `index.html`)
- Added `BUDGET_CARDS` module const and `cardOrder` to the `DS` settings default.
- Added reorder state/logic after the `crd` style def: `cardEdit`, `dragId`, a normalized
  `cardOrder` (falls back to default, appends missing, drops unknown), `moveCard`,
  `cwStyle`, `cwHandle`, `cardPM`, `cardEnd`.
- Budget tab: added a "↕ Reorder cards" toggle; wrapped the 9 cards in a
  `display:flex; flex-direction:column` container; each card sits in a
  `<div data-cardid=… style={cwStyle(id)}>` whose CSS `order` = index in `cardOrder`
  (reorders visually with **zero** restructuring of the card JSX).
- Drag uses **pointer events + `elementFromPoint`**, not HTML5 drag-and-drop — HTML5 DnD
  does not work in an iOS PWA. Handle calls `releasePointerCapture` so touch move events
  reach the container. Works on iPhone touch and macOS mouse.
- Verified: Babel/JSX compiles clean; reorder logic unit-tested (always 9 unique cards,
  migration-safe, drops unknown ids); `app.html` and `index.html` are byte-identical.

### Native — SwiftUI (NOT build-tested; no Swift toolchain in the Cowork env)
- `Shared/Models.swift`: added `BUDGET_CARDS` + `BUDGET_CARD_NAMES`.
- `Budget/BudgetStore.swift`: added computed `cardOrder` (same normalization as web) and
  `moveCards(from:to:)` writing `settings.cardOrder` and persisting (syncs to web).
- `Budget/BudgetTabView.swift`: body now renders `ForEach(store.cardOrder)` → `cardFor(id)`;
  added a "Reorder cards" button opening a `.sheet` with a `List` in permanent EditMode
  (native drag handles) using `.onMove { store.moveCards(...) }`.
- **TODO for Noah/Claude Code:** build in Xcode to confirm it compiles before committing.

## Task 2 — Native notifications ⏸ handed off to Claude Code

Investigated but did not change notification code (can't run the app to confirm the root
cause, and can't build Swift here). Full diagnosis, the complete web-vs-native notification
audit (web fires 13 types; native schedules 5, missing 8), and a concrete implementation
plan are in **`NOTIFICATIONS_HANDOFF.md`**. Noah will hand that to Claude Code.

Key point: native scheduling code is largely correct; the likely cause of "no
notifications" is device state (toggle off, or OS permission denied — which fails
silently). First on-device check: Settings → toggle on → "Send test notification".

## Task 3 — Bug sweep ✅

The prior `BUG-REPORT.md` (2026-06-12 scan) is now **mostly resolved** in current code:
- P1-1 Vite scaffold (`src/`, `public/`, `vite.config.js`, `package.json`): removed. ✅
- P1-2 paid-leave toggle cycle: web `toggleDay` and native `toggleDay` both now do
  `pl→off→work→hol→pl`. ✅ (parity confirmed)
- P2-2 manifest theme/background colors: both `#b38f57`. ✅
- P3-2 `cMN` off-year fallback: now `(getFullYear>2026?12:0)`. ✅
- P4b allpaid dedup: now `fireOnce('allpaid-'+mk,…)`. ✅
- P4a home bill ids: skin/gensav now included only when amount > 0. ✅
- P4d superseded icon files: gone. ✅

Not re-confirmed / left alone (low value or needs runtime): P2-1 passbook file-input reset
(couldn't locate a `type="file"` handler by the old name — may have been refactored;
worth a runtime check), P3-1 December-payday countdown edge, P3-3 edge-function rate cap
(server-side, unchanged).

**New/outstanding risk from this session:** the native Task-1 code is unbuilt. That's the
main thing to validate before shipping.

## Commit status
Nothing committed. When ready (after Xcode build confirms native Task 1):
`cp app.html index.html` is already done; `diff -q` is clean. Suggested split — one commit
for the reordering feature (web + native), one for the two handoff docs.
