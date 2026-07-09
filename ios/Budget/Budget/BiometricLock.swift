// BiometricLock.swift — Budget (iOS/Mac)
// Phase 3: optional Face ID / Touch ID (or device passcode) lock. Setting is a local
// device preference (UserDefaults), not synced. Single-prompt guard per the Nudge guide.

import SwiftUI
import LocalAuthentication

@MainActor
final class BiometricLock: ObservableObject {
    @Published var locked: Bool
    @Published var enabled: Bool
    private var authenticating = false
    private static let key = "appLockEnabled"

    /// Grace period: if the app is only backgrounded briefly, don't force Face ID on
    /// return. Locking only kicks in once the app has been in the background this long.
    private static let graceSeconds: TimeInterval = 60
    private var backgroundedAt: Date?
    private var pendingLock: Task<Void, Never>?

    init() {
        let e = UserDefaults.standard.bool(forKey: Self.key)
        enabled = e
        locked = e   // start locked if the user had it on
    }

    /// Turn the lock on/off.
    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.key)
        locked = false
        pendingLock?.cancel(); pendingLock = nil; backgroundedAt = nil
    }

    /// Enable AND immediately prompt Face ID / passcode so the user sees it works.
    func enableWithPrompt() {
        enabled = true
        UserDefaults.standard.set(true, forKey: Self.key)
        locked = true
        authenticate()
    }

    /// Called when the app leaves the foreground. Instead of locking instantly, we start
    /// a grace timer — the app only locks if it stays backgrounded for `graceSeconds`.
    /// Returning to the foreground before then cancels the pending lock (see onForeground).
    func lockOnBackground() {
        guard enabled, !locked else { return }
        backgroundedAt = Date()
        pendingLock?.cancel()
        pendingLock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.graceSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if self.enabled { self.locked = true }
                self.pendingLock = nil
            }
        }
    }

    /// Called when the app returns to the foreground. If we were away longer than the
    /// grace period, lock now (Face ID required). If we're back within the grace period,
    /// cancel the pending lock and stay unlocked — no Face ID prompt.
    func onForeground() {
        pendingLock?.cancel(); pendingLock = nil
        guard enabled, !locked else { backgroundedAt = nil; return }
        if let bg = backgroundedAt, Date().timeIntervalSince(bg) >= Self.graceSeconds {
            locked = true
        }
        backgroundedAt = nil
    }

    /// Prompt for biometrics/passcode. Only one prompt runs at a time (concurrent
    /// LAContext.evaluatePolicy calls jam up iOS).
    func authenticate() {
        guard enabled, locked, !authenticating else { return }
        authenticating = true
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        ctx.evaluatePolicy(policy, localizedReason: "Unlock Budget to view your finances") { ok, _ in
            Task { @MainActor in
                self.authenticating = false
                if ok { self.locked = false }
            }
        }
    }
}

struct LockView: View {
    let onUnlock: () -> Void
    var body: some View {
        ZStack {
            T.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 46)).foregroundStyle(T.accent)
                Text("Budget is locked").font(.headline).foregroundStyle(T.text)
                Button(action: onUnlock) {
                    Text("Unlock").fontWeight(.bold).foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(T.accent).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }
}
