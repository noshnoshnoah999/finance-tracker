# Building Native iOS + Mac Apps: Lessons from Nudge

**TL;DR:** Nudge is a web PWA + unified SwiftUI iOS/Mac Catalyst app over a shared Supabase blob. The iOS side took ~3 months of iteration. This document captures what works, what doesn't, and how to do it.

---

## Architecture

### The Blob Model
- **One Supabase project** per app, one `reminders` table (or equivalent) as a JSON blob (`data` text column).
- **Local-first:** iOS/Mac reads the blob into memory at launch, edits locally, pushes changes back (with `updatedAt` timestamp conflict-winning).
- **Web app** (PWA in index.html) hits the same Supabase endpoint, works offline via Service Worker.
- **No REST API per entity.** Just fetch/upsert the whole blob. Keeps sync simple: last-writer-wins on `updatedAt`.

### Code Sharing
- **Shared folder:** `ios/Nudge/Shared/` contains code used by both the app and the widget extension.
  - Data models (Reminder.swift, Recurrence.swift, etc.)
  - Helpers (date parsing, file storage, validation).
  - Do NOT put SwiftUI views here; they're platform-specific.
- **App folder:** `ios/Nudge/Nudge/` = iOS-only views + logic.
  - Mac builds the same app as iOS Catalyst (one .xcodeproj scheme → both platforms).
  - If you need Mac-only logic, use `#if targetEnvironment(macCatalyst)`.

### Supabase Setup
```sql
-- Nudge's actual schema (nudge_data table):
CREATE TABLE nudge_data (
  user_key UUID PRIMARY KEY,    -- hardcoded per-user UUID, not a real auth user
  data JSONB NOT NULL,          -- entire app state as JSON
  updated_at TIMESTAMPTZ NOT NULL
);
```
- One row per user. Fetch with `SELECT data FROM nudge_data WHERE user_key = eq.<uuid>`.
- On write: `UPSERT nudge_data SET data = ?, updated_at = NOW()`.
- **Auth:** Nudge uses Supabase's **anon key** (public-tier, in the binary) + a hardcoded `user_key` UUID per user — no sign-in flow. This works for a personal app with no other users. If you need multiple users, add real Supabase Auth + RLS.
- **Conflict resolution:** Nudge checks if local has pending pushes (`hasPendingPush`) OR if cloud == local (nothing changed) → don't apply cloud. Otherwise cloud wins (apply it). It does NOT compare timestamps — it's simpler than that.

---

## Tech Stack

### SwiftUI + Foundation
- **iOS 16+** (Nudge targets iOS 16; adjust if needed).
- **SwiftUI only.** No UIKit wrappers except where absolutely necessary (e.g., LockShield uses UIWindow for app-lock because a SwiftUI overlay can't sit above presented sheets).
- **@MainActor:** async/await + Combine for state management. No third-party state libraries.

### Persistence
- **UserDefaults:** for small prefs (theme, app-lock setting, pinned lists, etc.). Not for app data.
- **FileManager:** for backups (JSON snapshots) and image attachments (if needed). Create dirs once, not on every access (Nudge learned this the hard way).
- **Codable:** JSON encode/decode the entire blob. Use `@unknown default` on Codable to future-proof when fields are added.

### Networking
- **URLSession only.** No Alamofire/async-http. POST the blob, GET the blob, that's it.
- **Supabase anon key** (hardcoded in the binary) + a per-user UUID as the row key. Both the `apikey` and `Authorization: Bearer <anon-key>` headers go on every request. This is fine for a single-user personal app — no login screen needed.
- If you need multiple users (e.g. a shared app), switch to Supabase Auth + RLS, but that's more complex.

### Apple Reminders Sync (iOS only)
- **EventKit:** optional, but powerful. When a reminder's created in Nudge, you can push it to Apple Reminders so it syncs to iCal/other apps.
- Read-write: fetch Apple reminders, diff against Nudge, merge bidirectionally.
- **Gotcha:** EventKit `lastModifiedDate` wins on conflicts for Apple-side edits; Nudge's `updatedAt` wins for Nudge-side. Be explicit about the order.

### Notifications
- **UNUserNotificationCenter:** local notifications (iOS/Mac, no remote push needed). Schedule notifications based on reminder `dueDate`.
- **Badge count:** update `UIApplication.shared.applicationIconBadgeNumber` so the Home Screen shows how many are overdue.

---

## Project Structure

```
my-app/
├── ios/MyApp/
│   ├── MyApp.xcodeproj          # One project, two platforms
│   ├── MyApp/                   # iOS-specific views & logic
│   │   ├── ContentView.swift    # Main tab view
│   │   ├── AddReminderView.swift
│   │   ├── ReminderCardView.swift
│   │   ├── MyAppStore.swift     # @MainActor, all state
│   │   ├── Theme.swift          # Colors, fonts, swiftui extensions
│   │   ├── Notifications.swift
│   │   └── [other views]
│   ├── MyAppWidgets/            # Widget extension (Home Screen + Lock Screen)
│   │   └── MyAppWidgets.swift
│   ├── Shared/                  # Used by both app and widget
│   │   ├── Models.swift         # Reminder, List, Recurrence, etc.
│   │   ├── Helpers.swift        # Date parsing, formatting, validation
│   │   ├── SyncState.swift      # Supabase fetch/push logic
│   │   └── Constants.swift
│   └── Info.plist
├── web/
│   └── index.html               # PWA, same data model
└── NATIVE_APP_GUIDE.md          # This file
```

---

## Key Patterns

### State Management (NudgeStore analogue)
```swift
@MainActor
final class MyAppStore: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Published var syncState: String = "Synced"  // "Syncing", "Error", etc.
    var userId: UUID?
    
    // Fetch from Supabase
    func refresh() async {
        syncState = "Syncing"
        // GET /reminders?userId=... → decode blob
        reminders = [...]
        syncState = "Synced"
    }
    
    // Push back
    func persist() async {
        // UPSERT blob with new updatedAt
        // On conflict, local loses if server is newer
    }
    
    // Local edits ALWAYS call persist() after
    func addReminder(_ r: Reminder) {
        reminders.append(r)
        Task { await persist() }
    }
}
```

**Guard against state churn:** if `syncState` is set to the same value, don't publish — it triggers re-renders and can drop keyboard focus in open edit sheets. Use a `setSync()` helper:
```swift
func setSync(_ s: String) {
    if syncState != s { syncState = s }  // only publish if changed
}
```

### Backup Strategy
- **On app launch + every sync:** snapshot the blob to `Documents/backups/`.
- **Keep 60 most recent** (rolling window, oldest auto-deleted).
- **Surface in Settings:** "Last backup: 2 minutes ago (47 kept)" so the user trusts data is safe.
- **One-tap restore:** if the cloud blob gets corrupted, a user can tap "Restore from backup" → pick a date → reload.

### Undo/Redo
- **Single last-deleted reminder** held in memory (`recentlyDeleted`). No full edit history.
- **Not persisted.** Relaunch clears it.
- **Image cleanup is deferred:** on delete, photos aren't purged until `finalizeDelete()` is called (after the undo window passes), so undo can restore them.
- **Reschedule undo** is also supported: `undoReschedule(_ changes:)` resets the moved reminders back to their old dates.

### Sync Conflict Resolution
**Rule: Local `updatedAt` > Server `updatedAt` → use local; else use server.**
- **Example:** user adds a reminder at 10:00 AM, closes the app, opens it 5 minutes later.
  - Local `updatedAt` = 10:00:05 (just added).
  - Server `updatedAt` = 10:00:00 (not yet synced).
  - Local is newer → local wins, push it to server.
- **Example 2:** user opens the app, server has a newer blob (added on the web app 1 minute ago).
  - Local `updatedAt` = 9:59:00 (stale).
  - Server `updatedAt` = 10:00:00.
  - Server is newer → discard local changes, use server.

### Biometric Lock (Face ID / Touch ID)
- Use `LocalAuthentication.LAContext().evaluatePolicy(.deviceOwnerAuthentication)`.
- **Gotcha:** concurrent Face ID prompts jam up iOS. Use a guard flag so only one prompt runs at a time.
- **Another gotcha:** a vertical-axis `TextField` inside a `ScrollView` won't focus on iPhone (works on Mac). Use a plain single-line field + a simultaneous tap gesture to force focus.

### Notifications
```swift
// Schedule a notification for a reminder's dueDate
func scheduleNotification(for reminder: Reminder) {
    let trigger = UNCalendarNotificationTrigger(
        matching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                 from: reminder.dueDate),
        repeats: false)
    let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

// On reminder complete, remove the notification
UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
```

### Asset Storage
- **Images / attachments:** store locally in `Documents/<entity-id>/` (not in the cloud blob, too large).
- **Links in the blob:** just store the file URL as a string in the reminder's JSON.
- **On delete:** remove the file + the URL reference in one transaction.

---

## Common Gotchas & Fixes

| Problem | Cause | Fix |
|---------|-------|-----|
| **Title field won't focus on iPhone (works on Mac)** | `TextField(axis: .vertical)` inside `ScrollView` is a SwiftUI bug on iOS. | Use plain `TextField(text:)` (single-line). If multi-line needed, add `@FocusState` + `.simultaneousGesture(TapGesture().onEnded { focused = true })`. |
| **Face ID glitches / gets stuck on app open** | Multiple concurrent `LAContext.evaluatePolicy` calls (scene inactive→active handler fires while first prompt is pending). | Add `isAuthenticating` guard flag; only one prompt runs at a time. |
| **Scrolling is glitchy** | Per-card `DragGesture` competes with `ScrollView` pan. | Don't use swipe-to-delete drag gestures. Use long-press context menu or edit sheet instead. |
| **Store churn drops keyboard focus** | 15s refresh loop sets `syncState` on every poll, triggering re-renders of the edit sheet. | Guard `setSync()` to only publish if state actually changes. Also pause the poll while edit sheets are open. |
| **"Excessive I/O" Xcode warning** | Computed properties calling `FileManager.createDirectory` on every access (e.g., `backupDir` called on every sync). | Use `lazy var` or `static let` with a closure to create the directory once. |
| **Reminders lost after Apple Reminders edit** | Apple-completed routine bypasses your advance logic; the routine dies. | Extract advance logic into a helper; call it after Apple syncs in a completed routine. |
| **7-day signing profile doesn't reset on reinstall** | `xcodebuild` reuses a cached provisioning profile. | Delete cached profiles in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` before building. |
| **App can't launch after 7 days** | Free Apple Developer profile expires (free team, 7 days max). | Reinstall the app every ~5 days to reset the clock; or pay for a real team (removes the 7-day limit). |

---

## Deployment

### Free-Signing (7-day cycle)
- **No paid Apple Developer account needed.**
- Use Xcode's "Automatically manage signing" with your personal Apple ID.
- The app will stop launching after 7 days (OS enforcement); reinstall to reset.
- **Script it:** create a `reinstall_app.sh` that:
  1. Deletes cached provisioning profiles.
  2. Builds + installs to iPhone + Mac.
  3. Resets the 7-day clock.

### Testing MUST be on iPhone
- **Mac Catalyst is fast to test locally, but it hides iPhone-only bugs.**
  - Vertical TextField focus issue? Invisible on Mac, crashes on iPhone.
  - Face ID prompt? Only on iPhone (Mac uses passcode prompt).
  - Touch interactions? Different on iPhone vs trackpad.
- **Workflow:** after every change, run your reinstall script to push to both iPhone + Mac, then test the feature on iPhone (not just compile for Mac).

### Making a Widget
- **Separate target** in the project (`MyAppWidgets`).
- **Shared code:** use the `Shared/` folder for models + data access.
- **Widget can't edit** (read-only snapshot). If you need to e.g. tick off a reminder from the widget, use `AppIntents` to send an action → the app handles it.
- **Home Screen + Lock Screen:** separate widget kinds. Lock Screen is tiny (compact layout), Home Screen is flexible.

---

## Development Workflow

### Daily Loop
1. Make a change to a Swift file.
2. Run `./reinstall_app.sh` (or equivalent).
3. **Test on iPhone** (not just Mac).
4. Commit to git.

### Before Shipping
- [ ] Compile: `xcodebuild -project ios/MyApp/MyApp.xcodeproj -scheme MyApp -destination 'platform=macOS,variant=Mac Catalyst' build` (catches Swift errors).
- [ ] Run on iPhone: test the golden path + edge cases (offline, interrupted sync, stale profile, etc.).
- [ ] Check backups exist + restore works.
- [ ] Verify notifications fire on time.
- [ ] Test Face ID unlock flow.
- [ ] If you have widgets: test quick-add from the widget, verify the app opens correctly.

### Release Checklist
- [ ] Bump version in Info.plist.
- [ ] Write release notes (for you; you're not shipping to the App Store).
- [ ] Reinstall fresh on iPhone: make sure the 7-day clock is reset (backup + reinstall from scratch).
- [ ] Tag the commit: `git tag v1.0 && git push origin main --tags`.

---

## Debugging Tips

### Supabase Sync Issues
- Check the cloud blob directly: log into Supabase console, view the row, see the `data` JSON.
- Compare local vs cloud `updatedAt` timestamps.
- If stuck in a conflict loop, manually reset the server blob via Supabase console (careful!).

### Notification Issues
- Check `UNUserNotificationCenter.current().getPendingNotificationRequests { print($0) }` in the debugger.
- Verify the app has notification permission: Settings → [Your App] → Notifications = ON.
- On iPhone, don't silence notifications (mute switch) while testing; they won't fire.

### EventKit Sync (Apple Reminders)
- Check `EKEventStore.changedReminders(since:)` to see what Apple changed.
- Verify your reminder's `externalURL` is set so Apple knows it's linked to your app.
- If a reminder gets duplicated, you're likely syncing twice; add a dedupe check.

---

## File Sizing & Performance

- **Blob size:** ~100 KB JSON per 500 reminders is typical. At 5,000 reminders you're looking at ~1 MB (acceptable).
- **Startup:** reading + decoding the blob takes ~100–500 ms depending on size. OK for an app launch.
- **Sync frequency:** 15s polling is fine for a personal app. If the blob exceeds 10 MB, switch to a per-item API.

---

## Resources

- **Apple docs:** [SwiftUI](https://developer.apple.com/xcode/swiftui/), [EventKit](https://developer.apple.com/documentation/eventkit), [LocalAuthentication](https://developer.apple.com/documentation/localauthentication), [WidgetKit](https://developer.apple.com/documentation/widgetkit).
- **Supabase docs:** [Swift SDK](https://github.com/supabase/supabase-swift), [RLS](https://supabase.com/docs/guides/auth/row-level-security).
- **Nudge source:** [`/Users/noahflouty/Claude/nudge/ios/Nudge/`](../ios/Nudge/) — reference implementation.

---

## Example: Building "StudyTrack" as a Native App

You'd follow this structure:
```
studytrack/
├── ios/StudyTrack/
│   ├── StudyTrack.xcodeproj
│   ├── StudyTrack/          # iOS views (SessionListView, TimerView, StatsView, etc.)
│   ├── StudyTrackWidgets/   # Study timer widget for Home Screen
│   ├── Shared/              # Models (Session, Goal, Tag), sync helpers
│   └── Info.plist
├── web/
│   └── index.html           # PWA with the same data
└── NATIVE_APP_GUIDE.md
```

**Differences from Nudge:**
- **Timer widget:** StudyTrack's Lock Screen widget would show a live timer (Nudge has quick-add, simpler).
- **Notifications:** on-the-hour focus check-in ("hey, study for 25 min") instead of reminder alerts.
- **Sync scope:** per-session (smaller blobs) vs per-reminder; choose based on how often you edit.
