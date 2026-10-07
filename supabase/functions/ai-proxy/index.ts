// ai-proxy: the app's only path to Gemini.
//
// - The Gemini key lives here as the GEMINI_API_KEY secret, never in the app.
// - Callers must be signed in (Supabase verifies the JWT before this runs).
// - Every call passes the per-user rate limit (check_rate_limit); if that check
//   fails for any reason the request is refused (fail closed).
// - The request is forwarded with the key in a header, not the URL.
//
// Request body (from the app): { model, system_instruction, contents, generationConfig }
// Response: Gemini's JSON as-is, with Gemini's status code, so the app's parser
// and 503/429 handling keep working.

import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_MODELS = new Set(["gemini-3.5-flash", "gemini-2.5-flash"]);
const MAX_BODY_CHARS = 200_000;
const MAX_OUTPUT_TOKENS = 8192;

/** A refusal from this function (not from Gemini). The app shows the message as-is. */
function error(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json", "x-ai-proxy-error": "1" },
  });
}

/** Keeps only the generation settings the app uses, with a token cap. */
function sanitizeConfig(raw: unknown): Record<string, unknown> {
  const config: Record<string, unknown> = {};
  if (typeof raw !== "object" || raw === null) return config;
  const r = raw as Record<string, unknown>;
  if (typeof r.temperature === "number") {
    config.temperature = Math.min(Math.max(r.temperature, 0), 2);
  }
  const requested = typeof r.maxOutputTokens === "number" ? r.maxOutputTokens : MAX_OUTPUT_TOKENS;
  config.maxOutputTokens = Math.min(Math.max(Math.floor(requested), 1), MAX_OUTPUT_TOKENS);
  if (r.responseMimeType === "application/json") config.responseMimeType = "application/json";
  if (typeof r.thinkingConfig === "object" && r.thinkingConfig !== null) {
    config.thinkingConfig = r.thinkingConfig;
  }
  return config;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return error("Method not allowed", 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const geminiKey = Deno.env.get("GEMINI_API_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !geminiKey) return error("AI service is not configured", 500);

  // Act as the caller so auth.uid() inside check_rate_limit is their id.
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) return error("Not signed in", 401);

  const raw = await req.text();
  if (raw.length > MAX_BODY_CHARS) return error("Request too large", 413);

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return error("Invalid JSON", 400);
  }

  const model = typeof body.model === "string" ? body.model : "";
  if (!ALLOWED_MODELS.has(model)) return error("Unsupported model", 400);
  if (!Array.isArray(body.contents) || body.contents.length === 0) {
    return error("Missing contents", 400);
  }

  // Rate limit. Fail closed: any error refuses the request.
  const { data: limit, error: limitError } = await supabase.rpc("check_rate_limit");
  if (limitError) return error("Rate limit check failed", 503);
  if (!limit?.allowed) {
    const message = limit?.reason === "day"
      ? "Daily AI limit reached. Try again tomorrow."
      : "Too many AI requests. Please wait a moment before trying again.";
    return error(message, 429);
  }

  const payload: Record<string, unknown> = {
    contents: body.contents,
    generationConfig: sanitizeConfig(body.generationConfig),
  };
  if (body.system_instruction) payload.system_instruction = body.system_instruction;

  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey },
      body: JSON.stringify(payload),
    },
  );

  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: { "Content-Type": "application/json" },
  });
});
