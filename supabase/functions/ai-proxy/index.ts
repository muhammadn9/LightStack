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
// - Spending controls: the app names a `task` and a `request_id`; limits come from the
//   server task table (tasks.ts). ai_reserve (SECURITY DEFINER, service role only) checks the
//   kill switch, per-user/global day+month budgets and in-flight concurrency before the
//   call; ai_settle records the real cost from usageMetadata afterwards. See budget.ts and
//   docs/ai/AI_COST_CONTROLS.md.
//
// Request body (from the app): { task, request_id, model, system_instruction, contents, generationConfig }
// Response: Gemini's JSON as-is, with Gemini's status code, so the app's parser
// and 503/429 handling keep working.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { cleanRequestId, mapReserveReason, parseUsage } from "./budget.ts";
import { chooseModel, clampOutputTokens, clampThinking, inputChars, resolveTask, TASKS } from "./tasks.ts";

const MAX_BODY_CHARS = 200_000;
const UPSTREAM_TIMEOUT_MS = 45_000;
const MAX_THINKING_BUDGET = 1024;
const ALLOWED_THINKING_LEVELS = new Set(["minimal", "low"]);

/** A refusal from this function (not from Gemini). The app shows the message as-is. */
function error(message: string, status: number, code = "proxy_error"): Response {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json", "x-ai-proxy-error": code },
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

/** Keeps only the generation settings the app uses; limits come from the task, not the client. */
function sanitizeConfig(
  raw: unknown,
  thinking: Record<string, unknown>,
  maxOutputTokens: number,
): Record<string, unknown> {
  const config: Record<string, unknown> = { thinkingConfig: thinking, maxOutputTokens };
  if (typeof raw !== "object" || raw === null) return config;
  const r = raw as Record<string, unknown>;
  if (typeof r.temperature === "number") {
    config.temperature = Math.min(Math.max(r.temperature, 0), 2);
  }
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

  const resolved = resolveTask(body.task);
  if (!resolved.ok) return error("Invalid task", 400, "invalid_task");
  const taskName = resolved.name;
  const spec = TASKS[taskName];

  const requestedModel = typeof body.model === "string" ? body.model : "";
  const model = chooseModel(taskName, requestedModel, Deno.env.get("AI_MODEL_ROUTING") === "1");
  if (!model) return error("Unsupported model for this task", 400, "invalid_model");
  if (!Array.isArray(body.contents) || body.contents.length === 0) {
    return error("Missing contents", 400, "invalid_request");
  }
  if (inputChars(body) > spec.maxInputChars) {
    return error("Request too large for this feature", 413, "input_too_large");
  }

  // thinkingConfig: absent is fine; present must be one of the two allowed shapes.
  // Either way it is then clamped to what the task allows.
  const rawConfig = body.generationConfig;
  let requestedThinking: Record<string, unknown> | null = null;
  if (typeof rawConfig === "object" && rawConfig !== null &&
      (rawConfig as Record<string, unknown>).thinkingConfig !== undefined) {
    requestedThinking = validateThinkingConfig((rawConfig as Record<string, unknown>).thinkingConfig);
    if (!requestedThinking) {
      return error("Invalid thinkingConfig: use thinkingBudget 0-1024 or thinkingLevel minimal/low", 400, "invalid_request");
    }
  }
  const thinking = clampThinking(taskName, model, requestedThinking);
  const maxOutputTokens = clampOutputTokens(
    taskName,
    typeof rawConfig === "object" && rawConfig !== null
      ? (rawConfig as Record<string, unknown>).maxOutputTokens
      : undefined,
  );

  // Rate limit. Fail closed: any error refuses the request.
  const { data: limit, error: limitError } = await supabase.rpc("check_rate_limit");
  if (limitError) return error("Rate limit check failed", 503, "rate_limit_unavailable");
  if (!limit?.allowed) {
    const day = limit?.reason === "day";
    const message = day
      ? "Daily AI limit reached. Try again tomorrow."
      : "Too many AI requests. Please wait a moment before trying again.";
    return error(message, 429, day ? "rate_limit_day" : "rate_limit_minute");
  }

  const payload: Record<string, unknown> = {
    contents: body.contents,
    generationConfig: sanitizeConfig(body.generationConfig, thinking, maxOutputTokens),
  };
  if (body.system_instruction) payload.system_instruction = body.system_instruction;

  // Gives back the slot this request consumed. Uses the service role (the RPC is
  // not callable by signed-in clients) and the user id verified by auth.getUser,
  // never an id from the request. Never fails the request: if the RPC is missing
  // (migration not applied yet) or errors, log and carry on.
  const userId = userData.user.id;
  const admin = serviceKey ? createClient(supabaseUrl, serviceKey) : null;
  const refund = async () => {
    try {
      if (!admin) {
        console.warn("refund skipped: SUPABASE_SERVICE_ROLE_KEY not set");
        return;
      }
      const { error: refundError } = await admin.rpc("refund_rate_limit", {
        p_user_id: userId,
        p_endpoint: "coach",
      });
      if (refundError) console.warn("refund_rate_limit failed:", refundError.message);
    } catch (e) {
      console.warn("refund_rate_limit threw:", e);
    }
  };

  // Budget reservation. Fail closed: if it cannot be made, no Gemini call is made.
  // request_id comes from the app (one per logical request, reused across the
  // fallback-model retry) so a retry never counts twice.
  const requestId = cleanRequestId(body.request_id, () => crypto.randomUUID());
  if (!admin) {
    await refund();
    console.error("budget check unavailable: SUPABASE_SERVICE_ROLE_KEY not set");
    const f = mapReserveReason(null);
    return error(f.message, f.status, f.code);
  }
  const { data: reservation, error: reserveError } = await admin.rpc("ai_reserve", {
    p_user: userId,
    p_request_id: requestId,
    p_task: taskName,
    p_model: model,
    p_reserve_usd: spec.reserveUsd,
  });
  if (reserveError || !reservation?.ok) {
    await refund();
    if (reserveError) console.error("ai_reserve failed:", reserveError.message);
    const f = mapReserveReason(reserveError ? null : reservation?.reason);
    return error(f.message, f.status, f.code);
  }

  const settle = async (
    status: "succeeded" | "failed",
    usage: { input: number | null; output: number | null; thinking: number | null },
    startedAt: number,
    errorCode: string | null,
  ) => {
    try {
      const { error: settleError } = await admin.rpc("ai_settle", {
        p_user: userId,
        p_request_id: requestId,
        p_input_tokens: usage.input,
        p_output_tokens: usage.output,
        p_thinking_tokens: usage.thinking,
        p_status: status,
        p_latency_ms: Date.now() - startedAt,
        p_error_code: errorCode,
      });
      if (settleError) console.error("ai_settle failed:", settleError.message);
    } catch (e) {
      console.error("ai_settle threw:", e);
    }
  };
  const noUsage = { input: null, output: null, thinking: null };

  const startedAt = Date.now();
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
    const timedOut = controller.signal.aborted;
    await settle("failed", noUsage, startedAt, timedOut ? "upstream_timeout" : "upstream_unreachable");
    if (timedOut) {
      return error("The AI service took too long to respond. Please try again.", 504, "upstream_timeout");
    }
    console.error("upstream fetch failed:", e);
    return error("Could not reach the AI service. Please try again.", 502, "upstream_unreachable");
  } finally {
    clearTimeout(timer);
  }

  if (upstreamStatus >= 500) await refund();

  if (upstreamStatus >= 200 && upstreamStatus < 300) {
    await settle("succeeded", parseUsage(upstreamText), startedAt, null);
  } else {
    await settle("failed", noUsage, startedAt, `upstream_${upstreamStatus}`);
  }

  return new Response(upstreamText, {
    status: upstreamStatus,
    headers: { "Content-Type": "application/json" },
  });
});
