# Prompt for Claude Code

You're working in the `finance-tracker` repo (Budget App — web PWA `app.html`/`index.html`
which must stay byte-identical mirrors, plus a native SwiftUI app under `ios/Budget/`).

Before starting, read these two handoff docs in the repo root and confirm back to me your
understanding of each task before changing anything:

- `HANDOFF_2026-07-04_cowork.md` — what a prior Cowork session did (card reordering) and the
  bug-sweep status.
- `NOTIFICATIONS_HANDOFF.md` — diagnosis + full spec for fixing/porting the native
  notifications.

Repo rules: after any edit to `app.html`, run `cp app.html index.html`. Native logic lives
only under `ios/Budget/` (no shared source with web). The `.git` folder is sometimes shared
with a sandbox — if you hit an `index.lock` / lock error, tell me instead of forcing past
it. Put safety first; don't guess — if unsure, say so and check.

## Task A — Build & verify the native card-reordering (already written, NOT yet compiled)
The prior session added Budget-tab card reordering to both web (verified) and native (not
build-tested — no Swift toolchain was available). The native changes are in
`ios/Budget/Shared/Models.swift`, `ios/Budget/Budget/BudgetStore.swift`, and
`ios/Budget/Budget/BudgetTabView.swift` (a `cardOrder` synced field, `moveCards`, an
order-driven `ForEach(store.cardOrder)` render, and a "Reorder cards" sheet using a List in
EditMode with `.onMove`). Build in Xcode, fix any compile errors, and confirm reordering
works and syncs with the web app. Report anything you had to change.

## Task B — Fix the native notifications
Follow `NOTIFICATIONS_HANDOFF.md`. First confirm the root cause with the on-device check it
describes (toggle on → "Send test notification"), then implement: (1) the
denied-permission feedback, and (2) port the 8 missing notifications (date-based ones into
`schedule()`, state-based ones evaluated at launch/foreground with the de-dup described).
Match the web titles/bodies. Build and test in Xcode before committing.

## Task C — Commit & push (the Cowork session could not — git was locked)
There are uncommitted changes from the Cowork session in the working tree:
- Web reorder: `app.html`, `index.html`
- Native reorder: `ios/Budget/Budget/BudgetStore.swift`, `ios/Budget/Budget/BudgetTabView.swift`, `ios/Budget/Shared/Models.swift`
- New docs: `HANDOFF_2026-07-04_cowork.md`, `NOTIFICATIONS_HANDOFF.md`, `CLAUDE_CODE_PROMPT.md`

First check for and clear any stale `.git/index.lock` (only if no git process is actually
running). Then commit in logical chunks with clear messages and push. Suggested split:
1. `Budget tab: rearrangeable cards (web + native, synced order)` — the 5 code files.
2. `docs: add 2026-07-04 session + native notifications handoffs` — the md files.
3. A separate commit for your notification fix once it builds.

Confirm your understanding of A, B, and C before you start.
