# Claude Code Prompt — Debug the missing Estimated Pay on Wage tab (iOS/macOS)

## Context (read first, don't re-investigate what's already ruled out)

On the **native iOS/macOS SwiftUI app**, the Wage tab shows **transport-only** amounts for unlogged months (e.g. August ¥11,000, September ¥15,400) with **no "Estimated Pay" label** and **no wage portion**. The web app works correctly with identical logic. The app HAS already been reinstalled from the latest commit, so this is NOT a stale-binary issue.

Static analysis in Cowork verified every function in the path is correct on paper:
- `Finance.swift`: `estimatedPay(_:)`, `estHours(_:_:)`, `shiftHours(_:)`, `shifts(_:)`, `dayState(...)`, `jsDay(...)`
- `BudgetStore.swift`: `setShift(...)` writes to `blob.settings["shifts"]` keyed `"0"/"1"/"2"`
- `SettingsView.swift`: shift editor reads the same numeric-string keys `["1","2","0"]`
- `WageView.swift`: `showEst`, the "Estimated Pay" label (line ~72), and `estimatedPayCard` (line ~164) are all wired

The Settings screen on-device correctly shows Mon 7h, Tue 3h, Sun 5.5h — so shift data exists and `shiftHours` works there. Yet the Wage estimate computes wage = 0. The source and the observed behavior contradict each other. **We need one runtime readout to break the deadlock — do not keep re-reading source; add instrumentation and RUN it.**

## Your task

1. **Confirm the working tree** is on `main` at the latest commit (`b1f69c3` or newer) and clean:
   ```
   git -C . log --oneline -3
   git -C . status --short
   ```
   If there are uncommitted changes you didn't make, STOP and report before touching anything.

2. **Add a temporary debug print** inside `estimatedPay(_:)` in `ios/Budget/Shared/Finance.swift`, right before the `return` statement. Print the month key, the previous month key, and every intermediate value:
   ```swift
   print("EST[\(mk)] pmk=\(pmk) hours=\(hours) noShift=\(noShift) days=\(days) wageEst=\(wageEst) transportEst=\(transportEst) hourlyWage=\(hourlyWage) shiftKeys=\(Array(sh.keys).sorted())")
   ```
   This tells us at runtime which case we're in:
   - `hours=0, noShift>0` → the shift lookup is missing at runtime (data/key problem despite source looking right)
   - `shiftKeys` empty or unexpected → `shifts(pmk)` isn't returning the schedule
   - `hours≈69` but the card still doesn't render → the bug is in `WageView`, not the calc

3. **Build and run** the macOS target (fastest to read console). Open the Wage tab so the unlogged months render, which triggers `estimatedPay`. Capture the `EST[...]` console lines for at least August and September.

4. **Report back to Noah** with the exact printed values. Do NOT attempt a fix yet — just report the numbers. The values tell us exactly which of the three cases it is, and the fix follows from that.

5. **Remove the debug print**, leave the working tree exactly as it was (no committed debug code). Confirm `git status` is clean again.

## Rules (Noah's standing project instructions)
- Safety & security first. This debug line only prints wage math — never print or log API keys, tokens, or secrets.
- Do NOT change any calculation or budget logic in this pass. This is diagnosis ONLY.
- Do NOT commit the debug print. It must be removed before you finish.
- If the build fails to compile (the Swift was only static-checked in Cowork this session, never compiled), report the exact compiler errors to Noah — that itself may be the root cause and is a real fix we'd then make.
- After you finish, **remove any stale git locks** (`.git/index.lock`, `.git/*.lock`) if present, so the next session runs cleanly.
- Report back what you found and what you understand before making any further change.
