# Bug Report — Finance Tracker (for Opus to fix)

Scan date: 2026-06-12. Scope: the whole `finance-tracker` repo (app, service workers, manifests, push pipeline, edge function). Fix the issues below in priority order.

## Read this first — how this repo works

- **`app.html` is the source. `index.html` is the deployed copy.** There is NO build step. After every edit to `app.html`, run `cp app.html index.html`. Never edit `index.html` directly.
- The app is React 18 + Babel Standalone in one file. Babel transpiles `const`→`var`, so a variable used before its declaration does **not** crash — it is silently `undefined`. Bugs of that class are invisible at runtime.
- Deployed via GitHub Pages. Supabase for sync. Do not introduce a bundler, framework, or new files unless an issue below says so.
- There are already **uncommitted fixes** in `app.html`/`index.html` from earlier today (a use-before-declaration fix for `nMK`, and a dynamic halfway-point label). Keep them. When all fixes below are done, commit everything and push.

---

## P1-1 · Delete the abandoned Vite scaffold (conflicting second app)

**Files:** `src/App.jsx`, `src/main.jsx`, `package.json`, `vite.config.js`, `public/sw.js`, `public/manifest.json` (all untracked).

**Problem:** `src/App.jsx` is a 906-line obsolete draft of the app (no Supabase, no themes, no silver, no Passbook AI). The repo therefore contains two app implementations, two manifests, and two service workers. `public/sw.js` is a cache-first service worker that would permanently freeze the app at an old version if it were ever deployed, and `src/main.jsx` registers `/sw.js` — the wrong path for GitHub Pages (`/finance-tracker/sw.js`). This is dead code waiting to cause a wrong-file edit or a broken deploy.

**Do:** Delete `src/`, `public/`, `package.json`, `vite.config.js`. Also delete `supabase/functions/.DS_Store` and add a `.gitignore` containing `.DS_Store`. Do NOT touch the root `sw.js` and root `manifest.json` — those are the live ones.

## P1-2 · Calendar: hardcoded paid-leave days are a dead-end

**File:** `app.html` — `toggleDay` inside `renderCal()` (~line 517–529), interacts with `getDayState` (~line 84) and the `PAID_LEAVE` array (~line 82).

**Problem:** The 5 dates in `PAID_LEAVE` get state `"pl"` from `getDayState` *without* a `customDays` override. The tap cycle in `toggleDay` for such a day goes: `"pl"` → `"off"` (override) → tap again hits `state==="off" → next=null`, which **deletes** the override — and `getDayState` falls back to `"pl"` again. So a hardcoded PL day can only ever toggle between PL and OFF; it can never be marked Work or Holiday (e.g. if Noah actually worked 2026-06-01 and took leave another day). If the day is not in `se.workDays`, it's fully stuck: `"pl"` → `next=null` → still `"pl"` — taps do nothing at all.

**Do:** In `toggleDay`, treat hardcoded-PL days specially so the full cycle is reachable via overrides. Concretely:
- `state==="off"` → `next = PAID_LEAVE.includes(ds) ? "work" : null;`
- `state==="pl" && !isSched` → `next = "work"` instead of falling into the delete branch.
This gives PL days the cycle pl → off → work → hol → pl. Keep behaviour for normal days unchanged.

## P2-1 · Passbook AI: picking the same file twice does nothing

**File:** `app.html` ~line 1418 (file input inside the Passbook AI card, Settings tab).

**Problem:** `<input type="file" onChange={...}>` never has its `value` reset. Browsers only fire `onChange` when the value changes, so selecting the **same** file again (e.g. retry after a timeout error — exactly the flow we built the error message for) silently does nothing. The label even invites it: "Scan another (last: …)".

**Do:** Capture the file, then clear the input before analysing:
```jsx
onChange={e=>{const f=e.target.files&&e.target.files[0];e.target.value="";analyzePassbook(f);}}
```

## P2-2 · manifest.json has stale theme colors (old Sage theme)

**File:** `manifest.json` (root — the live one).

**Problem:** `background_color: "#2d6a3e"` (green) and `theme_color: "#f0f5ee"` are from the old Sage theme. The app migrated to Latte (`app.html` uses `<meta name="theme-color" content="#b38f57">` and body background `#b38f57`). On iOS/Android the PWA splash screen flashes the wrong green before the brown app loads.

**Do:** Set both `background_color` and `theme_color` to `"#b38f57"`.

## P3-1 · Home: after the December payday, card shows "Payday is today 🎉" for two weeks

**File:** `app.html` ~lines 434–441 (`payMK` / `daysToPay` for the Next Paycheck hero).

**Problem:** Once today is past the December payday, `payMK` can't advance (no 2027 months in `MONTHS`), so `daysToPay = Math.max(0, negative) = 0` and the card claims payday is today from Dec 16–31.

**Do:** Detect the case (`_today.getDate() > _curPD && _miCur === MONTHS.length-1`) and render a "Paid on the {payPD}th ✓ — next payday in January" style line instead of the countdown. Small, targeted change to the subtitle text only.

## P3-2 · `cMN` pretends it's April in any year other than 2026

**File:** `app.html` ~line 365: `const cMN=nw.getFullYear()===2026?nw.getMonth()+1:4;`

**Problem:** In 2027 every "earned vs future" computation (Limit tab, savings dimming, safe-per-month) silently behaves as if it's April 2026. Arbitrary and wrong.

**Do:** Replace the fallback `4` with: `(nw.getFullYear()>2026?12:0)` — i.e. in 2027+ all 2026 months are past (`cMN=12`); before 2026, none are. Both edge values are already handled safely downstream (`nFM>0`, `cMN>0`, `cMN<=11` guards exist). Note: the app is intentionally 2026-only; this just makes the off-year behaviour sane, it does not add 2027 support.

## P3-3 · Edge function is publicly invocable — Anthropic credit burn risk

**File:** `supabase/functions/analyze-passbook/index.ts`.

**Problem:** The function is called with the Supabase **anon key**, which is public in `app.html` on GitHub Pages. Anyone who reads the page source can invoke the function directly and burn Anthropic API credits. No rate limit exists.

**Do (cheap mitigation, don't over-engineer):** Add a daily call cap inside the function: keep a counter row (e.g. table `fn_usage` with `day` + `count`, or reuse any existing table pattern), increment per call, return HTTP 429 above ~15 calls/day. Noah is the only legitimate user; 15/day is generous. Requires redeploying the function — print the updated file and tell Noah to paste it into the Supabase editor and Deploy (he has done this flow before).

## P4 · Minor (fix if quick, skip if risky)

| # | File / where | Problem | Suggested fix |
|---|---|---|---|
| a | `app.html` ~line 426 `homeBillIds` | Home "Bills paid x of y" counts Skin Treatment / General Savings even when their amount is ¥0, so "all done" needs ticking ¥0 lines. The in-app `allBillsPaid` notification (~line 329) treats ¥0 as paid — inconsistent. | Include `"skinTreatment"` only when `bdSkin>0`, `"generalSavings"` only when `bdGenSav>0`. |
| b | `app.html` ~line 330 | `fire('allpaid', …)` is deduped per-day, so "All Bills Paid!" re-fires every day for the rest of the month once bills are done. | Use `fireOnce` with a month-scoped key, e.g. `'allpaid-'+mk`. |
| c | `app.html` ~line 290 | Notification effect runs on mount with **cached** data (cache-first startup) before cloud data lands — a limit warning could use stale totals. Daily dedup limits the blast radius. | Acceptable as-is; fix only if trivial (e.g. also keying off a cloud-loaded flag). |
| d | repo root | 12 superseded icon files (`*-v2`…`*-v5`, original unversioned). Only `*-v6` are referenced. | Delete the unreferenced ones. |

## Verified clean — do NOT spend time on these

- `scripts/send-push.js` + `.github/workflows/push.yml`: payday math (incl. weekend pull-back) matches the app exactly; JST handling correct; year-agnostic; no secrets committed (`VAPID_PRIVATE_KEY` comes from GitHub secrets).
- Root `sw.js`: notifications-only, no caching — correct for instant updates.
- Supabase sync (debounce + realtime + `selfChange` echo guard) and cache-first startup: working as designed.
- `se.fixed` unguarded `.map/.filter` calls: safe — every load path rebuilds it with a `|| DS.fixed` fallback.
- React hooks: all run before the `if(!ld)` early return; no conditional-hook violations.
- Earlier today, already fixed in working tree (keep, don't redo): `nMK` use-before-declaration (~line 388), hardcoded ¥515,000 halfway label (~line 1551).

## When done

1. `cp app.html index.html` (must be identical — `diff -q` to confirm).
2. Quick smoke test: launch preview server `finance-tracker`, check console for errors, tap through Home / Budget calendar (toggle a paid-leave day through all states) / Settings.
3. Commit everything (including the pre-existing uncommitted fixes) with a clear message and push to deploy.
