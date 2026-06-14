// Supabase Edge Function: import-bank-emails
// ------------------------------------------------------------------
// Fetches Sony Bank WALLET (Visa debit) "ご利用のお知らせ" emails from a
// Gmail label and parses each into a passbook transaction. The app calls this,
// then merges the returned transactions into the right month (same dedup as the
// passbook importer).
//
// All Gmail credentials live in Supabase secrets — never in the browser:
//   GMAIL_CLIENT_ID       OAuth client id      (Google Cloud console)
//   GMAIL_CLIENT_SECRET   OAuth client secret
//   GMAIL_REFRESH_TOKEN   long-lived refresh token for noah@flouty.uk
//   GMAIL_LABEL_ID        the "Sony Bank Debit Transactions" label id
//                         (Label_936850695158882149)
//
// Setup steps live in BUDGET_NATIVE.md / the chat. Deploy:
//   supabase functions deploy import-bank-emails
// ------------------------------------------------------------------
const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

// Full-width → half-width (Sony writes merchant names in full-width katakana/ASCII).
const toHalf = (s: string) =>
  s.replace(/[！-～]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xFEE0))
   .replace(/　/g, " ").replace(/\s+/g, " ").trim();

// base64url (Gmail message bodies) → UTF-8 string.
function b64urlToText(data: string): string {
  const b64 = data.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder("utf-8").decode(bytes);
}

// Walk the MIME tree for the first text/plain body.
function plainText(payload: any): string {
  if (!payload) return "";
  if (payload.mimeType === "text/plain" && payload.body?.data) return b64urlToText(payload.body.data);
  for (const p of payload.parts || []) {
    const t = plainText(p);
    if (t) return t;
  }
  if (payload.body?.data) return b64urlToText(payload.body.data); // single-part fallback
  return "";
}

// Parse one Sony Bank WALLET usage email into a transaction (or null).
function parseSony(body: string) {
  const d = body.match(/カード利用日[：:]\s*(\d{4})年(\d{1,2})月(\d{1,2})日/);
  const a = body.match(/ご利用金額[：:]\s*(-?[\d,]+)\s*円/);
  if (!d || !a) return null;
  const date = `${d[1]}-${d[2].padStart(2, "0")}-${d[3].padStart(2, "0")}`;
  const raw = Number(a[1].replace(/,/g, ""));            // negative = refund
  const m = body.match(/ご利用加盟店[：:]\s*(.+)/);
  const merchant = m ? toHalf(m[1]) : "Sony Bank WALLET";
  const isSuica = /SUICA|スイカ/i.test(merchant);
  return {
    date,
    description: isSuica ? "Mobile Suica (Apple) top-up" : merchant,
    amount: Math.abs(raw),
    direction: raw < 0 ? "in" : "out",
    category: isSuica ? "transport" : "shopping",
    source: "sony-email",
  };
}

async function accessToken(): Promise<string> {
  const body = new URLSearchParams({
    client_id: Deno.env.get("GMAIL_CLIENT_ID") ?? "",
    client_secret: Deno.env.get("GMAIL_CLIENT_SECRET") ?? "",
    refresh_token: Deno.env.get("GMAIL_REFRESH_TOKEN") ?? "",
    grant_type: "refresh_token",
  });
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const j = await r.json();
  if (!r.ok || !j.access_token) throw new Error("Gmail auth failed: " + (j.error_description || j.error || r.status));
  return j.access_token;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const labelId = Deno.env.get("GMAIL_LABEL_ID");
  if (!Deno.env.get("GMAIL_REFRESH_TOKEN") || !labelId) {
    return json({ error: "Gmail not configured. Set GMAIL_CLIENT_ID/SECRET/REFRESH_TOKEN/LABEL_ID in Supabase secrets." }, 500);
  }

  // Optional: { sinceDays } to bound how far back we read (default 120).
  let sinceDays = 120;
  try { const b = await req.json(); if (b && Number(b.sinceDays) > 0) sinceDays = Number(b.sinceDays); } catch { /* no body */ }

  try {
    const tok = await accessToken();
    const auth = { Authorization: `Bearer ${tok}` };
    const q = encodeURIComponent(`newer_than:${sinceDays}d`);
    const listR = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages?labelIds=${labelId}&q=${q}&maxResults=100`,
      { headers: auth },
    );
    const list = await listR.json();
    if (!listR.ok) return json({ error: "Gmail list failed: " + (list.error?.message || listR.status) }, 502);
    const ids: string[] = (list.messages || []).map((m: { id: string }) => m.id);

    const txns: unknown[] = [];
    for (const id of ids) {
      const mR = await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}?format=full`, { headers: auth });
      if (!mR.ok) continue;
      const msg = await mR.json();
      const t = parseSony(plainText(msg.payload));
      if (t) txns.push(t);
    }
    return json({ ok: true, count: txns.length, transactions: txns }, 200);
  } catch (e) {
    return json({ error: String(e instanceof Error ? e.message : e) }, 502);
  }
});
