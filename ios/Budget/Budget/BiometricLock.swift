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
    }

    /// Enable AND immediately prompt Face ID / passcode so the user sees it works.
    func enableWithPrompt() {
        enabled = true
        UserDefaults.standard.set(true, forKey: Self.key)
        locked = true
        authenticate()
    }

    /// Re-lock when leaving the foreground.
    func lockOnBackground() { if enabled { locked = true } }

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
