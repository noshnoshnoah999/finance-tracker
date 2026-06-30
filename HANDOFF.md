# Budget App — Handoff

_Last updated: 2026-07-01_

---

## Session 2026-07-01 — Silver Investment checkbox/skip + git collision incident

**Done this session:**

1. **Silver Investment row now matches General Savings UX** (checkbox to mark
   paid, amount field, "Skip / Invest this month" toggle that zeroes the
   amount for that month without deleting the stored figure). Landed via
   commit `c35263b` ("Add checkbox and Skip button to Silver Investment row").
   - Field name used: `saveSilver` (boolean, `undefined`/`true` = investing,
     `false` = skipped — same back-compat pattern as `saveGen`).
   - `silverM(mk)` now gates on `d.saveSilver!==false`.
   - `bdLeftPay` (Budget tab "Left to pay") and `homeBillIds`/`homePaidCount`
     (Home tab paid-count badge) now both include `silverInvest` when active —
     previously Silver was counted in "Total Fixed" but silently dropped from
     "Left to pay" and the Home paid-count, which was a real bug.
   - `allBillsPaid` (drives the "✅ All Bills Paid!" notification) now also
     requires silver to be paid before firing, when active.
   - Applied identically to both `app.html` and `index.html`.

2. **Duplicate-work incident, resolved.** A separate Claude Code terminal
   session (branch `claude/things-need-fixing-qgyh2n`, commit `c35263b`,
   2026-06-28) had independently built the same feature with a more complete
   scope (also touched `index.html`, `allBillsPaid`, `homeBillIds` — areas
   this Cowork session's first attempt missed). Cowork's own attempt (commit
   `44820c3`, field name `investSilver`, narrower scope) was discarded via
   `git reset --hard origin/main` in favor of the terminal session's version.
   Remote branch `claude/things-need-fixing-qgyh2n` deleted after merge
   (already in `main`).
   - **Root cause:** Cowork sandbox and Noah's local terminal share the same
     `.git` directory (Cowork mounts the selected folder directly — not a
     separate clone). Concurrent git operations from both sides produced
     stale `index.lock` / `HEAD.lock` files; the sandbox could not delete its
     own lock files (`Operation not permitted`), so Noah had to clear them
     from his terminal each time.
   - **Standing rule saved to memory** (`git-shared-repo-collision.md`):
     coordinate before git ops from either side; check `git log`/`git fetch`
     at the start of a session in case a parallel Claude Code session already
     touched the same area; all pushes/remote-branch deletes must run from
     Noah's terminal — **the Cowork sandbox has no GitHub push credentials.**

3. **Confirmed pushed:** commit `1654ed3` ("Fix Jan–Apr 2026 pay records
   against actual payslips") from the 2026-06-28 session — listed as
   "NOT pushed" in that session's notes, but verified now present on
   `origin/main`. Item closed below.

**Open / to do (carried forward, still unresolved):**

1. ~~Push commit `1654ed3` to GitHub.~~ **Done — confirmed on `origin/main`.**
2. **5-week-month contradiction — still UNRESOLVED, blocks 2027 build-out.**
   Code (`MONTHS`, ~line 68) flags Mar/Jun/Aug/Nov 2026 as `is5wk` (drives
   ¥20k vs ¥25k food money to Mum). Noah said Jan/May/Jul/Oct. Need to settle
   which is right (test: which 2026 month did Noah actually send Mum
   ¥25,000?) before building 2027 months — `MONTHS` currently ends Dec 2026.
3. **Calendar work-days override displayed days** — stored `days` were
   corrected per payslip, but the on-screen count comes from the Budget-tab
   calendar via `gWorkDays`, so displayed numbers (e.g. Jan showed 12 not 4)
   may still be wrong. Noah needs to fix the calendar entries directly.
4. **Stale transport rates for calculated (May-2026-onward) months** —
   `commuteOneWay`, `trBefore`, `trAfter` (~line 82) reflect Noah's old
   address; he's moved and new daily transport cost is higher. Code's
   rate-change cutoff is `k<="2026-03"` (14 Mar), not May — needs correcting.
   Note: `commuteOneWay` is one-way (×2 in code, ~line 370) and drives SUICA
   only, not the monthly transport figure (that's `trBefore`/`trAfter`).
5. **¥1,030,000 limit assumption unverified** — app excludes transport from
   the limit count (standard JP treatment) but Noah's exact threshold hasn't
   been confirmed against his actual situation.
6. **Two unfinished side tasks** (unrelated to the app itself): (a) Google
   Doc on Nitori topper (product 7544982, semi-double) with price +
   alternatives; (b) Google Doc of JR Keiyō Line trains departing
   Shin-Urayasu 9:00–11:00, both directions.

**KNOWN TOOL ISSUE (carried forward):** Control Chrome MCP
`execute_javascript` / `get_page_content` errors "Chrome not running" even
with tabs visible and permissions granted — confirmed broken regardless of
permission resets. JS-rendered prices/timetables (Nitori, Yahoo transit)
can't be auto-read this way. Have Noah read values off-screen; do NOT guess
money or train-time figures.

---

## Session 2026-06-28 — Payslip pay-record corrections

**Done this session (committed, NOT yet pushed):**

Corrected the four hardcoded past-month earnings in the `PF` block (`app.html`,
synced to `index.html`) against Noah's actual payslips. In this app
`wageOverride` = TOTAL received incl. transport; displayed base pay =
`wageOverride − transportOverride`; that base feeds the ¥1,030,000 limit.

| Month | wageOverride (total) | transportOverride | days | → base |
|-------|---------------------|-------------------|------|--------|
| 2026-01 | 31158 | 2176 | 4 | 28982 |
| 2026-02 | 91543 | 10400 | 10 | 81143 |
| 2026-03 | 121952 | 14560 | 14 | 107392 (incl. ¥35 OT) |
| 2026-04 | 112607 | 15400 | 14 | 97207 |

- **Commit:** `1654ed3` "Fix Jan–Apr 2026 pay records against actual payslips".
- **NOT pushed** — Cowork sandbox has no GitHub credentials. Push from Claude Code
  or run `git push origin main` on the Mac.

**Open / to do (in priority order):**

1. **Push commit `1654ed3` to GitHub.**
2. **5-week-month contradiction — UNRESOLVED, blocks 2027.** Code (`MONTHS`, ~line 68)
   flags Mar/Jun/Aug/Nov 2026 as `is5wk` (drives ¥20k vs ¥25k food money to Mum).
   Noah said Jan/May/Jul/Oct. Verified the code's Mar/Jun/Aug/Nov = "pay period
   15th→14th contains 5 Mondays" rule. Settle which is right (test: which 2026 month
   did Noah actually send Mum ¥25,000?), THEN build 2027 months — `MONTHS` currently
   ends Dec 2026. (If Monday rule holds, 2027 5-week = Mar/May/Aug/Nov.)
3. **Calendar work-days override displayed days.** Stored `days` corrected above, but
   app shows work-days from Budget-tab calendar via `gWorkDays`, so on-screen counts
   (e.g. Jan showed 12 not 4) may still be wrong. Noah must fix the calendar days.
4. **Stale transport rates for calculated (May-2026-onward) months.** `commuteOneWay`,
   `trBefore`, `trAfter` (~line 82) reflect Noah's OLD address; he moved. Verified new
   daily transport higher. Note: code's rate-change cutoff is `k<="2026-03"` (14 Mar),
   not May. Also `commuteOneWay` is ONE-WAY (×2 in code, line ~370) and drives SUICA,
   NOT the monthly transport (that's trBefore/trAfter).
5. **¥1,030,000 limit assumption unverified** — app excludes transport from the limit
   count (standard JP treatment) but Noah's exact threshold not confirmed.
6. **Two unfinished side tasks:** (a) Google Doc on Nitori topper (product 7544982,
   semi-double) with price + alternatives; (b) Google Doc of JR Keiyō Line trains
   departing Shin-Urayasu 9:00–11:00 tomorrow, both directions.

**KNOWN TOOL ISSUE:** Control Chrome MCP `execute_javascript` / `get_page_content`
error "Chrome not running" even with tabs visible and permissions granted — confirmed
broken regardless of permission resets. JS-rendered prices/timetables (Nitori, Yahoo
transit) can't be auto-read this way. Have Noah read values off-screen; do NOT guess
money or train-time figures.

---

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
