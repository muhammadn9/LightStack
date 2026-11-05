// Server-owned task table for ai-proxy. The client only NAMES a task; every limit
// below is decided here. Unknown task names fall back to `other` (the smallest limits).
// Pure module (no Deno / network APIs) so it can be unit-tested.

export type TaskName = "plan" | "chat" | "postWorkout" | "monthPlan" | "formFeedback" | "other" | "legacy";

export const CHEAP_MODEL = "gemini-2.5-flash";
export const CURRENT_MODEL = "gemini-3.5-flash";
export const ALL_MODELS = [CURRENT_MODEL, CHEAP_MODEL];

export type ThinkingEffort = "minimal" | "low";

export interface TaskSpec {
  /** Models this task may use. Anything else is rejected (400 invalid_model). */
  models: string[];
  /** Model used when routing is enabled (AI_MODEL_ROUTING=1) or the client sends none. */
  defaultModel: string;
  /** Max characters of contents + system_instruction (JSON-serialised). */
  maxInputChars: number;
  /** Hard cap on generationConfig.maxOutputTokens. */
  maxOutputTokens: number;
  /** Most thinking the task may use; also the value applied when the client sends none. */
  maxThinking: ThinkingEffort;
  /** Estimated worst-case cost (USD) reserved before the call. Replaced by the actual cost on settle. */
  reserveUsd: number;
}

export const TASKS: Record<TaskName, TaskSpec> = {
  plan: {
    models: ALL_MODELS, defaultModel: CURRENT_MODEL,
    maxInputChars: 150_000, maxOutputTokens: 6144, maxThinking: "low", reserveUsd: 0.03,
  },
  chat: {
    models: ALL_MODELS, defaultModel: CHEAP_MODEL,
    maxInputChars: 60_000, maxOutputTokens: 1000, maxThinking: "minimal", reserveUsd: 0.006,
  },
  postWorkout: {
    models: ALL_MODELS, defaultModel: CHEAP_MODEL,
    maxInputChars: 40_000, maxOutputTokens: 800, maxThinking: "minimal", reserveUsd: 0.005,
  },
  monthPlan: {
    models: ALL_MODELS, defaultModel: CURRENT_MODEL,
    maxInputChars: 100_000, maxOutputTokens: 4000, maxThinking: "minimal", reserveUsd: 0.02,
  },
  formFeedback: {
    models: ALL_MODELS, defaultModel: CHEAP_MODEL,
    maxInputChars: 30_000, maxOutputTokens: 600, maxThinking: "minimal", reserveUsd: 0.004,
  },
  other: {
    models: [CHEAP_MODEL], defaultModel: CHEAP_MODEL,
    maxInputChars: 20_000, maxOutputTokens: 1024, maxThinking: "minimal", reserveUsd: 0.003,
  },
  // Old app builds that send no `task`. Only reachable when AI_ALLOW_LEGACY_CLIENTS is on; a client can
  // never ask for it by name. Old behaviour (both models, 8192 out, 200k body cap, thinking up to 1024
  // tokens / "low"), reserved like a plan. Budgets, kill switch, ledger and rate limits still apply.
  legacy: {
    models: ALL_MODELS, defaultModel: CURRENT_MODEL,
    maxInputChars: 200_000, maxOutputTokens: 8192, maxThinking: "low", reserveUsd: 0.03,
  },
};

export type TaskResolution = { ok: true; name: TaskName } | { ok: false };

/**
 * Missing task -> `legacy` when allowLegacy (AI_ALLOW_LEGACY_CLIENTS), else `other`. Unknown string -> `other`.
 * A non-string, or an absurdly long value, is `invalid_task`.
 */
export function resolveTask(raw: unknown, allowLegacy = false): TaskResolution {
  if (raw === undefined || raw === null) return { ok: true, name: allowLegacy ? "legacy" : "other" };
  if (typeof raw !== "string" || raw.length > 64) return { ok: false };
  return { ok: true, name: raw !== "legacy" && Object.hasOwn(TASKS, raw) ? (raw as TaskName) : "other" };
}

/** Picks the model. With routing on, cheap tasks always use their defaultModel. */
export function chooseModel(task: TaskName, requested: string, routingEnabled: boolean): string | null {
  const spec = TASKS[task];
  if (!requested) return spec.defaultModel;
  if (!spec.models.includes(requested)) return null;
  if (routingEnabled && spec.models.includes(spec.defaultModel)) return spec.defaultModel;
  return requested;
}

/** Gemini 3.x takes a level, 2.5 takes a token budget. */
export function thinkingFor(model: string, effort: ThinkingEffort): Record<string, unknown> {
  if (model.startsWith("gemini-2.5")) return { thinkingBudget: effort === "low" ? 1024 : 0 };
  return { thinkingLevel: effort };
}

/**
 * Clamps validated client thinking (see index.ts validateThinkingConfig) to the task.
 * Absent -> the task's maxThinking (so a missing field can never mean "unbounded dynamic thinking").
 */
export function clampThinking(
  task: TaskName,
  model: string,
  requested: Record<string, unknown> | null,
): Record<string, unknown> {
  const max = TASKS[task].maxThinking;
  if (!requested) return thinkingFor(model, max);
  let effort: ThinkingEffort;
  if (typeof requested.thinkingBudget === "number") {
    effort = requested.thinkingBudget > 0 ? "low" : "minimal";
  } else {
    effort = requested.thinkingLevel === "low" ? "low" : "minimal";
  }
  if (effort === "low" && max === "minimal") effort = "minimal";
  return thinkingFor(model, effort);
}

/** Characters the task counts as input. */
export function inputChars(body: { contents?: unknown; system_instruction?: unknown }): number {
  let n = 0;
  try {
    n += JSON.stringify(body.contents ?? "").length;
    if (body.system_instruction) n += JSON.stringify(body.system_instruction).length;
  } catch {
    return Number.MAX_SAFE_INTEGER;
  }
  return n;
}

export function clampOutputTokens(task: TaskName, requested: unknown): number {
  const cap = TASKS[task].maxOutputTokens;
  const r = typeof requested === "number" && Number.isFinite(requested) ? Math.floor(requested) : cap;
  return Math.min(Math.max(r, 1), cap);
}

export type TextContent = { role: "user" | "model"; parts: { text: string }[] };

function textParts(raw: unknown): { text: string }[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const out: { text: string }[] = [];
  for (const p of raw) {
    if (typeof p !== "object" || p === null || typeof (p as Record<string, unknown>).text !== "string") return null;
    out.push({ text: (p as Record<string, unknown>).text as string });
  }
  return out;
}

/**
 * Rebuilds `contents` as text-only turns (all the app sends). Anything else (inline_data, fileData /
 * fileUri, functionCall, unknown keys) returns null: media and URLs are billed by tokens far beyond
 * their JSON size, so they would bypass maxInputChars and the reservation.
 */
export function textOnlyContents(raw: unknown): TextContent[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const out: TextContent[] = [];
  for (const c of raw) {
    if (typeof c !== "object" || c === null) return null;
    const role = (c as Record<string, unknown>).role;
    if (role !== "user" && role !== "model") return null;
    const parts = textParts((c as Record<string, unknown>).parts);
    if (!parts) return null;
    out.push({ role, parts });
  }
  return out;
}

/** system_instruction: absent -> undefined; {parts:[{text}]} -> rebuilt; anything else -> null. */
export function textOnlySystemInstruction(raw: unknown): { parts: { text: string }[] } | null | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw !== "object" || Array.isArray(raw)) return null;
  const parts = textParts((raw as Record<string, unknown>).parts);
  return parts ? { parts } : null;
}
