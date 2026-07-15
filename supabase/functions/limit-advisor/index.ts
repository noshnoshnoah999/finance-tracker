// Supabase Edge Function: limit-advisor
// ------------------------------------------------------------------
// Friendly, intelligent coach for the ¥1,030,000 tax-free limit. The app sends
// the numbers (earned so far, room left, months left, hourly wage) plus the
// shifts the user is thinking of working, and Claude returns a plain-English
// verdict + advice on whether to work more, less, or just right.
//
// Follow-up chat: if the request includes a non-empty `history` array (prior
// {role, content} turns) plus a `message` string, this is a follow-up question
// in the same conversation — Claude replies in free-form text (no JSON schema)
// using the same financial context from the original request. The first call
// (no history) is unchanged and still returns the structured verdict card.
//
// Secret (Supabase -> Edge Functions -> Secrets): ANTHROPIC_API_KEY
// Deploy:  supabase functions deploy limit-advisor
// ------------------------------------------------------------------
import Anthropic from "npm:@anthropic-ai/sdk";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    verdict: { type: "string", enum: ["yes", "caution", "over"] },
    headline: { type: "string" },          // one short sentence, the bottom line
    reasoning: { type: "string" },         // 1-2 sentences explaining why
    suggestions: { type: "array", items: { type: "string" } }, // 2-4 concrete tips
  },
  required: ["verdict", "headline", "reasoning", "suggestions"],
};

// Shared situation block used by both the first structured verdict and any follow-up chat,
// so Claude always reasons from the same numbers regardless of which mode it's in.
const SITUATION = (ctx: Record<string, unknown>) => `Their situation right now:
- Annual tax-free limit: ¥${ctx.annualLimit}
- Earned so far this year (taxable, incl. paid leave): ¥${ctx.earnedSoFar}
- Room left before the limit: ¥${ctx.roomLeft}
- Months left in the year (including the one they're planning): ${ctx.monthsLeft}
- Steady pace to use the rest evenly: ¥${ctx.safePerMonthYen}/month (~${ctx.safePerMonthHours} hours/month at ¥${ctx.hourlyWage}/hr)

The shifts they're thinking of working this month:
${ctx.shiftLines || "(none entered)"}
- That totals ${ctx.plannedHours} hours = ¥${ctx.plannedPay} this month.
- If they worked roughly this much every remaining month, they'd finish the year at about ¥${ctx.projectedYearEnd}.
${ctx.estimateLines ? `\nEstimated pay for upcoming unlogged months (live-computed from their schedule + calendar, arrears convention — same figures shown on their Wage tab):\n${ctx.estimateLines}` : ""}`;

const PROMPT = (ctx: Record<string, unknown>) => `You are a sharp, encouraging money coach for a 16-year-old part-time worker in Japan. They must stay under the ¥1,030,000 annual tax-free limit (going over costs them and their family in tax/dependent status). All amounts are yen.

${SITUATION(ctx)}

Decide the verdict:
- "yes" = comfortably fine this month and sustainable.
- "caution" = doable but above their steady pace, so they'd need lighter months later.
- "over" = this pushes them toward or past the limit; they should cut back.

Then give a short headline (the bottom line in plain words, e.g. "Yes — you can work these and still have room"), 1-2 sentences of reasoning with the key numbers, and 2-4 concrete suggestions (e.g. add/drop a specific shift, how many more hours they could safely add this month, or how to rebalance). Be warm, specific, and brief. Output strictly matches the JSON schema.`;

const CHAT_SYSTEM = (ctx: Record<string, unknown>) => `You are a sharp, encouraging money coach for a 16-year-old part-time worker in Japan, chatting with them about the ¥1,030,000 annual tax-free limit. They must stay under it (going over costs them and their family in tax/dependent status). All amounts are yen.

You already gave them an initial verdict on the shifts below. Now they're asking follow-up questions in a chat. Use the same numbers to answer — recompute or reason about "what if" scenarios (dropping/adding a shift, a different month, working more or less) using these figures. If a question needs a number you don't have, say so plainly rather than guessing.

${SITUATION(ctx)}

Reply in plain, warm, brief conversational text (2-5 sentences typically, longer only if the question needs it). No JSON, no markdown headers — just a natural chat reply.`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "Server is missing the ANTHROPIC_API_KEY secret." }, 500);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }

  const history = Array.isArray(body.history) ? body.history as { role: string; content: string }[] : [];
  const message = typeof body.message === "string" ? body.message : "";
  const isChat = history.length > 0 || message.length > 0;

  const client = new Anthropic({ apiKey });
  try {
    if (isChat) {
      if (!message) return json({ error: "Missing 'message' for chat follow-up" }, 400);
      // Keep the conversation bounded — last 20 turns is plenty of context for a budgeting chat
      // and keeps token usage (and cost) predictable.
      const trimmedHistory = history.slice(-20).map(h => ({
        role: h.role === "assistant" ? "assistant" as const : "user" as const,
        content: String(h.content || "").slice(0, 4000),
      }));
      const stream = client.messages.stream({
        model: "claude-haiku-4-5",
        max_tokens: 600,
        thinking: { type: "disabled" },
        system: CHAT_SYSTEM(body),
        messages: [...trimmedHistory, { role: "user", content: message }],
      });
      const msg = await stream.finalMessage();
      const text = (msg.content.find((b: { type: string }) => b.type === "text") as { text?: string } | undefined)?.text;
      if (!text) return json({ error: "No reply returned" }, 502);
      return json({ ok: true, reply: text }, 200);
    }

    // Haiku 4.5: fast + cheap, plenty for this numeric-reasoning + advice task.
    const stream = client.messages.stream({
      model: "claude-haiku-4-5",
      max_tokens: 1200,
      thinking: { type: "disabled" },
      output_config: { format: { type: "json_schema", schema: SCHEMA } },
      messages: [{ role: "user", content: PROMPT(body) }],
    });
    const msg = await stream.finalMessage();
    const text = (msg.content.find((b: { type: string }) => b.type === "text") as { text?: string } | undefined)?.text;
    if (!text) return json({ error: "No analysis returned" }, 502);
    return json({ ok: true, data: JSON.parse(text) }, 200);
  } catch (e) {
    return json({ error: "Anthropic request failed: " + (e instanceof Error ? e.message : String(e)) }, 502);
  }
});
