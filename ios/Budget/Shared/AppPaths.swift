// AppPaths.swift — Budget (iOS/Mac)
// Resolves the app's data directory.
//
// On Mac Catalyst the app is UNSANDBOXED, so FileManager's `.documentDirectory`
// resolves to the user's real ~/Documents — we don't want to litter that with
// budget_cache.json and backups/. Instead, on Mac we use the conventional
// ~/Library/Application Support/<AppName>/ (created on first use).
//
// On iPhone the sandbox container is correct, so we keep `.documentDirectory`
// unchanged. (Same fix applied to the Nudge app.)

import Foundation

enum AppPaths {
    /// Folder name under ~/Library/Application Support on Mac Catalyst.
    private static let appName = "Budget"

    /// Base directory for all persisted app files.
    static var dataDirectory: URL {
        let fm = FileManager.default
        #if targetEnvironment(macCatalyst)
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
        #else
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }

    /// Returns a file URL inside the data directory.
    static func file(_ name: String) -> URL {
        dataDirectory.appendingPathComponent(name)
    }
}
