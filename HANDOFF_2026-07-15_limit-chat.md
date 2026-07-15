# Handoff — Limit page follow-up chat (2026-07-15)

## What was asked
Noah wanted to be able to chat back to Claude in the same box where it tells
him what shifts he can work (Limit page shift advisor) — turning the
one-shot "Ask Claude for advice" verdict into a real back-and-forth
conversation.

## Decisions made (confirmed with Noah before building)
- Keep the structured verdict card as-is; chat appears **below** it after
  the first verdict, not replacing it.
- Chat context = same Limit-page numbers (limit, earned, shifts, wage) PLUS
  Estimated Pay for future/unlogged months, reusing the existing Estimated
  Pay logic (Wage tab feature, logged 2026-07-15) — no duplicate logic.
- Persistence: **local device storage only**, **1 day** TTL. No Supabase
  table, no cross-device sync. Noah asked "is local better?" — answered yes:
  this is a scratchpad for thinking out loud about shifts, not a financial
  record, so the sync/schema overhead of Supabase wasn't worth it. Tradeoff
  (chat doesn't follow you between web and iOS) was explicitly accepted.

## What was built
1. **`supabase/functions/limit-advisor/index.ts`** — extended to accept
   optional `history[]` + `message`. Backward compatible: no history/message
   → identical behavior to before (structured JSON verdict). With them →
   free-form conversational text reply. History capped at last 20 turns,
   4000 chars/message, to bound Anthropic API cost.
2. **`app.html`** — chat thread + input below the verdict card.
   localStorage-persisted (`limitChat_v1`, 1-day TTL). New shift-plan verdict
   clears old chat. "Clear chat" button included.
3. **`ios/Budget/Budget/LimitView.swift`** + **`BudgetStore.swift`** — same
   UX in SwiftUI. New `BudgetStore.limitChatReply()`, new
   `LimitChatStore` (UserDefaults, 1-day TTL) + `LimitChatMessage` type.

Full technical detail is in `CLAUDE_CODE_PROMPT.md` (also serves as the
deploy/push instructions for this session).

## What's NOT done yet — blockers
- **Edge function not deployed.** No Supabase CLI in the Cowork sandbox.
  The chat feature will not work until `supabase functions deploy
  limit-advisor` is run from Noah's machine.
- **Not committed/pushed.** Hit the known shared-repo git lock collision
  (`.git/index.lock`, permission-denied to remove from sandbox) — see
  memory `git-shared-repo-collision.md`. All 4 changed files are staged
  in the sandbox's working copy but the commit itself needs to happen from
  Noah's terminal.
- **Not compiled/tested.** No Xcode or JS runtime available in the sandbox
  to actually build/run either app. Swift files were brace/paren-balance
  checked only; web JS was brace/paren-balance checked only. Real
  verification (build + manual test on both platforms) is still needed.

## Next steps for Noah / next session
1. Run the `CLAUDE_CODE_PROMPT.md` instructions in Claude Code: clears the
   lock, commits, deploys the edge function, pushes, cleans up locks again.
2. Build + test on iOS (Xcode) — this session could not verify Swift
   compiles.
3. Manually test the chat flow end-to-end on web once deployed: ask a
   follow-up question, confirm a real reply comes back (not an error),
   confirm it survives a page refresh same-day, confirm "Clear chat" works.
4. Same manual test pass on iOS after building.

## Files touched this session
- `supabase/functions/limit-advisor/index.ts`
- `app.html`
- `ios/Budget/Budget/LimitView.swift`
- `ios/Budget/Budget/BudgetStore.swift`
- `CLAUDE_CODE_PROMPT.md` (overwritten — previous content was a stale prompt
  from the already-merged Estimated Pay session)
