// BudgetApp.swift — Budget (iOS/Mac)

import SwiftUI
import UserNotifications

@main
struct BudgetApp: App {
    @StateObject private var store = BudgetStore()
    @StateObject private var lock = BiometricLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(lock)
                .tint(T.accent)
                .overlay {
                    if lock.locked { LockView { lock.authenticate() } }
                }
                .task {
                    UNUserNotificationCenter.current().delegate = NotifDelegate.shared
                    if lock.locked { lock.authenticate() }
                    await store.refresh()
                    Notifs.schedule(store)
                    poll()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        if lock.locked { lock.authenticate() }
                        Task { await store.refresh(); Notifs.schedule(store) }
                    case .background:
                        lock.lockOnBackground()
                    default: break
                    }
                }
        }
    }

    /// Lightweight 15s foreground poll so web edits show up (same cadence as Nudge).
    private func poll() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await store.refresh()
            }
        }
    }
}
