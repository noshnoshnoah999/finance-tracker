# Handoff — 2026-07-09 — Savings Sync, Web Keyboard Done, Face ID Grace Period

Session in Cowork. Three changes, all shipped to **both web (app.html/index.html) and iOS (ios/Budget/)** where applicable, keeping web/native parity.

## 1. Savings ↔ Budget sync (the ¥10,000 bug)

**Symptom:** July was set to "not saving" (General Savings) and "not investing" (Silver)
on the Budget tab, but the Savings tab still showed ¥10,000 for July, dragging
Total Saved 2026 to ¥10,000, Avg/month to ¥1,429, and Projected Year to ¥17,143.

**Root cause:** The ¥10,000 was a **manual entry** sitting in `da["2026-07"].savings`.
The effective-savings function let any manual `savings > 0` bypass the `saveGen`
toggle:
- web `savEff` (app.html ~L491)
- iOS `Finance.savingsTotal` (Shared/Finance.swift ~L349)

So the Budget "not saving" toggle never suppressed it. Avg (`tS/cMN`) and Projected
(`avgMonth*12`) were correct formulas fed a wrong `tS`.

**Decision (confirmed with Noah):** *Toggle wins.* If a month is opted out on the
Budget tab (`saveGen=false` or General Savings hidden), that month contributes **¥0**
on the Savings tab regardless of any manual amount. The two tabs are now linked/synced
for every month. Same logic requested for Silver (Silver was already gated by
`saveSilver`, so it was already correct — no data change needed).

**What changed:**
- web `savEff` now returns 0 when opted out, before reading manual `savings`.
- web Savings-tab month renderer: opted-out months show a "not saving" pill + a note
  ("Set to 'not saving' on the Budget tab…") and **hide the input** so you can't type a
  value that would be ignored.
- iOS `savingsTotal` mirrors the same guard; added `savingsOptedOut(_:)` helper.
- iOS `SavingsView` shows the same "not saving" state and hides the field.

**Effect on Noah's real data (Jan–Jun ¥0, Jul opted out):**
Total ¥0, Avg ¥0, Projected ¥0. Verified by simulation.

**No data was deleted.** The stale ¥10,000 still lives in the blob but is *ignored*
while July is opted out. If July is toggled back on, that ¥10,000 reappears as the
manual amount. If you'd rather physically clear it, set July savings to 0 on the
Savings tab after toggling it on — but that's optional.

## 2. Web keyboard "Done" bar

iOS **already had** a global keyboard Done button (ContentView.swift, `.toolbar` /
`ToolbarItemGroup(placement:.keyboard)` + `dismissKeyboard()`). The **web app had none**
— numeric keypads (`type=number` / `inputmode=numeric|decimal`) have no Return key, so a
focused amount field could be impossible to dismiss.

Added a framework-agnostic floating "Done" bar at the bottom of app.html (vanilla JS,
injected after `ReactDOM.createRoot(...).render`). It listens on `focusin`/`focusout` at
the document level (survives React re-renders), shows above the keyboard for any numeric
input, and blurs the field on tap (via `mousedown` + `preventDefault` so the blur fires
before the button steals focus). Respects `env(safe-area-inset-bottom)`.

## 3. Face ID 60-second grace period (iOS only)

**Request:** Don't require Face ID every time the app is backgrounded. Only lock if the
app has been in the background **≥60 seconds**. Return within 60s → no Face ID.

**Implementation (BiometricLock.swift):**
- `lockOnBackground()` no longer locks instantly. It records `backgroundedAt` and starts
  a cancellable `pendingLock` Task that sets `locked=true` after 60s if still backgrounded.
- New `onForeground()`: on return, cancels the pending lock. If elapsed ≥60s it locks now
  (Face ID required before content shows); if <60s it stays unlocked (no prompt).
- Wired `onForeground()` into BudgetApp.swift `.active` (iOS) and the macCatalyst
  `NSApplicationDidBecomeActiveNotification` handler, before the authenticate check.
- `setEnabled()` clears any pending lock/timestamp.

**Security note / tradeoff (by design):** within 60s of backgrounding, anyone holding
the unlocked phone can reopen without Face ID — this is the exact behaviour requested and
matches banking-app grace periods. A genuine cold launch still locks (`init()` sets
`locked = enabled`). Grace constant: `BiometricLock.graceSeconds = 60` — change there if
Noah wants a different window.

## Files touched
- app.html, index.html (kept identical)
- ios/Budget/Shared/Finance.swift
- ios/Budget/Budget/SavingsView.swift
- ios/Budget/Budget/BiometricLock.swift
- ios/Budget/Budget/BudgetApp.swift

## Verification done
- app.html == index.html (diff clean)
- savEff logic simulated: opted-out July → ¥0; manual/default cases still correct
- Swift: static review only (no Xcode in this env). **Needs a build on device/simulator**
  to confirm the Face ID grace timing and the SavingsView layout feel right.

## Not done / follow-ups
- iOS not compiled here — build & test Face ID grace + Savings "not saving" UI on device.
- Web keyboard bar: test on a real iPhone Safari (backdrop-filter + safe-area) — looks
  right by code but untested on hardware.
