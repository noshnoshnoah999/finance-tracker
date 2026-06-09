// Supabase Edge Function: analyze-passbook
// ------------------------------------------------------------------
// Secure proxy between the static finance-tracker app and the Anthropic
// API. The ANTHROPIC_API_KEY secret lives here (server-side) and is never
// shipped to the browser, so it can't be scraped from the public site.
//
// Deploy:
//   1. Supabase Dashboard -> Edge Functions -> Deploy a new function
//      named "analyze-passbook", paste this file.
//   2. Project Settings -> Edge Functions -> Secrets:
//         ANTHROPIC_API_KEY = sk-ant-...your key...
//   (CLI equivalent: `supabase functions deploy analyze-passbook`
//    then `supabase secrets set ANTHROPIC_API_KEY=sk-ant-...`)
// ------------------------------------------------------------------
import Anthropic from "npm:@anthropic-ai/sdk";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

// Structured-output schema — guarantees clean JSON we can render in-app.
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    currency: { type: "string" },
    period: {
      type: "object",
      additionalProperties: false,
      properties: { start: { type: "string" }, end: { type: "string" } },
      required: ["start", "end"],
    },
    transactions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          date: { type: "string" },
          description: { type: "string" },
          amount: { type: "number" },
          direction: { type: "string", enum: ["in", "out"] },
          category: {
            type: "string",
            enum: [
              "income", "food", "transport", "subscriptions", "shopping",
              "bills", "savings", "investment", "fees", "transfer", "cash", "other",
            ],
          },
        },
        required: ["date", "description", "amount", "direction", "category"],
      },
    },
    categories: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          name: { type: "string" },
          total: { type: "number" },
          count: { type: "integer" },
        },
        required: ["name", "total", "count"],
      },
    },
    recurring: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          description: { type: "string" },
          amount: { type: "number" },
          cadence: { type: "string" },
          note: { type: "string" },
        },
        required: ["description", "amount", "cadence", "note"],
      },
    },
    summary: {
      type: "object",
      additionalProperties: false,
      properties: {
        income_total: { type: "number" },
        spending_total: { type: "number" },
        net: { type: "number" },
        savings_rate_pct: { type: "number" },
      },
      required: ["income_total", "spending_total", "net", "savings_rate_pct"],
    },
    anomalies: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          description: { type: "string" },
          amount: { type: "number" },
          reason: { type: "string" },
        },
        required: ["description", "amount", "reason"],
      },
    },
    budget_matches: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          app_item: { type: "string" },
          passbook: { type: "string" },
          status: { type: "string" },
          amount: { type: "number" },
        },
        required: ["app_item", "passbook", "status", "amount"],
      },
    },
    suggestions: { type: "array", items: { type: "string" } },
    insights: { type: "array", items: { type: "string" } },
  },
  required: [
    "currency", "period", "transactions", "categories", "recurring",
    "summary", "anomalies", "budget_matches", "suggestions", "insights",
  ],
};

const PROMPT = (budgetContext: string) => `You are a meticulous personal-finance analyst. The attached file is a bank passbook / 通帳 / statement (image or PDF), most likely a Japanese bank account belonging to a 16-year-old part-time worker. Japanese passbooks list 年月日 (date), 摘要 (description), お支払金額 (paid out / withdrawal), お預り金額 (deposit / paid in), and 差引残高 (running balance).

Extract EVERY transaction you can read. For each: ISO date (YYYY-MM-DD; infer the year from context), a clean human-readable description (translate Japanese to natural English but keep names/merchants), the amount as a positive number in the account currency, direction ("in" for deposits/income, "out" for withdrawals/spending), and the best-fit category from the allowed enum.

Then produce:
- categories: per-category totals (spending only, "out") with counts, biggest first.
- recurring: payments that look like subscriptions or repeating bills (same/similar payee or amount); for each give a short note (e.g. "looks like a monthly subscription").
- summary: total in, total out, net, and savings_rate_pct = round(net / income_total * 100) (0 if no income).
- anomalies: anything unusual — unusually large charges, possible duplicate/double charges, bank/ATM fees, or one-off spikes. Explain why in "reason".
- budget_matches: reconcile against the user's existing budget below. status is one of "matched", "missing_from_app" (in passbook but not tracked), or "not_seen" (tracked in app but no matching payment found).
- suggestions: concrete, friendly actions (e.g. "Add ¥X 'Netflix' to your Subscribe & Save", "You paid ¥Y in ATM fees — withdraw less often").
- insights: 3-6 short plain-English observations about the spending.

Be accurate; never invent transactions you cannot read. Amounts are whole yen unless decimals are clearly shown. Output strictly matches the provided JSON schema.

The user's current budget tracked in their app:
${budgetContext || "(none provided)"}`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: { fileBase64?: string; mediaType?: string; budgetContext?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const { fileBase64, mediaType, budgetContext } = body;
  if (!fileBase64 || !mediaType) {
    return json({ error: "Missing fileBase64 or mediaType" }, 400);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return json(
      { error: "Server is missing the ANTHROPIC_API_KEY secret. Set it in Supabase -> Edge Functions -> Secrets." },
      500,
    );
  }

  const client = new Anthropic({ apiKey });
  const isPdf = mediaType === "application/pdf";
  const mediaBlock = isPdf
    ? { type: "document", source: { type: "base64", media_type: "application/pdf", data: fileBase64 } }
    : { type: "image", source: { type: "base64", media_type: mediaType, data: fileBase64 } };

  try {
    // Stream server-side so long PDF reads keep the upstream connection alive
    // (avoids idle-timeout drops); we still return one JSON blob to the client.
    const stream = client.messages.stream({
      model: "claude-sonnet-4-6",
      max_tokens: 16000,
      thinking: { type: "adaptive" },
      output_config: { effort: "medium", format: { type: "json_schema", schema: SCHEMA } },
      messages: [
        { role: "user", content: [mediaBlock as never, { type: "text", text: PROMPT(budgetContext || "") }] },
      ],
    });
    const msg = await stream.finalMessage();
    const textBlock = msg.content.find((b: { type: string }) => b.type === "text") as { text?: string } | undefined;
    if (!textBlock?.text) return json({ error: "No analysis returned" }, 502);
    let data: unknown;
    try {
      data = JSON.parse(textBlock.text);
    } catch {
      return json({ error: "Model returned non-JSON", raw: textBlock.text }, 502);
    }
    return json({ ok: true, data, usage: msg.usage }, 200);
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    return json({ error: "Anthropic request failed: " + m }, 502);
  }
});
