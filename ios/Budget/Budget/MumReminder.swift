// MumReminder.swift — Budget (iOS/Mac)
// Keeps the user's existing recurring Apple Reminder ("Send to Mum …") in sync
// with the live amount from the budget app. We only EDIT a reminder the user
// already created — we never create or delete one. Requires Reminders access
// (INFOPLIST_KEY_NSRemindersFullAccessUsageDescription).

import Foundation
import EventKit

enum MumReminder {
    private static let store = EKEventStore()
    // Any reminder whose title starts with this is treated as "the Mum reminder".
    private static let prefix = "Send to Mum"

    /// Recompute the current month's send-to-Mum total and rewrite the matching
    /// reminder's title to show it. Safe to call often (launch, foreground, edits).
    @MainActor static func sync(_ budget: BudgetStore) {
        let amount = budget.calc.sendToMum(currentMonthKeyClamped())
        guard amount > 0 else { return }                 // nothing checked yet — leave text alone
        let newTitle = "\(prefix) — \(yen(amount))"
        Task.detached { await apply(newTitle) }
    }

    private static func apply(_ newTitle: String) async {
        guard await requestAccess() else { return }
        let pred = store.predicateForReminders(in: nil)   // all reminder lists
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        var changed = false
        for r in reminders where !r.isCompleted && (r.title ?? "").hasPrefix(prefix) {
            if r.title != newTitle {
                r.title = newTitle
                try? store.save(r, commit: false)
                changed = true
            }
        }
        if changed { try? store.commit() }
    }

    private static func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess { return true }
        if status == .denied || status == .restricted { return false }
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            return await withCheckedContinuation { c in
                store.requestAccess(to: .reminder) { ok, _ in c.resume(returning: ok) }
            }
        }
    }
}
