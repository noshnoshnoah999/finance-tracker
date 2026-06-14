// Notifications.swift — Budget (iOS/Mac)
// Phase 3: on-device local notifications for payday / SUICA / bills / paid leave.
// Scheduled in advance with UNCalendarNotificationTrigger, so they fire even when the
// app is closed — no server, no web push, no GitHub Actions needed.

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
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Ask permission, then (if granted) reschedule everything.
    static func enable(_ store: BudgetStore) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            UserDefaults.standard.set(granted, forKey: enabledKey)
            if granted { Task { @MainActor in schedule(store) } }
        }
    }
    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Clear and re-create the upcoming reminders from current data. Safe to call on launch.
    @MainActor static func schedule(_ store: BudgetStore) {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let c = store.calc
        let cal = Calendar.current
        let now = Date()

        // Next 3 upcoming paydays: 3 days before (SUICA), 2 before (bills), 1 before, on the day.
        var count = 0
        for mo in MONTHS {
            let parts = mo.key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let pd = c.payday(mo.key)
            guard let payDate = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: pd, hour: 9)) else { continue }
            if payDate < now { continue }
            add(center, "pay-\(mo.key)", payDate, "💰 Pay day!", "Today's your payday — log your hours.")
            if let d = cal.date(byAdding: .day, value: -1, to: payDate) { add(center, "payeve-\(mo.key)", d, "💰 Payday tomorrow", "Payday is the \(pd)th — get ready.") }
            if let d = cal.date(byAdding: .day, value: -2, to: payDate) { add(center, "bills-\(mo.key)", d, "📋 Sort your bills", "Payday in 2 days — sort this month's bills.") }
            if let d = cal.date(byAdding: .day, value: -3, to: payDate) { add(center, "suica-\(mo.key)", d, "🚇 Top up your SUICA", "Payday in 3 days — load up for the new pay period.") }
            count += 1
            if count >= 3 { break }
        }
        // Upcoming paid-leave days.
        for ds in PAID_LEAVE {
            let p = ds.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3, let d = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 9)), d > now else { continue }
            add(center, "pl-\(ds)", d, "🏖️ Paid leave today", "Enjoy the time off.")
        }
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
            if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional { fire() }
            else { center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in if ok { fire() } } }
        }
    }

    private static func add(_ center: UNUserNotificationCenter, _ id: String, _ date: Date, _ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
