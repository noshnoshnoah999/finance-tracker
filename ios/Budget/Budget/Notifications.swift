// Notifications.swift — Budget (iOS/Mac)
// Phase 3: on-device local notifications for payday / SUICA / bills / paid leave /
// annual-limit / milestones — ported to match the web app's set (app.html useEffect).
//
// Two mechanisms:
//  • Date-based reminders (payday, SUICA window, budget-prep, mum, paid leave) are
//    pre-scheduled with UNCalendarNotificationTrigger, so they fire even when the app is
//    closed — no server, no web push, no GitHub Actions needed. Re-added every launch/
//    foreground with stable ids (adding replaces a same-id pending request).
//  • State-based reminders (annual-limit %, halfway, all-bills-paid, unlogged hours,
//    last-shift warning) depend on live data, so they're evaluated in schedule() (which
//    runs at launch/foreground) and fired with a near-immediate trigger IF true right now.
//    These carry de-dup keys in UserDefaults — daily (fn-<key>-<yyyy-MM-dd>) or once-ever
//    (fn1-<key>) — mirroring the web's localStorage de-dup so they don't re-fire on every
//    foreground.

import Foundation
import UserNotifications

/// Lets notifications show as a banner even while the app is in the foreground.
final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

enum Notifs {
    static let enabledKey = "nativeNotifs"
    /// Set when iOS has denied notification permission — drives the red hint in Settings.
    static let deniedKey = "notifDenied"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var denied: Bool { UserDefaults.standard.bool(forKey: deniedKey) }

    /// Ask permission, then (if granted) reschedule everything. If iOS denies (or a prior
    /// denial makes requestAuthorization silently return false), record it so Settings can
    /// surface the "open iOS Settings" hint instead of failing silently.
    static func enable(_ store: BudgetStore) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            UserDefaults.standard.set(granted, forKey: enabledKey)
            UserDefaults.standard.set(!granted, forKey: deniedKey)
            if granted { Task { @MainActor in schedule(store) } }
        }
    }
    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Re-check the OS-level permission — it can be revoked in iOS Settings after we were
    /// granted, in which case nothing delivers and the toggle would otherwise look fine.
    static func refreshAuthState() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            UserDefaults.standard.set(s.authorizationStatus == .denied, forKey: deniedKey)
        }
    }

    /// Clear and re-create the upcoming reminders from current data. Safe to call on launch.
    /// Gated on real OS authorization (not just our flag) — mirrors the web's
    /// `Notification.permission === 'granted'` check — so we never consume once-ever de-dup
    /// keys (halfway/all-paid) while notifications can't actually be delivered. Also refreshes
    /// the denied flag every time, catching permission revoked in iOS Settings after the fact.
    @MainActor static func schedule(_ store: BudgetStore) {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let authed = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            UserDefaults.standard.set(s.authorizationStatus == .denied, forKey: deniedKey)
            guard authed else { return }
            Task { @MainActor in scheduleNow(store) }
        }
    }

    /// The actual scheduling work — only reached once OS authorization is confirmed.
    @MainActor private static func scheduleNow(_ store: BudgetStore) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let c = store.calc
        let cal = Calendar.current
        let now = Date()

        // ── Date-based: next 3 upcoming paydays and their surrounding reminders ──
        var count = 0
        for mo in MONTHS {
            let parts = mo.key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let pd = c.payday(mo.key)
            let label = mo.label
            guard let payDate = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: pd, hour: 9)) else { continue }
            if payDate < now { continue }
            func dayBefore(_ n: Int) -> Date? { cal.date(byAdding: .day, value: -n, to: payDate) }

            // Payday + eve (always).
            add(center, "pay-\(mo.key)", payDate, "💰 Pay Day!", "Today is your payday — log your hours!")
            if let d = dayBefore(1) { add(center, "payeve-\(mo.key)", d, "💰 Pay Day Tomorrow", "Payday is tomorrow (\(pd)th). Get ready!") }

            // SUICA top-up window: pd-3, pd-2, pd-1 (web #5 fires each day).
            for k in 1...3 {
                if let d = dayBefore(k) {
                    add(center, "suica\(k)-\(mo.key)", d, "🚇 Top up your SUICA",
                        "Payday is in \(k) day\(k > 1 ? "s" : "") (\(pd)th) — load up your SUICA for the new pay period")
                }
            }

            // Budget-prep nudges — only if the month still needs sorting (recomputed here).
            if needsPrep(c, mo.key) {
                if let d = dayBefore(7) {
                    add(center, "prep7-\(mo.key)", d, "📋 Sort your budget — 1 week to payday",
                        "Payday is in 7 days (\(pd)th) — have you added your one-off expenses and sorted your fixed bills for \(label)?")
                }
                if let d = dayBefore(2) {
                    add(center, "prep2-\(mo.key)", d, "📋 Payday in 2 days — budget not sorted!",
                        "You haven't added one-off expenses or sorted your fixed bills yet for \(label) — do it before the \(pd)th!")
                }
            }

            // Send to Mum — payday and the two days after, if there are any Mum items active this month.
            if c.se.arr("mumItems").contains(where: { c.mumActive($0, mo.key) }) {
                for k in 0...2 {
                    if let d = cal.date(byAdding: .day, value: k, to: payDate) {
                        add(center, "mum\(k)-\(mo.key)", d, "👩 Send to Mum?",
                            "Don't forget to send Mum her money for this pay period!")
                    }
                }
            }

            count += 1
            if count >= 3 { break }
        }

        // ── Date-based: Paidy monthly instalment paid, next 3 payment dates ──
        // Amount is read from c.paidyMonthly(mk) at schedule time (launch/foreground), so it
        // always reflects whatever's currently set in the Paidy tab — including future
        // increases — rather than a hardcoded figure.
        if let payDay = c.paidyPlans.first?.i("paymentDay", 27) {
            var scheduled = 0
            var probe = now
            var tries = 0
            while scheduled < 3 && tries < 48 {   // cap: stop looking after 4 years of no active plan
                tries += 1
                let y = cal.component(.year, from: probe), mo = cal.component(.month, from: probe)
                guard let payDate = cal.date(from: DateComponents(year: y, month: mo, day: payDay, hour: 9)),
                      let next = cal.date(byAdding: .month, value: 1, to: probe) else { break }
                probe = next
                guard payDate > now else { continue }
                let mk = String(format: "%04d-%02d", y, mo)
                let amt = c.paidyMonthly(mk)
                guard amt > 0 else { continue }
                add(center, "paidy-\(mk)", payDate, "💳 Paidy Monthly Instalments Paid", "\(yen(amt)) paid")
                scheduled += 1
            }
        }

        // ── Date-based: upcoming paid-leave — warn a few days ahead and on the day ──
        for ds in PAID_LEAVE {
            let p = ds.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3, let day = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 9)) else { continue }
            let body = "You have paid leave on \(ds) — enjoy the time off!"
            if let lead = cal.date(byAdding: .day, value: -5, to: day) {
                add(center, "pl-lead-\(ds)", lead, "🏖️ Paid Leave Coming Up", body)
            }
            add(center, "pl-\(ds)", day, "🏖️ Paid Leave Coming Up", body)
        }

        // ── State-based: evaluate now; fire (with de-dup) if the condition holds ──
        fireStateBased(center, c, cal, now)
    }

    /// Whether a month still needs budgeting (no one-offs added, or no fixed bills ticked).
    /// Mirrors the web `needsPrep = !hasOneOffs || !hasSortedFixed`.
    @MainActor private static func needsPrep(_ c: Calc, _ mk: String) -> Bool {
        let m = c.month(mk)
        let hasOneOffs = !(m["oneOffs"]?.array ?? []).isEmpty
        let hasSortedFixed = (m["paidFixed"]?.object ?? [:]).values.contains { $0.bool == true }
        return !hasOneOffs || !hasSortedFixed
    }

    /// Live-data reminders that can't be pre-scheduled: annual-limit %, halfway milestone,
    /// all-bills-paid, unlogged hours (Sundays), and the last-shift warning. Fired ~5s out
    /// with UserDefaults de-dup so they don't repeat on every foreground.
    @MainActor private static func fireStateBased(_ center: UNUserNotificationCenter, _ c: Calc, _ cal: Calendar, _ now: Date) {
        let comps = cal.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let y = comps.year, let m = comps.month, let d = comps.day, let wd = comps.weekday else { return }
        let todayStr = String(format: "%04d-%02d-%02d", y, m, d)
        let dow = wd - 1   // JS getDay(): 0 = Sunday

        let mk = currentMonthKeyClamped()
        let label = monthMeta(mk)?.label ?? "this month"

        // Annual-limit progress (sum taxable across all 12 months, like the web `tot`).
        let tot = MONTHS.reduce(0.0) { $0 + c.taxable($1.key) }
        let limit = c.annualLimit
        let pct = limit > 0 ? Int((tot / limit * 100).rounded()) : 0
        let rem = limit - tot

        func fire(_ key: String, _ title: String, _ body: String) { fireOnce(center, key, title, body, todayStr, once: false) }
        func once(_ key: String, _ title: String, _ body: String) { fireOnce(center, key, title, body, todayStr, once: true) }

        // Limit warnings (90% wins over 80%, matching the web else-if).
        if pct >= 90 { fire("limit90", "⚠️ Limit Almost Full", "\(pct)% used — only \(yen(rem)) left!") }
        else if pct >= 80 { fire("limit80", "⚡ Nearing Annual Limit", "\(pct)% of your \(yen(limit)) limit used") }

        // Unlogged hours — Sundays only, if this month has no hours/override logged yet.
        if dow == 0 {
            let cm = c.month(mk)
            let logged = cm.d("hours") > 0 || cm.d("wageOverride") > 0
            if !logged { fire("unlogged", "🔁 Hours not logged yet", "You may have worked this week — don't forget to log your hours for \(label)!") }
        }

        // Halfway milestone (once ever).
        if tot >= limit / 2 {
            once("halfway", "🏆 Halfway There!", "You've earned \(yen(tot)) — halfway through your \(yen(limit)) annual limit")
        }

        // All fixed bills marked paid/skipped for the month (once per month).
        if allBillsPaid(c, mk) {
            once("allpaid-\(mk)", "✅ All Bills Paid!", "Every fixed expense is marked as paid for \(label) — nice work!")
        }

        // Last-shift warning: little room left before the annual limit.
        if rem > 0 && rem < c.hourlyWage * 6 * 2 {
            fire("lastday", "📆 Almost at the Limit", "Only \(yen(rem)) left — your next shift could exceed your annual limit!")
        }
    }

    /// Replicates the web `allBillsPaid` boolean: every fixed line paid or skipped, plus
    /// SUICA + food, plus skin / general-savings / silver when those are active this month.
    @MainActor private static func allBillsPaid(_ c: Calc, _ mk: String) -> Bool {
        let m = c.month(mk)
        let pf = m["paidFixed"]?.object ?? [:]
        let sf = m["skippedFixed"]?.object ?? [:]
        func paid(_ k: String) -> Bool { pf[k]?.bool == true }
        func skipped(_ k: String) -> Bool { sf[k]?.bool == true }
        let fixed = c.fixed
        guard !fixed.isEmpty else { return false }
        guard fixed.allSatisfy({ skipped(c.idStr($0["id"])) || paid(c.idStr($0["id"])) }) else { return false }
        guard paid("suica"), paid("food") else { return false }
        let skinActive = m.d("skinTreatment") > 0
        if skinActive && !paid("skinTreatment") { return false }
        let genActive = c.showGenSav && (m["saveGen"]?.bool == true)
        if genActive && !paid("generalSavings") { return false }
        let silverActive = c.showSilver && (m["saveSilver"]?.bool != false) && (m.d("silverInvest") > 0)
        if silverActive && !paid("silverInvest") { return false }
        return true
    }

    /// Fire a state-based notification ~5s out unless its de-dup key is already set today
    /// (daily) or ever (once). Mirrors the web fire()/fireOnce() localStorage de-dup.
    private static func fireOnce(_ center: UNUserNotificationCenter, _ key: String, _ title: String, _ body: String, _ todayStr: String, once: Bool) {
        let dedupKey = once ? "fn1-\(key)" : "fn-\(key)-\(todayStr)"
        if UserDefaults.standard.bool(forKey: dedupKey) { return }
        UserDefaults.standard.set(true, forKey: dedupKey)
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.add(UNNotificationRequest(identifier: "state-\(key)-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    /// Fire a test notification ~2s from now on THIS device (asks permission if needed).
    static func sendTest() {
        let center = UNUserNotificationCenter.current()
        func fire() {
            let content = UNMutableNotificationContent()
            content.title = "Budget ✓"; content.body = "Notifications are working on this device."; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
        }
        center.getNotificationSettings { s in
            if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional {
                UserDefaults.standard.set(false, forKey: deniedKey)
                fire()
            } else {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                    UserDefaults.standard.set(!ok, forKey: deniedKey)
                    if ok { fire() }
                }
            }
        }
    }

    /// Schedule a single date-based reminder. Skips dates already in the past so we don't
    /// pile up triggers that will never fire.
    private static func add(_ center: UNUserNotificationCenter, _ id: String, _ date: Date, _ title: String, _ body: String) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
