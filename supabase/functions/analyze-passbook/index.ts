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

// Best-effort daily call cap. The app calls this function with the *public*
// anon key (it's in the GitHub Pages source), so anyone could invoke it and
// burn Anthropic credit. This caps total calls/day. It is FAIL-OPEN: any error
// (e.g. the fn_usage table not existing yet) simply lets the request through,
// so the feature never breaks — the cap just won't be enforced until the table
// exists. One-time setup SQL (run in Supabase SQL editor):
//   create table if not exists fn_usage (day date primary key, count int not null default 0);
const DAILY_CAP = 15;
async function underDailyCap(): Promise<boolean> {
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) return true; // can't check → allow
    const day = new Date().toISOString().slice(0, 10);
    const h = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
    const r = await fetch(`${url}/rest/v1/fn_usage?day=eq.${day}&select=count`, { headers: h });
    if (!r.ok) return true; // table missing / error → allow
    const rows = await r.json();
    const count = (rows[0] && rows[0].count) || 0;
    if (count >= DAILY_CAP) return false;
    await fetch(`${url}/rest/v1/fn_usage`, {
      method: "POST",
      headers: { ...h, Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({ day, count: count + 1 }),
    });
    return true;
  } catch {
    return true; // never block legitimate use on an internal error
  }
}

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

// Mode B — insights only, over already-extracted transactions (no re-extraction).
const INSIGHTS_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    categories: (SCHEMA as { properties: Record<string, unknown> }).properties.categories,
    recurring: (SCHEMA as { properties: Record<string, unknown> }).properties.recurring,
    summary: (SCHEMA as { properties: Record<string, unknown> }).properties.summary,
    anomalies: (SCHEMA as { properties: Record<string, unknown> }).properties.anomalies,
    budget_matches: (SCHEMA as { properties: Record<string, unknown> }).properties.budget_matches,
    suggestions: (SCHEMA as { properties: Record<string, unknown> }).properties.suggestions,
    insights: (SCHEMA as { properties: Record<string, unknown> }).properties.insights,
  },
  required: ["categories", "recurring", "summary", "anomalies", "budget_matches", "suggestions", "insights"],
};

const INSIGHTS_PROMPT = (budgetContext: string, txText: string) => `You are a friendly, sharp personal-finance coach for a 16-year-old part-time worker in Japan. Below is their full transaction history (already extracted from their bank passbook), one per line as: DATE | +/-AMOUNT | CATEGORY | DESCRIPTION. Amounts are in yen.

Analyse the WHOLE picture across all months and produce:
- categories: per-category spending totals ("out" only) with counts, biggest first.
- recurring: subscriptions or repeating bills you can spot; short note each.
- summary: total in, total out, net, savings_rate_pct = round(net / income_total * 100) (0 if no income).
- anomalies: unusual or wasteful spending — spikes, likely duplicate charges, ATM/bank fees, creeping habits. Explain why in "reason".
- budget_matches: reconcile against the budget below. status ∈ "matched" / "missing_from_app" (spent but not tracked) / "not_seen" (tracked but no spending found).
- suggestions: 3-6 concrete, encouraging, actionable recommendations tailored to a teen saver (specific yen amounts where possible).
- insights: 3-6 short plain-English observations about their spending habits and trends over time.

Be specific and genuinely useful. Output strictly matches the provided JSON schema.

The user's budget tracked in their app:
${budgetContext || "(none provided)"}

Transactions:
${txText}`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: {
    fileBase64?: string;
    mediaType?: string;
    budgetContext?: string;
    transactions?: Array<Record<string, unknown>>;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const { fileBase64, mediaType, budgetContext, transactions } = body;
  // Mode A = file upload (extract + analyse). Mode B = insights-only over given transactions.
  const insightsMode = Array.isArray(transactions) && transactions.length > 0;
  if (!insightsMode && (!fileBase64 || !mediaType)) {
    return json({ error: "Missing fileBase64/mediaType (or a transactions array)" }, 400);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return json(
      { error: "Server is missing the ANTHROPIC_API_KEY secret. Set it in Supabase -> Edge Functions -> Secrets." },
      500,
    );
  }

  if (!(await underDailyCap())) {
    return json({ error: "Daily scan limit reached — please try again tomorrow." }, 429);
  }

  const client = new Anthropic({ apiKey });

  try {
    let content: unknown[];
    let schema: unknown;
    if (insightsMode) {
      // Mode B: analyse already-extracted transactions, no file.
      const txText = (transactions as Array<Record<string, unknown>>)
        .map((t) => `${t.date} | ${t.direction === "in" ? "+" : "-"}${t.amount} | ${t.category} | ${t.description}`)
        .join("\n");
      schema = INSIGHTS_SCHEMA;
      content = [{ type: "text", text: INSIGHTS_PROMPT(budgetContext || "", txText) }];
    } else {
      const isPdf = mediaType === "application/pdf";
      const mediaBlock = isPdf
        ? { type: "document", source: { type: "base64", media_type: "application/pdf", data: fileBase64 } }
        : { type: "image", source: { type: "base64", media_type: mediaType, data: fileBase64 } };
      schema = SCHEMA;
      content = [mediaBlock as never, { type: "text", text: PROMPT(budgetContext || "") }];
    }
    // Speed: disable thinking in both modes (adaptive thinking was the main
    // latency cost, and extraction/insight quality holds without it). Mode A
    // (passbook OCR/extraction) stays on Sonnet for vision accuracy but at
    // effort "low"; Mode B (insights over already-extracted text) drops to
    // Haiku 4.5 — much faster and cheaper, and plenty for summarising text.
    // Note: Haiku 4.5 does NOT accept the `effort` param (400s), so only set
    // it for Sonnet.
    const outputConfig: Record<string, unknown> = { format: { type: "json_schema", schema } };
    if (!insightsMode) outputConfig.effort = "low";
    // Stream server-side so long reads keep the upstream connection alive
    // (avoids idle-timeout drops); we still return one JSON blob to the client.
    const stream = client.messages.stream({
      model: insightsMode ? "claude-haiku-4-5" : "claude-sonnet-4-6",
      max_tokens: 16000,
      thinking: { type: "disabled" },
      output_config: outputConfig as never,
      messages: [
        { role: "user", content: content as never },
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
