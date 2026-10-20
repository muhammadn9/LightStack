// ai-proxy: the app's only path to Gemini.
//
// - The Gemini key lives here as the GEMINI_API_KEY secret, never in the app.
// - Callers must be signed in (Supabase verifies the JWT before this runs).
// - Every call passes the per-user rate limit (check_rate_limit); if that check
//   fails for any reason the request is refused (fail closed).
// - The request is forwarded with the key in a header, not the URL.
// - thinkingConfig is validated (budget 0..1024 or level minimal/low); anything else is a 400.
// - The upstream call times out after 45s (504). Requests that fail upstream with a
//   5xx or time out are refunded (refund_rate_limit); a missing RPC is tolerated.
//
// Request body (from the app): { model, system_instruction, contents, generationConfig }
// Response: Gemini's JSON as-is, with Gemini's status code, so the app's parser
// and 503/429 handling keep working.

import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_MODELS = new Set(["gemini-3.5-flash", "gemini-2.5-flash"]);
const MAX_BODY_CHARS = 200_000;
const MAX_OUTPUT_TOKENS = 8192;
const UPSTREAM_TIMEOUT_MS = 45_000;
const MAX_THINKING_BUDGET = 1024;
const ALLOWED_THINKING_LEVELS = new Set(["minimal", "low"]);

/** A refusal from this function (not from Gemini). The app shows the message as-is. */
function error(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json", "x-ai-proxy-error": "1" },
  });
}

/**
 * Accepts only {thinkingBudget: integer 0...1024} or {thinkingLevel: "minimal" | "low"}
 * (what the app sends). Returns the cleaned config, or null if it is anything else.
 */
function validateThinkingConfig(raw: unknown): Record<string, unknown> | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const keys = Object.keys(raw);
  if (keys.length !== 1) return null;
  const r = raw as Record<string, unknown>;
  if (keys[0] === "thinkingBudget") {
    const v = r.thinkingBudget;
    if (typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= MAX_THINKING_BUDGET) {
      return { thinkingBudget: v };
    }
    return null;
  }
  if (keys[0] === "thinkingLevel") {
    const v = r.thinkingLevel;
    if (typeof v === "string" && ALLOWED_THINKING_LEVELS.has(v)) return { thinkingLevel: v };
    return null;
  }
  return null;
}

/** Keeps only the generation settings the app uses, with a token cap. */
function sanitizeConfig(raw: unknown, thinking: Record<string, unknown> | null): Record<string, unknown> {
  const config: Record<string, unknown> = {};
  if (thinking) config.thinkingConfig = thinking;
  if (typeof raw !== "object" || raw === null) return config;
  const r = raw as Record<string, unknown>;
  if (typeof r.temperature === "number") {
    config.temperature = Math.min(Math.max(r.temperature, 0), 2);
  }
  const requested = typeof r.maxOutputTokens === "number" ? r.maxOutputTokens : MAX_OUTPUT_TOKENS;
  config.maxOutputTokens = Math.min(Math.max(Math.floor(requested), 1), MAX_OUTPUT_TOKENS);
  if (r.responseMimeType === "application/json") config.responseMimeType = "application/json";
  return config;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return error("Method not allowed", 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const geminiKey = Deno.env.get("GEMINI_API_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
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

  // thinkingConfig: absent is fine; present must be one of the two allowed shapes.
  const rawConfig = body.generationConfig;
  let thinking: Record<string, unknown> | null = null;
  if (typeof rawConfig === "object" && rawConfig !== null &&
      (rawConfig as Record<string, unknown>).thinkingConfig !== undefined) {
    thinking = validateThinkingConfig((rawConfig as Record<string, unknown>).thinkingConfig);
    if (!thinking) {
      return error("Invalid thinkingConfig: use thinkingBudget 0-1024 or thinkingLevel minimal/low", 400);
    }
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
    generationConfig: sanitizeConfig(body.generationConfig, thinking),
  };
  if (body.system_instruction) payload.system_instruction = body.system_instruction;

  // Gives back the slot this request consumed. Uses the service role (the RPC is
  // not callable by signed-in clients) and the user id verified by auth.getUser,
  // never an id from the request. Never fails the request: if the RPC is missing
  // (migration not applied yet) or errors, log and carry on.
  const userId = userData.user.id;
  const refund = async () => {
    try {
      if (!serviceKey) {
        console.warn("refund skipped: SUPABASE_SERVICE_ROLE_KEY not set");
        return;
      }
      const admin = createClient(supabaseUrl, serviceKey);
      const { error: refundError } = await admin.rpc("refund_rate_limit", {
        p_user_id: userId,
        p_endpoint: "coach",
      });
      if (refundError) console.warn("refund_rate_limit failed:", refundError.message);
    } catch (e) {
      console.warn("refund_rate_limit threw:", e);
    }
  };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  let upstreamStatus: number;
  let upstreamText: string;
  try {
    const upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey },
        body: JSON.stringify(payload),
        signal: controller.signal,
      },
    );
    upstreamStatus = upstream.status;
    upstreamText = await upstream.text();
  } catch (e) {
    await refund();
    if (controller.signal.aborted) {
      return error("The AI service took too long to respond. Please try again.", 504);
    }
    console.error("upstream fetch failed:", e);
    return error("Could not reach the AI service. Please try again.", 502);
  } finally {
    clearTimeout(timer);
  }

  if (upstreamStatus >= 500) await refund();

  return new Response(upstreamText, {
    status: upstreamStatus,
    headers: { "Content-Type": "application/json" },
  });
});
