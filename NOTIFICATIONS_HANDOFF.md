# Native Notifications — Handoff for Claude Code

**Date:** 2026-07-04
**Author:** Cowork session (Claude). I could not run Xcode/Swift in my environment, so
this is a diagnosis + implementation spec for you to build and verify in Xcode.
**Goal:** (1) figure out why Noah gets *no* notifications from the native app and fix it,
(2) port the missing notifications so the native app matches the web app.

---

## 0. Ground rules (from repo CLAUDE.md)

- Native app lives under `ios/Budget/`. Web app is `app.html` / `index.html` (those two
  must stay byte-identical, but **notifications on native are Swift-only — you will not
  touch the HTML for this task**).
- Confirm understanding with Noah before large changes. Put safety first. If you hit a
  git lock error (the `.git` folder is sometimes shared with a sandbox), stop and tell
  him rather than forcing.
- Before committing, the native app must actually **build in Xcode**. The Cowork session
  could not compile Swift, so treat all Swift below as a spec to implement and verify,
  not as tested code.

---

## 1. Files involved

| File | Role |
|---|---|
| `ios/Budget/Budget/Notifications.swift` | The `Notifs` enum: permission, `schedule`, `sendTest`, `add`. This is where scheduled notifications are created. |
| `ios/Budget/Budget/BudgetApp.swift` | Sets `UNUserNotificationCenter.current().delegate` and calls `Notifs.schedule(store)` on launch and on `scenePhase == .active`. |
| `ios/Budget/Budget/SettingsView.swift` | The Notifications toggle (`privacyAlerts()`, ~line 36-66) + "Send test notification" button. |
| `ios/Budget/Budget/BudgetStore.swift` | The synced data blob (`blob.settings`, `blob.data`) and the `Calc` engine (`store.calc`). |
| `ios/Budget/Shared/Finance.swift` | `Calc` — `payday(mk)`, `monthlyPay`, `sendToMum`, `commute`, `food`, etc. |
| `ios/Budget/Shared/Models.swift` | `MONTHS`, `PAID_LEAVE`, and (newly added this session) `BUDGET_CARDS`. |
| `app.html` (reference only) | The web notification-firing block, `useEffect` at ~lines 335-378. This is the source of truth for what notifications should exist. |

---

## 2. Why there may be *no* notifications (diagnosis)

I reviewed the scheduling path end-to-end. **The core code is largely correct**, which is
why I will not claim a single definitive bug without an on-device check:

- `BudgetApp.swift` sets the delegate and calls `Notifs.schedule(store)` on launch and on
  every foreground. ✅
- `Notifs.enable` requests authorization and, if granted, sets `nativeNotifs=true` and
  schedules. ✅
- `Notifs.schedule` guards on `isEnabled` (the `nativeNotifs` UserDefaults flag), clears
  pending, and re-adds triggers for the next 3 paydays (+SUICA/bills/eve) and upcoming
  paid-leave. ✅
- Local notifications need **no entitlement** and none is missing. ✅
- `payday(mk)` returns valid days; future months produce valid future triggers. ✅

The two most likely real causes are **device state, not code**:

1. **The Settings → Notifications toggle is not actually on.** Nothing schedules unless
   `nativeNotifs == true`.
2. **iOS notification permission was denied at some point.** After a denial,
   `requestAuthorization` silently returns `false` and never re-prompts. The toggle can
   look "on" (the `@State notifsOn` is set before `enable` runs) while nothing ever
   delivers, and "Send test notification" also does nothing. **The app currently gives no
   feedback about this state — that is a genuine UX defect worth fixing regardless.**

There is also a benign possibility: the only things currently scheduled are paydays (weeks
away) and paid-leave dates — and **every `PAID_LEAVE` date in the code is May/June 2026,
all in the past** as of 2026-07-04 — so those never fire. It's plausible nothing has simply
come due yet.

### First: one on-device check to disambiguate
Ask Noah to open Settings in the app, confirm the toggle is on, and tap **"Send test
notification."**
- **No banner in ~2s** → OS permission issue. Fix path: iOS Settings → Budget →
  Notifications → Allow. Then implement the denied-permission feedback in §4.1.
- **Test works, scheduled ones don't** → it's the coverage gap in §3/§4.2 (most real
  notifications aren't ported yet).

---

## 3. What the web fires vs. what native schedules

### Web (source of truth) — `app.html` `useEffect` ~lines 335-378
Gated by `ld && se.notifs && Notification.permission === 'granted'`. `pd = gPD(mk)` is
payday. `fire(key,…)` = **daily** de-dup (localStorage `fn-<key>-<YYYY-MM-DD>`);
`fireOnce(key,…)` = **once-ever** de-dup (localStorage `fn1-<key>`).

| # | key | Condition | Title / body (verbatim) | Dedup |
|---|---|---|---|---|
| 1 | `payday` | `d === pd` | 💰 Pay Day! / "Today is your payday — log your hours!" | daily |
| 2 | `payday-eve` | `d === pd-1` | 💰 Pay Day Tomorrow / "Payday is tomorrow (Nth). Get ready!" | daily |
| 3 | `limit90` | `pct >= 90` | ⚠️ Limit Almost Full / "N% used — only ¥X left!" | daily |
| 4 | `limit80` | `pct >= 80` (else-if of #3) | ⚡ Nearing Annual Limit / "N% of your ¥LIMIT limit used" | daily |
| 5 | `suica` | `d >= pd-3 && d <= pd-1` | 🚇 Top up your SUICA / "Payday is in K day(s) (Nth) — load up your SUICA for the new pay period" | daily |
| 6 | `mum` | `d >= pd && d <= pd+2 && mumItems.length>0` | 👩 Send to Mum? / "Don't forget to send Mum her money for this pay period!" | daily |
| 7 | `budget-prep-7` | `needsPrep && d === pd-7` | 📋 Sort your budget — 1 week to payday / "Payday is in 7 days (Nth) — have you added your one-off expenses and sorted your fixed bills for MONTH?" | daily |
| 8 | `budget-prep-2` | `needsPrep && d === pd-2` | 📋 Payday in 2 days — budget not sorted! / "You haven't added one-off expenses or sorted your fixed bills yet for MONTH — do it before the Nth!" | daily |
| 9 | `pl-<date>` | a `PAID_LEAVE` date within 0-5 days | 🏖️ Paid Leave Coming Up / "You have paid leave on DATE — enjoy the time off!" | daily |
| 10 | `unlogged` | `dow === 0` (Sun) & no hours logged this month | 🔁 Hours not logged yet / "You may have worked this week — don't forget to log your hours for MONTH!" | daily |
| 11 | `lastday` | `rem > 0 && rem < hourlyWage*6*2` | 📆 Almost at the Limit / "Only ¥X left — your next shift could exceed your annual limit!" | daily |
| 12 | `halfway` | `tot >= annualLimit/2` | 🏆 Halfway There! / "You've earned ¥X — halfway through your ¥LIMIT annual limit" | once |
| 13 | `allpaid-<mk>` | all fixed bills + suica + food (+skin/gensav/silver if active) paid | ✅ All Bills Paid! / "Every fixed expense is marked as paid for MONTH — nice work!" | once |

`needsPrep = !hasOneOffs || !hasSortedFixed` where `hasOneOffs = month.oneOffs.length>0`
and `hasSortedFixed = any(month.paidFixed value is true)`.

### Native today — `Notifications.swift` `schedule()`
Pre-schedules with `UNCalendarNotificationTrigger` (fires even when app is closed), for the
next 3 upcoming paydays and upcoming paid-leave:

| native id | maps to web | note |
|---|---|---|
| `pay-<mk>` (on payday, 9am) | #1 payday | ✅ |
| `payeve-<mk>` (pd-1) | #2 payday-eve | ✅ |
| `bills-<mk>` (pd-2) | ~#8 budget-prep-2 | ⚠️ not conditioned on `needsPrep`, different text |
| `suica-<mk>` (pd-3) | #5 suica | ⚠️ web fires each of pd-3..pd-1; native only pd-3 |
| `pl-<ds>` (on the day) | #9 paid leave | ⚠️ web warns up to 5 days ahead; native only "today" |

**Missing entirely on native:** #3 limit90, #4 limit80, #6 mum, #7 budget-prep-7,
#10 unlogged, #11 lastday, #12 halfway, #13 allpaid. (8 of 13.)

---

## 4. Implementation plan

### 4.1 Denied-permission feedback (do this regardless of the on-device check)
In `Notifs.enable`, after the auth callback, if `granted == false`, expose that so the UI
can react. Simplest: publish an `@Published`/UserDefaults flag like
`notifDenied`, and in `SettingsView.privacyAlerts()` show a small red line + a button
that opens `UIApplication.openSettingsURLString` when denied. This stops the silent
failure that's the most likely cause of "no notifications." Keep it small and additive.

### 4.2 Port the missing notifications

There are **two categories**, and they need different mechanisms:

**A. Date-based (can be pre-scheduled like the existing ones).** These depend only on the
calendar, so add them to `schedule()` alongside the current loop, per upcoming month:
- Full SUICA window: also schedule pd-2 and pd-1 (not just pd-3), matching #5.
- `mum` at payday (and optionally pd+1, pd+2) if `store.calc.se.arr("mumItems")` non-empty — #6.
- `budget-prep-7` at pd-7 — #7. (You *can* pre-schedule this; the `needsPrep` condition is
  data-based, so either drop the condition for the scheduled version, or recompute at
  schedule time using the current month's `oneOffs`/`paidFixed`.)
- Paid-leave: fire a few days ahead, not just on the day — #9.

Use the existing private `add(center, id, date, title, body)` helper. Keep ids stable
(`removeAllPendingNotificationRequests()` runs first each time, so re-adding is safe and
there is **no** de-dup concern for scheduled items).

**B. State-based (cannot be pre-scheduled cleanly).** #3/#4 limit %, #10 unlogged,
#11 lastday, #12 halfway, #13 allpaid depend on live data (earnings so far, whether hours
are logged, whether bills are ticked). On native these should be **evaluated at
launch/foreground** (in `schedule()`, which already runs then) and, if the condition is
true right now, fired with a **near-immediate** trigger (e.g. `UNTimeIntervalNotificationTrigger`
of ~5s). **These DO need de-dup** — otherwise they re-fire every time the app foregrounds.
Mirror the web:
- daily de-dup for limit80/limit90/lastday/unlogged: store a `UserDefaults` key like
  `fn-<key>-<yyyy-MM-dd>` and skip if present.
- once-ever de-dup for halfway/allpaid: store `fn1-<key>` (for allpaid, key includes `mk`).

Compute values from `store.calc`:
- `tot` = sum over MONTHS of taxable earnings (see how the web computes `gTx`; there should
  be an equivalent on `Calc` — check `Finance.swift`). `pct = tot/annualLimit*100`,
  `rem = annualLimit - tot`.
- `unlogged`: only on Sunday; current month `hours>0 || wageOverride>0` false.
- `allpaid`: replicate the web `allBillsPaid` boolean (fixed items all paid/skipped, plus
  suica/food, plus skin/gensav/silver when active) — there may already be a
  `leftToPay(mk)==0` helper on `Calc` you can reuse.

### 4.3 Text/parity
Match the web titles/bodies verbatim where practical (table in §3) so the two apps feel
identical.

---

## 5. Testing in Xcode (required before commit)
1. Build the app (this session could not — confirm it compiles first).
2. Settings → toggle Notifications on → grant permission.
3. Tap "Send test notification" → banner should appear in ~2s.
4. Temporarily hack a trigger date to a few seconds out (or set device date near a payday)
   to confirm scheduled ones deliver with the app **closed**.
5. Confirm state-based ones fire once and then de-dup (don't re-fire on every foreground).
6. Test the denied path: deny permission in iOS Settings, reopen app, confirm the new
   red hint + Open Settings button appears.

---

## 6. Out of scope for this handoff
- The Budget-tab card reordering feature was completed in the same session (web verified;
  native written but pending an Xcode build). It's unrelated to notifications.
- Do not modify `app.html`/`index.html` for this task.
