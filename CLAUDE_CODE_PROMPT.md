# Claude Code — Commit, Deploy & Push Prompt (2026-07-15)

Cowork could NOT commit this session — `.git/index.lock` exists and is not
removable from the Cowork sandbox (permission-restricted on that mount). One
piece of work is staged and waiting: a follow-up chat on the Limit page's
Claude shift advisor. Please commit, deploy, and push from your side.

## Steps

1. From the repo root (`~/Claude/finance-tracker`), clear any stale lock first:
   ```
   rm -f .git/index.lock
   ```
2. Review the diff before committing:
   ```
   git status
   git diff --stat
   ```
   Expect changes in exactly these 4 files (already staged from the Cowork
   session, but verify):
   - `app.html`
   - `ios/Budget/Budget/BudgetStore.swift`
   - `ios/Budget/Budget/LimitView.swift`
   - `supabase/functions/limit-advisor/index.ts`

3. Commit:
   ```
   git add app.html ios/Budget/Budget/BudgetStore.swift ios/Budget/Budget/LimitView.swift supabase/functions/limit-advisor/index.ts CLAUDE_CODE_PROMPT.md
   git commit -m "Add follow-up chat to Limit page shift advisor (web + iOS)

After the first structured verdict (yes/caution/over), a chat thread now
appears below it so you can ask follow-up questions ('what if I drop the
Saturday shift?') and get contextual replies from Claude, instead of only
one-shot advice.

limit-advisor edge function: now accepts optional history[]/message params.
When present, skips the JSON-schema output and replies in free-form text,
using the same financial context (limit, earned, shifts, wage) plus
Estimated Pay for upcoming unlogged months (reuses the Wage tab's
gEstPay/estimatedPay logic, arrears convention). History capped at last 20
turns to bound token cost. No history/message present = unchanged behavior
(structured verdict card).

Web (app.html): chat thread + input below the verdict card. Messages
persisted to localStorage for 1 day only, per-device, cleared automatically
on expiry or when a new shift plan is submitted. 'Clear chat' button.

iOS (LimitView.swift + BudgetStore.swift): same UX in SwiftUI. New
BudgetStore.limitChatReply() calls the same edge function with history.
Messages persisted via new LimitChatStore (UserDefaults, 1-day TTL).

No new Supabase tables — chat history is a local scratchpad only, not
synced across devices or stored server-side, matching the low-stakes nature
of 'thinking out loud about shifts' vs. actual financial records."
   ```

4. Deploy the edge function:
   ```
   supabase functions deploy limit-advisor
   ```
   Confirm the `ANTHROPIC_API_KEY` secret is still set — this change doesn't
   touch secrets, but worth a sanity check:
   ```
   supabase secrets list
   ```

5. Push:
   ```
   git push origin main
   ```

6. After push, clear any leftover locks so the next session is smooth:
   ```
   rm -f .git/*.lock .git/refs/**/*.lock 2>/dev/null; true
   ```

7. Report back: commit hash, deploy result, push result.

## What changed, in more detail

**Edge function (`supabase/functions/limit-advisor/index.ts`):**
Backward compatible. A request with no `history`/`message` behaves exactly
as before — returns the structured `{verdict, headline, reasoning,
suggestions}` JSON. A request with `history` (prior `{role, content}` turns)
and `message` (the new user message) switches to a plain-text conversational
reply (`{reply: "..."}`), using the same situation block (limit, earned,
room left, shifts, plus a new optional `estimateLines` block for upcoming
months' estimated pay). History is trimmed to the last 20 turns and each
message capped at 4000 chars to keep token usage predictable.

**Web (`app.html`):**
- New state: `chatMsgs`, `chatInput`, `chatLoading`, `chatErr`, `limitCtx`.
- New module-level helpers: `loadLimitChat`/`saveLimitChat` — localStorage
  key `limitChat_v1`, 1-day TTL, per-device only.
- New `buildEstimateLines()` — pulls `gEstPay(mo.key)` for each future month
  (same function already powering the Wage tab's Estimated Pay card).
- `askLimitAdvisor` now also stores the full `ctx` object (as `limitCtx`) and
  clears any existing chat thread (new shift plan = new numbers, don't let
  Claude answer follow-ups against stale context).
- New `sendLimitChat()` — posts `{...limitCtx, history: chatMsgs, message}`
  to the edge function, appends the reply, persists to localStorage.
- New `clearLimitChat()` — wired to a "Clear chat" link in the UI.
- New chat UI block renders below the existing verdict card, gated on
  `simAdvice` already having a headline/reasoning (i.e., chat only shows
  after the first verdict).

**iOS (`ios/Budget/Budget/LimitView.swift` + `BudgetStore.swift`):**
- `BudgetStore.swift`: new `limitChatReply(ctx:history:message:)` — same
  edge function, same request shape as web, decodes `reply` from the
  response.
- `LimitView.swift`: new `@State` for `chatMsgs`, `chatInput`, `chatLoading`,
  `chatErr`, `limitCtx`. New `buildEstimateLines()` mirroring web's version
  via `store.calc.estimatedPay(mo.key)`. `runAdvisor` now stores `limitCtx`
  and clears any prior chat. New `sendChat()`/`clearChat()`. New chat UI
  (message bubbles + TextField + Send button) below the existing advice
  card, same gating as web.
- New file-scope types: `LimitChatMessage` (Codable, `{role, content}`) and
  `LimitChatStore` enum — UserDefaults-backed persistence, key
  `limitChat_v1`, 1-day TTL, mirroring the web localStorage behavior.

## Things I could not verify in the Cowork sandbox

- No Supabase CLI available there, so the edge function has NOT been
  deployed yet — it only exists in the local file, not live. Deploying it
  (step 4 above) is required before the chat feature will actually work in
  the app; until then, tapping "Ask Claude for advice" still works as before
  (unchanged first-call behavior), but the chat box's follow-up messages
  will fail against the old deployed version of the function.
- No Xcode/swift build available there either — `LimitView.swift` and
  `BudgetStore.swift` are logic-reviewed and brace/paren-balance-checked
  only, not compiled. Worth a build check before considering this verified.

## After push — test on both platforms

- **Web:** Limit tab → add a shift → "Ask Claude for advice" → verdict card
  appears → a chat box should appear below it → type a follow-up ("what if I
  drop this shift?") → should get a plain-text reply in a few seconds →
  refresh the page within the same day → chat history should still be there
  → "Clear chat" should wipe it.
- **iOS:** same flow in the Limit tab. Force-quit and reopen the app within
  the same day → chat history should persist. Wait past 1 day (or manually
  clear UserDefaults for testing) → history should be gone on next load.
- **Cost sanity check:** each chat message is a new Anthropic API call
  (Haiku 4.5, max 600 tokens) against the existing `ANTHROPIC_API_KEY`
  secret — not unbounded, but confirm nothing loops or double-sends.
