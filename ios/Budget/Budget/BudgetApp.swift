// BudgetApp.swift — Budget (iOS/Mac)

import SwiftUI
import UserNotifications

@main
struct BudgetApp: App {
    @StateObject private var store = BudgetStore()
    @StateObject private var lock = BiometricLock()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The Latte theme is a LIGHT design — make the tab bar opaque & readable
        // regardless of the system's light/dark setting (fixes the brown-on-brown bar).
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0.93, green: 0.89, blue: 0.82, alpha: 1.0) // warm cream
        let brown = UIColor(red: 0.39, green: 0.25, blue: 0.12, alpha: 1.0)            // accent brown
        let muted = UIColor(red: 0.55, green: 0.45, blue: 0.32, alpha: 1.0)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.selected.iconColor = brown
            item.selected.titleTextAttributes = [.foregroundColor: brown]
            item.normal.iconColor = muted
            item.normal.titleTextAttributes = [.foregroundColor: muted]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(lock)
                .tint(T.accent)
                .preferredColorScheme(.light)
                .overlay {
                    if lock.locked { LockView { lock.authenticate() } }
                }
                .task {
                    UNUserNotificationCenter.current().delegate = NotifDelegate.shared
                    if lock.locked { lock.authenticate() }   // prompt on genuine launch
                    await store.refresh()
                    Notifs.schedule(store)
                    MumReminder.sync(store)
                    poll()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // On Mac, scenePhase flips to .active for windows that are merely
                        // visible (Stage Manager), not focused — so DON'T prompt here on Mac;
                        // the NSApplication active notification below does it on real focus.
                        #if !targetEnvironment(macCatalyst)
                        if lock.locked { lock.authenticate() }
                        #endif
                        Task { await store.refresh(); Notifs.schedule(store); MumReminder.sync(store) }
                    case .background:
                        lock.lockOnBackground()
                    default: break
                    }
                }
                // Mac: drive lock/unlock off the real "app became frontmost" signal so Touch ID
                // prompts when you actually switch TO the app — but never while it's just visible
                // behind another app in Stage Manager.
                #if targetEnvironment(macCatalyst)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NSApplicationDidBecomeActiveNotification"))) { _ in
                    if lock.locked { lock.authenticate() }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NSApplicationDidResignActiveNotification"))) { _ in
                    lock.lockOnBackground()
                }
                #endif
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
