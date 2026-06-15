// Supabase Edge Function: limit-advisor
// ------------------------------------------------------------------
// Friendly, intelligent coach for the ¥1,030,000 tax-free limit. The app sends
// the numbers (earned so far, room left, months left, hourly wage) plus the
// shifts the user is thinking of working, and Claude returns a plain-English
// verdict + advice on whether to work more, less, or just right.
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

const PROMPT = (ctx: Record<string, unknown>) => `You are a sharp, encouraging money coach for a 16-year-old part-time worker in Japan. They must stay under the ¥1,030,000 annual tax-free limit (going over costs them and their family in tax/dependent status). All amounts are yen.

Their situation right now:
- Annual tax-free limit: ¥${ctx.annualLimit}
- Earned so far this year (taxable, incl. paid leave): ¥${ctx.earnedSoFar}
- Room left before the limit: ¥${ctx.roomLeft}
- Months left in the year (including the one they're planning): ${ctx.monthsLeft}
- Steady pace to use the rest evenly: ¥${ctx.safePerMonthYen}/month (~${ctx.safePerMonthHours} hours/month at ¥${ctx.hourlyWage}/hr)

The shifts they're thinking of working this month:
${ctx.shiftLines || "(none entered)"}
- That totals ${ctx.plannedHours} hours = ¥${ctx.plannedPay} this month.
- If they worked roughly this much every remaining month, they'd finish the year at about ¥${ctx.projectedYearEnd}.

Decide the verdict:
- "yes" = comfortably fine this month and sustainable.
- "caution" = doable but above their steady pace, so they'd need lighter months later.
- "over" = this pushes them toward or past the limit; they should cut back.

Then give a short headline (the bottom line in plain words, e.g. "Yes — you can work these and still have room"), 1-2 sentences of reasoning with the key numbers, and 2-4 concrete suggestions (e.g. add/drop a specific shift, how many more hours they could safely add this month, or how to rebalance). Be warm, specific, and brief. Output strictly matches the JSON schema.`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "Server is missing the ANTHROPIC_API_KEY secret." }, 500);

  let ctx: Record<string, unknown>;
  try { ctx = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }

  const client = new Anthropic({ apiKey });
  try {
    // Haiku 4.5: fast + cheap, plenty for this numeric-reasoning + advice task.
    const stream = client.messages.stream({
      model: "claude-haiku-4-5",
      max_tokens: 1200,
      thinking: { type: "disabled" },
      output_config: { format: { type: "json_schema", schema: SCHEMA } },
      messages: [{ role: "user", content: PROMPT(ctx) }],
    });
    const msg = await stream.finalMessage();
    const text = (msg.content.find((b: { type: string }) => b.type === "text") as { text?: string } | undefined)?.text;
    if (!text) return json({ error: "No analysis returned" }, 502);
    return json({ ok: true, data: JSON.parse(text) }, 200);
  } catch (e) {
    return json({ error: "Anthropic request failed: " + (e instanceof Error ? e.message : String(e)) }, 502);
  }
});
