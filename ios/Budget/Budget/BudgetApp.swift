// BudgetApp.swift — Budget (iOS/Mac)

import SwiftUI

@main
struct BudgetApp: App {
    @StateObject private var store = BudgetStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(T.accent)
                .task { await store.refresh(); poll() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refresh() } }
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
