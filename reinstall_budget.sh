#!/bin/bash
# Rebuild + reinstall Budget on iPhone + Mac (resets the free-team 7-day clock).
# Mirrors reinstall_nudge.sh. Pass --interactive for modal dialogs; without it,
# failures come as notifications.
PROJ="/Users/noahflouty/Claude/finance-tracker/ios/Budget"
DEV="73562BAB-DA59-5AB0-A722-8AACE1D8820C"   # Noah's iPhone (same as Nudge)
BUNDLE="uk.flouty.Budget"
INTERACTIVE=0; [ "$1" = "--interactive" ] && INTERACTIVE=1

notify()  { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"$3\"" >/dev/null 2>&1; }
report()  {
  if [ "$INTERACTIVE" = "1" ]; then
    /usr/bin/osascript -e "display dialog \"$2\" with title \"$1\" buttons {\"OK\"} default button 1 with icon caution" >/dev/null 2>&1
  else notify "$1" "$2" "Basso"; fi
}

# ---------- Preflight / connectivity check ----------
echo "[$(date '+%H:%M')] Checking everything's ready…"
P=""
if ! security find-identity -p codesigning -v 2>/dev/null | grep -q "Apple Development"; then
  P="${P}• Xcode isn't signed in — open Xcode ▸ Settings ▸ Accounts and add your Apple ID.
"
fi
if [ "$(defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null | grep -c 'identifier =')" -eq 0 ]; then
  P="${P}• No Apple ID in Xcode — open Xcode ▸ Settings ▸ Accounts, click +, add your Apple ID.
"
fi
if ! xcrun devicectl list devices 2>/dev/null | grep "$DEV" | grep -qiE "connected|available"; then
  P="${P}• iPhone not reachable — unlock it on the same Wi-Fi (or plug it in) and trust this Mac.
"
else
  if xcrun devicectl device info lockState --device "$DEV" 2>/dev/null | grep -qi "passcodeRequired: true"; then
    P="${P}• iPhone is locked — unlock it and keep the screen on.
"
  fi
fi
if [ -n "$P" ]; then
  report "Budget — not ready yet" "Fix these, then click again:

$P"
  echo "Preflight failed:"; printf '%s' "$P"; exit 1
fi
[ "$INTERACTIVE" = "1" ] && notify "Budget" "All set — rebuilding & reinstalling (~1 min)…" "Pop"
echo "Preflight OK."

# ---------- Force a fresh 7-day profile ----------
PROF_BK="$(mktemp -d)"
PRIMARY_PROF="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
for PROF_DIR in "$PRIMARY_PROF" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  [ -d "$PROF_DIR" ] || continue
  for p in "$PROF_DIR"/*.mobileprovision; do
    [ -f "$p" ] || continue
    if security cms -D -i "$p" 2>/dev/null | grep -qi "flouty"; then
      mv "$p" "$PROF_BK/"; echo "Set aside profile $(basename "$p")"
    fi
  done
done
restore_profiles() { mkdir -p "$PRIMARY_PROF"; cp "$PROF_BK"/*.mobileprovision "$PRIMARY_PROF/" 2>/dev/null; }

# ---------- iPhone ----------
cd "$PROJ" || { report "Budget reinstall failed" "Project folder not found."; exit 1; }
if ! ( set -o pipefail; xcodebuild -project Budget.xcodeproj -scheme Budget -destination 'generic/platform=iOS' -allowProvisioningUpdates build 2>&1 | tail -6 ); then
  restore_profiles
  report "Budget reinstall failed" "iPhone build/signing failed. Open Xcode ▸ Settings ▸ Accounts and make sure your Apple ID is added, then click again."
  echo "iPhone build FAILED — not installing (would be a stale app)."; exit 1
fi
rm -rf "$PROF_BK"
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/Budget-"*/Build/Products/Debug-iphoneos -maxdepth 1 -name Budget.app 2>/dev/null | head -1)
[ -z "$APP" ] && { notify "Budget reinstall failed" "No iPhone build output." "Basso"; exit 1; }
OUT=$(xcrun devicectl device install app --device "$DEV" "$APP" 2>&1); echo "$OUT" | tail -2
if echo "$OUT" | grep -qiE "installed|databaseUUID"; then
  xcrun devicectl device process launch --terminate-existing --device "$DEV" "$BUNDLE" >/dev/null 2>&1
  echo "iPhone reinstalled."
else
  notify "Budget reinstall failed" "Install failed — unlock & reconnect your iPhone, then click again." "Basso"; exit 1
fi

# ---------- Mac (Catalyst) ----------
# Sign the Mac build properly (Apple Development identity) — NOT ad-hoc — so macOS
# lets the app register for notifications (ad-hoc Catalyst builds are silently blocked).
if xcodebuild -project Budget.xcodeproj -scheme Budget -destination 'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates build 2>&1 | tail -3; then
  MACAPP=$(find "$HOME/Library/Developer/Xcode/DerivedData/Budget-"*/Build/Products/Debug-maccatalyst -maxdepth 1 -name Budget.app 2>/dev/null | head -1)
  if [ -n "$MACAPP" ]; then
    # Install ONE canonical copy into /Applications and always open that — so the Dock
    # icon is stable and we never spawn a second "version" from a temp build folder.
    pkill -x Budget >/dev/null 2>&1; sleep 1
    rm -rf "/Applications/Budget.app"
    cp -R "$MACAPP" "/Applications/Budget.app"
    # Remove the DerivedData build copy + its LaunchServices registration so it doesn't
    # show up as a duplicate "Budget" in Launchpad/Spotlight.
    LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    [ -x "$LSREG" ] && "$LSREG" -u "$MACAPP" >/dev/null 2>&1
    rm -rf "$MACAPP"
    /usr/bin/open "/Applications/Budget.app"
  fi
  echo "Mac refreshed (/Applications/Budget.app)."
else
  notify "Budget Mac refresh failed" "The Mac app couldn't rebuild." "Basso"
fi
notify "Budget" "✅ Reinstalled on iPhone + Mac — 7-day clock reset." "Glass"
echo "[$(date '+%H:%M')] Done."
