# Handoff — Dad's "Requested?" tracker + auto-refreshing exchange rate

**Date:** 2026-08-28
**Commit:** `5a807ca` (committed, **not pushed**)
**Scope:** web (`app.html` + `index.html`) and iOS/macOS (`ios/Budget/`) — in parity

---

## What changed

### 1. Free-spend feature deleted

The `Free?` button on Dad's Contributions was **not cosmetic**. Toggling it added that
item's yen to income. Everything below is now removed:

| Removed | Where |
|---|---|
| `bdDJFree` | `app.html` Budget-tab income maths |
| `cmDadFree` | `app.html` Home "Left to spend" maths |
| `"Dad (free spend)"` income row | `app.html` + `BudgetTabView.incomeCard` |
| `"From Dad"` row on Home | `app.html` |
| `Calc.dadFree(_:)` | `Shared/Finance.swift` |
| `dadFree` term in `Calc.income(_:)` | `Shared/Finance.swift` |
| `BudgetStore.toggleDadFree(_:)` | `BudgetStore.swift` |
| `dadFreeSpend:{}` default | `app.html` `DS` |

**Consequence:** income and Free to Spend are lower for any month where an item had
been marked Free. Income is now `wage (or estimate) + paid leave + transport + extra money`.

Existing `settings.dadFreeSpend` data in Supabase/localStorage is **left untouched** —
nothing reads it any more. Reverting = `git revert 5a807ca`.

### 2. `Requested?` — Revolut request tracker

Replaces the Free button in the same slot. **Display only. Changes no totals.**

- Web: `data.<monthKey>.dadRequested` — toggled by `tDR(k, id)`, read as `(bd.dadRequested||{})[it.id]`.
- iOS: same JSON path, toggled via the existing `store.toggleBoolMap(bm, "dadRequested", id)`.
- Added `dadRequested:{}` to `eM()` so the realtime-sync merge (`{...eM(), ...v.data[k]}`) always has it.

**Why per month, not settings:** `DEF_DAD()` gives every month the *same* item ids
(`d1`–`d6`). `dadFreeSpend` lived in settings keyed by that id, so a single flag applied to
all twelve months at once. That was tolerable for "this is free money" but wrong for
"I sent the request this month". Do not move this back into settings.

Active colour is `c.blueD` / `T.blueD` deliberately — green in this app means *paid/received*,
and a sent request is neither.

### 3. Exchange rate refreshes itself

- New setting `fxFetchedOn` — local `YYYY-MM-DD` stamp of the last successful fetch.
- Web: `fetchLiveRate()` + a `useEffect` that runs on load and on `visibilitychange`/`focus`,
  fetching only when `se.fxFetchedOn !== lclDay()`.
- iOS/macOS: `BudgetStore.fetchRateIfStale()` + `BudgetStore.localDayKey()`, called from
  `BudgetApp`'s `.task` and from the `scenePhase == .active` branch.
- **Failure handling:** a failed fetch does *not* write `fxFetchedOn` and does *not* touch
  `gbpToJpy`, so the last known rate stands and it retries on the next open. No retry loop.
- Settings numeric field and the `Live rate` button still work — manual override and forced refresh.
- The `💷 Rate improved!` notification is **gone entirely** (web `notify(...,'rate')` removed).

---

## Deliberately NOT done

**Past-month rate freezing.** Yen figures are computed live as `£ × current rate`, so every
month — including January — is re-valued whenever the rate moves. With daily auto-fetch, that
history now drifts daily.

Freezing was considered and dropped for this session because **there is no historical rate data
in the app**: the only rate available to backfill Jan–Aug with is today's. Freezing would lock
those months at today's number and call it history, which is worse than obviously-live figures.

If it gets picked up later: store `data.<mk>.fxRate`, resolve as `month.fxRate ?? settings.gbpToJpy`,
stamp the current month on every successful fetch, and let months freeze naturally as they pass —
accurate from that point forward, with no fake backfill.

---

## Verification performed

`app.html` was served locally and driven with headless Chromium (Playwright), with the FX
endpoint stubbed and Supabase blocked:

- Babel/JSX compiles clean; **zero page errors**
- 6 × `Requested?`, 0 × `Free?` remaining
- Toggling `Requested?` changes **no other text on the page** (full-body string compare)
- Flags are per month: marked 2 in Aug → Sep shows 0 marked / 6 unmarked → back to Aug shows 2
- Exactly **1** FX fetch on open; hide→show on the same day triggers **0** extra fetches
- Failed fetch keeps the previous rate (¥216) and a later resume retries successfully (¥203.4)

**Not verified:** the Swift changes are **not compile-checked** — `device_bash` runs in a Linux VM
with no Swift toolchain, and SwiftUI can't build on Linux at all. Build the iOS/macOS target in
Xcode before trusting it.

---

## Repo hygiene note

`device_bash` cannot delete files, so git could not clean up its own lock files. Two stale
`index.lock` copies were moved to `_to_delete/` — delete that folder. `.git/` is verified clean
of locks and `tmp_obj_*` files.

---

## Follow-up, same day — card layout

Two changes on top of `5a807ca` / `76cf7e1`, after Noah saw it running:

1. **Subtitle removed** from the Dad's Contributions card on iOS/macOS
   (`"What Dad sends each month. Tap Requested..."`). The web card never had one, so this
   brings them into parity rather than out of it.
2. **Item names moved to their own line.** At phone width the names were being clipped
   (`Pocket mo...`, `Commuter...`, `Japanese l...`). Each item is now two lines: the full name
   on top, then `£ amount / ¥ value / Requested? / Edit / ×` below it, pushed apart with a
   spacer. Chosen over wrapping or auto-shrinking text because it cannot truncate at any width
   or name length.

Web: the name div lost `whiteSpace:nowrap` + `textOverflow:ellipsis` and gained
`overflowWrap:anywhere`; the display branch is now one full-width container with a stacked
name and a control row. iOS: the row `HStack` became a `VStack` with the name `TextField` at
`maxWidth: .infinity` above an `HStack` of the controls.

Re-verified in headless Chromium at **390px wide** (the width that was clipping): JSX compiles,
zero page errors, all 6 names render with `scrollWidth == clientWidth` (nothing clipped), the
page does not scroll sideways, and toggling `Requested?` still changes no other text on the page.

Swift again **not compile-checked** — build in Xcode. The whole `dadCard` function was re-read
end to end this time to check for orphaned locals, which is what caused the `dad` build break in
`76cf7e1`.

### Amazon line + "Left to Request"

- **Amazon (Subscribe & Save) now has its own `Requested?` button.** It is a derived aggregate
  (summed from `se.subItems` where `payer === "dad"`), not a dad item, so it has no item id — it
  uses the fixed key `"amazon"` in the same per-month `data.<mk>.dadRequested` map. Same two-line
  layout as the items. Still no `Edit`/`×` on it, since it isn't editable here.
- **"Left to Request" row** added at the bottom of the card, under Total. It is the £ still to ask
  Dad for this month: every dad item not marked Requested, plus the Amazon line's £ equivalent
  (`subTotalDad / gbpToJpy`) when that isn't marked either. £ only, no yen — Revolut requests are
  in £. Turns green at £0.00. Guarded against a zero rate.

Verified at 390px with a seeded dad-payer sub item (¥2,841): 7 `Requested?` buttons (6 items +
Amazon); Left to Request reads £338.15 with nothing marked, £288.15 after marking Pocket money
(£50), £275.00 after also marking Amazon, and £0.00 with everything marked; the Total row is
byte-identical before and after marking; September shows £338.15 and 7 unmarked buttons while
August keeps £0.00, so the `"amazon"` flag is per-month like the rest; no page errors, no
sideways scroll.
