# Budget App — Handoff

_Last updated: 2026-06-26_

A personal finance / budgeting app for tracking 2026 income against Japan's tax
limit, monthly budgets, savings, and silver investments. Two front-ends share one
Supabase backend:

- **Web app** (primary) — single-file React, GitHub Pages.
- **Native app** — SwiftUI + Mac Catalyst (iPhone + Mac), reads the same shared blob.

---

## Repository

- **Remote:** https://github.com/noshnoshnoah999/finance-tracker
- **Local:** `/Users/noahflouty/Claude/finance-tracker`
- **Branch:** `main` (push = deploy for web)

---

## Architecture

### Web (`app.html` → `index.html`)
- **Single file.** All UI/logic lives in one `<script type="text/babel">` block in
  `app.html`, transformed in-browser by Babel (no build step). React / ReactDOM /
  Babel / supabase are loaded from unpkg CDN. Classic React via JSX.
- **Deploy:** GitHub Pages serves `index.html`. The working file is `app.html`, so
  **every change must be copied to `index.html` before committing** (`cp app.html index.html`).
- **State:** one big data blob persisted to Supabase. `da` = per-month data,
  `se` = settings. Theme persisted in `data.theme`.
- **Nav:** horizontal scrolling bar driven by
  `const tabs=["home","wage","budget","limit","savings","goals","settings"]` (~line 632),
  rendered by `tabs.map(...)` (~line 1679).

### Native (`ios/Budget/`)
- **SwiftUI + Mac Catalyst.** One fixed theme (no theme picker — mirrors the web's
  active "Ocean" palette).
- **Main tabs** (`ContentView.swift`): Home · Wage · Budget · Savings · More.
  iOS allows 5 tabs before auto-creating a white overflow list, so we keep a custom
  themed **More** screen (Limit · Goals · Settings) instead of the system overflow.
- **Key files:**
  - `Shared/Theme.swift` — color palette (`enum T`), ported from the web Ocean theme.
  - `Shared/Finance.swift` — pay/tax/savings calculations (mirror of web logic).
  - `Shared/Models.swift` — data model + Supabase blob decoding.
  - `Budget/BudgetStore.swift` — load/refresh/push to Supabase, debounced writes.
  - `Budget/*View.swift` — one file per screen.
  - `BudgetWidgets/` — home-screen widgets.
- **Bundle ID:** `uk.flouty.Budget`

---

## Backend (Supabase)

- Shared blob holds all app data. Web and native both read/write it.
- **Edge functions** (`supabase/functions/`):
  - `limit-advisor` — Claude advice on whether planned shifts stay under the tax limit.
  - `analyze-passbook` / `import-bank-emails` — **NO LONGER USED by the UI** (the
    Passbook page was removed). The functions still exist server-side but nothing calls
    them. Safe to delete later if desired.
- **Secrets:** stored in Supabase / GitHub Secrets, never in the repo or in chat.

---

## Deploy workflow

### Web
```sh
cp app.html index.html          # sync (REQUIRED — Pages serves index.html)
git add app.html index.html
git commit -m "..."
git push                        # push = live on GitHub Pages
```

### Native (Mac + iPhone)
```sh
cd ios/Budget

# Mac (Catalyst)
xcodebuild -scheme Budget -configuration Release \
  -destination generic/platform=macos -derivedDataPath ~/tmp_budget build
rm -rf /Applications/Budget.app
cp -r ~/tmp_budget/Build/Products/Release-maccatalyst/Budget.app /Applications/Budget.app
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/\
LaunchServices.framework/Versions/Current/Support/lsregister -f /Applications/Budget.app

# iPhone (device id below — re-check with: xcrun devicectl list devices)
xcodebuild -scheme Budget -configuration Release \
  -destination generic/platform=iOS -derivedDataPath ~/tmp_budget_ios build
xcrun devicectl device install app --device <DEVICE_ID> \
  ~/tmp_budget_ios/Build/Products/Release-iphoneos/Budget.app
```
- **iPhone device id (iPhone 17 Pro):** `73562BAB-DA59-5AB0-A722-8AACE1D8820C`
  (re-verify with `xcrun devicectl list devices`).
- iPhone install sometimes fails with a transient "Connection reset by peer" —
  just **retry 2–3 times**.
- There's also `reinstall_budget.sh` at the repo root.

---

## Theme — current "Coffee" palette (single fixed theme)

Unified **earth palette** from the user's reference swatch (Cav Co.): Tobacco bg,
Vanilla cards, Sand alt, Mahogany text/accent, Mountain muted. Money figures use a muted
olive (+) / muted brick (−); other accents (blue/lav/peach) neutralised to palette browns
so nothing clashes (2026-06-26).

Source swatch: Vanilla `#F1EADA` · Tobacco `#B59E7D` · Mountain `#AAA396` ·
Mahogany `#584738` · Sand `#CEC1A8`.

| Token        | Value |
|--------------|-------|
| bg gradient  | `#c2ab8b` → `#b59e7d` → `#a68d6b` (180°, Tobacco) |
| body bg      | `#b59e7d` |
| card         | `#f1eada` (Vanilla) |
| cardAlt      | `#cec1a8` (Sand) |
| border       | `#d6c9b0` |
| text / sub / muted | `#584738` (Mahogany) / `#6f5d49` / `#9a917f` (Mountain) |
| accent       | `#584738` (Mahogany) |
| green (positive) | `#6f7a48` (muted olive) |
| rose (negative)  | `#9c5240` (muted brick) |
| blue / lav / peach | `#7a6854` / `#8a7c64` / `#b08a55` (all palette browns) |

- **Single theme now.** Web `_t.c` is hard-wired to `COFFEE` (~line 227); the Settings
  theme picker was removed; `th` defaults to `"coffee"`. Old palette constants
  (OCEAN/SAGE/EMBER/LATTE/INDIGO + dark-COFFEE replaced) still exist in the file but are
  unreferenced — safe to delete later.
- Web: `const COFFEE={...}` (~line 137) + `body { background:#cdbb96 }` (~line 28) +
  `<meta theme-color="#cdbb96">`.
- Native: `Shared/Theme.swift` `enum T` (kept in sync by hand).

⚠️ Keep backgrounds **warm and saturated — never near-white** (long-standing user pref).

---

## Recent work (this session)

1. **Removed the Passbook page entirely** (web + native) — user no longer used it.
   Deleted `PassbookView.swift`, removed all `pb*` state/helpers, the passbook tab,
   AI spending-insights UI, and bank-email import button. Edge functions left in place
   but unused.
2. **More colorful background** — replaced the washed-out near-white Ocean with the
   vivid blue→indigo→violet gradient + tinted cards above.
3. **Promoted Savings to the main nav bar** (native) — now Home · Wage · Budget ·
   Savings · More. Web already had it.

---

## Open / pending items (offered, awaiting user)

- **Home vs Passbook reconcile** — *now moot* since Passbook was removed. The Home
  "left to spend" `monthOut` calc still exists and is correct.
- **Dad's Contributions recurrence** — items are per-month; new ones don't auto-repeat
  to later months. User hasn't asked to change this yet.
- **Dead edge functions** — `analyze-passbook` and `import-bank-emails` are no longer
  called by any UI. Could be deleted from Supabase.

---

## Gotchas

- **In-browser preview** (`preview_*` tools) has flaky React auto-mount; the big
  count-up numbers can freeze on a wrong frame under manual mount — that's a **preview
  artifact only**, real devices animate fine. To preview the *look* of palette changes,
  injecting a static HTML mockup into the page is more reliable than mounting the app.
- App is **2026-only** (months hardcoded to 2026). Watch for Tokyo-time / month-key
  (`YYYY-MM`) handling in date logic.
- **Never** sync only `app.html` and forget `index.html` — the live site won't update.
- **Web and native logic/theme must be kept in sync manually** — there's no shared
  source between them.
