// ai-proxy: the app's only path to Gemini.
//
// - The Gemini key lives here as the GEMINI_API_KEY secret, never in the app.
// - Callers must be signed in (Supabase verifies the JWT before this runs).
// - Every call passes the per-user rate limit (check_rate_limit); if that check
//   fails for any reason the request is refused (fail closed).
// - The request is forwarded with the key in a header, not the URL.
// - thinkingConfig is validated (budget 0..4096 or level minimal/low/medium); anything else is a 400.
// - responseSchema is passed through only with responseMimeType application/json, as a plain
//   object of at most 6000 JSON characters; otherwise it is dropped.
// - The upstream call times out after 55s (504). Requests that fail upstream with a
//   5xx or time out are refunded (refund_rate_limit); a missing RPC is tolerated.
//
// - Optional `tools`: ONLY exactly [{"google_search":{}}] is accepted (anything else is a 400).
//   Gemini can reject google_search together with responseMimeType application/json, so when
//   tools are present responseMimeType is dropped (the app asks for JSON in text and parses it
//   leniently). The response is returned as-is, including groundingMetadata.
// - contents parts may be {text} or one {inline_data:{mime_type,data}} image (image/jpeg or
//   image/png, base64, max 1 per request). Any other part type is a 400. Bodies with an image
//   may be up to 3,000,000 chars; text-only bodies stay capped at 200,000.
//
// Request body (from the app): { model, system_instruction, contents, generationConfig, tools? }
// Response: Gemini's JSON as-is, with Gemini's status code, so the app's parser
// and 503/429 handling keep working.

import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_MODELS = new Set(["gemini-3.5-flash", "gemini-2.5-flash"]);
const MAX_BODY_CHARS = 200_000;
const MAX_BODY_CHARS_WITH_IMAGE = 3_000_000;
const MAX_IMAGES = 1;
const MAX_PARTS_PER_CONTENT = 8;
const ALLOWED_IMAGE_MIME = new Set(["image/jpeg", "image/png"]);
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;
const MAX_OUTPUT_TOKENS = 8192;
const UPSTREAM_TIMEOUT_MS = 55_000;
const MAX_THINKING_BUDGET = 4096;
const MAX_SCHEMA_CHARS = 6000;
const ALLOWED_THINKING_LEVELS = new Set(["minimal", "low", "medium"]);

/** A refusal from this function (not from Gemini). The app shows the message as-is. */
function error(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json", "x-ai-proxy-error": "1" },
  });
}

/**
 * Accepts only {thinkingBudget: integer 0...4096} or {thinkingLevel: "minimal" | "low" | "medium"}
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

/** True only for exactly [{"google_search":{}}]. */
function isGoogleSearchTools(raw: unknown): boolean {
  if (!Array.isArray(raw) || raw.length !== 1) return false;
  const tool = raw[0];
  if (typeof tool !== "object" || tool === null || Array.isArray(tool)) return false;
  const keys = Object.keys(tool);
  if (keys.length !== 1 || keys[0] !== "google_search") return false;
  const inner = (tool as Record<string, unknown>).google_search;
  return typeof inner === "object" && inner !== null && !Array.isArray(inner) &&
    Object.keys(inner).length === 0;
}

/**
 * Validates and rebuilds `contents`: each item {role?, parts:[{text}|{inline_data}]}.
 * Returns the cleaned contents and the image count, or null if any shape is not allowed.
 */
function validateContents(raw: unknown): { contents: unknown[]; images: number } | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  let images = 0;
  const contents: unknown[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null || Array.isArray(item)) return null;
    const c = item as Record<string, unknown>;
    if (c.role !== undefined && c.role !== "user" && c.role !== "model") return null;
    if (!Array.isArray(c.parts) || c.parts.length === 0 || c.parts.length > MAX_PARTS_PER_CONTENT) return null;
    const parts: unknown[] = [];
    for (const part of c.parts) {
      if (typeof part !== "object" || part === null || Array.isArray(part)) return null;
      const p = part as Record<string, unknown>;
      const keys = Object.keys(p);
      if (keys.length !== 1) return null;
      if (keys[0] === "text") {
        if (typeof p.text !== "string") return null;
        parts.push({ text: p.text });
      } else if (keys[0] === "inline_data") {
        const d = p.inline_data;
        if (typeof d !== "object" || d === null || Array.isArray(d)) return null;
        const data = d as Record<string, unknown>;
        if (Object.keys(data).length !== 2) return null;
        if (typeof data.mime_type !== "string" || !ALLOWED_IMAGE_MIME.has(data.mime_type)) return null;
        if (typeof data.data !== "string" || data.data.length === 0 || !BASE64_PATTERN.test(data.data)) return null;
        images += 1;
        if (images > MAX_IMAGES) return null;
        parts.push({ inline_data: { mime_type: data.mime_type, data: data.data } });
      } else {
        return null;
      }
    }
    contents.push(c.role === undefined ? { parts } : { role: c.role, parts });
  }
  return { contents, images };
}

/** Keeps only the generation settings the app uses, with a token cap. */
function sanitizeConfig(
  raw: unknown,
  thinking: Record<string, unknown> | null,
  allowJsonMime = true,
): Record<string, unknown> {
  const config: Record<string, unknown> = {};
  if (thinking) config.thinkingConfig = thinking;
  if (typeof raw !== "object" || raw === null) return config;
  const r = raw as Record<string, unknown>;
  if (typeof r.temperature === "number") {
    config.temperature = Math.min(Math.max(r.temperature, 0), 2);
  }
  const requested = typeof r.maxOutputTokens === "number" ? r.maxOutputTokens : MAX_OUTPUT_TOKENS;
  config.maxOutputTokens = Math.min(Math.max(Math.floor(requested), 1), MAX_OUTPUT_TOKENS);
  if (allowJsonMime && r.responseMimeType === "application/json") {
    config.responseMimeType = "application/json";
    const schema = r.responseSchema;
    if (typeof schema === "object" && schema !== null && !Array.isArray(schema) &&
        JSON.stringify(schema).length <= MAX_SCHEMA_CHARS) {
      config.responseSchema = schema;
    }
  }
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
  if (raw.length > MAX_BODY_CHARS_WITH_IMAGE) return error("Request too large", 413);

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
  const validated = validateContents(body.contents);
  if (!validated) return error("Invalid contents: use text parts or one image/jpeg or image/png inline_data", 400);
  // Text-only requests keep the original, smaller limit.
  if (validated.images === 0 && raw.length > MAX_BODY_CHARS) return error("Request too large", 413);

  // tools: absent is fine; present must be exactly [{"google_search":{}}].
  const useSearch = body.tools !== undefined;
  if (useSearch && !isGoogleSearchTools(body.tools)) {
    return error('Invalid tools: only [{"google_search":{}}] is allowed', 400);
  }

  // thinkingConfig: absent is fine; present must be one of the two allowed shapes.
  const rawConfig = body.generationConfig;
  let thinking: Record<string, unknown> | null = null;
  if (typeof rawConfig === "object" && rawConfig !== null &&
      (rawConfig as Record<string, unknown>).thinkingConfig !== undefined) {
    thinking = validateThinkingConfig((rawConfig as Record<string, unknown>).thinkingConfig);
    if (!thinking) {
      return error("Invalid thinkingConfig: use thinkingBudget 0-4096 or thinkingLevel minimal/low/medium", 400);
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
    contents: validated.contents,
    generationConfig: sanitizeConfig(body.generationConfig, thinking, !useSearch),
  };
  if (useSearch) payload.tools = [{ google_search: {} }];
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
