// GymLog problem-report relay (ship-readiness #5).
//
// The app POSTs the diagnostic template here; this function is the ONLY
// place the Telegram bot token exists (Supabase secret env), so nothing
// sensitive ships inside the APK — a bundled token would be extractable
// with `strings` and unrevocable without shipping a new build.
//
// Deploy:
//   supabase functions deploy report-problem
//   supabase secrets set TELEGRAM_BOT_TOKEN=<token> TELEGRAM_CHAT_ID=<@gym_log or numeric id>

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID") ?? "@gym_log";
const MAX_FIELD = 2000;

// Best-effort per-IP rate limit (resets on cold start — enough to stop
// casual abuse; review Supabase invocation logs for anything smarter).
const hits = new Map<string, number[]>();
const WINDOW_MS = 10 * 60 * 1000;
const MAX_PER_WINDOW = 5;

function rateLimited(ip: string): boolean {
  const now = Date.now();
  const list = (hits.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  if (list.length >= MAX_PER_WINDOW) return true;
  list.push(now);
  hits.set(ip, list);
  return false;
}

// Telegram HTML parse mode: escape the three meta chars and cap length.
function clean(value: unknown, fallback = ""): string {
  if (typeof value !== "string") return fallback;
  return value
    .slice(0, MAX_FIELD)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!BOT_TOKEN) {
    return new Response("Relay not configured", { status: 500 });
  }

  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  if (rateLimited(ip)) {
    return new Response("Rate limited", { status: 429 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  const category = clean(body.category, "Other");
  const summary = clean(body.summary);
  const repro = clean(body.repro);
  if (!summary) {
    return new Response("summary is required", { status: 400 });
  }

  const lines = [
    "<b>🛠 GymLog Problem Report</b>",
    `<b>Category:</b> ${category}`,
    `<b>Summary:</b> ${summary}`,
    repro ? `<b>Repro:</b>\n${repro}` : "",
    "",
    `<b>App:</b> ${clean(body.appVersion)} · <b>OS:</b> ${clean(body.os)}`,
    `<b>DB:</b> v${clean(String(body.dbSchema ?? ""))} · <b>Catalog:</b> v${clean(String(body.catalog ?? ""))}`,
    `<b>Ref:</b> ${clean(body.opRef)}`,
  ];
  const text = lines.filter((l) => l !== "").join("\n");

  const tg = await fetch(
    `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        chat_id: CHAT_ID,
        text,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    },
  );

  if (!tg.ok) {
    return new Response("Upstream failed", { status: 502 });
  }
  return Response.json({ ok: true });
});
