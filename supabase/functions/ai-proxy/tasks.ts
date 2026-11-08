// Server-owned task table for ai-proxy. The client only NAMES a task; every limit
// below is decided here. Unknown task names fall back to `other` (the smallest limits).
// Pure module (no Deno / network APIs) so it can be unit-tested.

export type TaskName = "plan" | "chat" | "postWorkout" | "monthPlan" | "formFeedback" | "mealEstimate" | "other" | "legacy";

export const CHEAP_MODEL = "gemini-2.5-flash";
export const CURRENT_MODEL = "gemini-3.5-flash";
export const ALL_MODELS = [CURRENT_MODEL, CHEAP_MODEL];

export type ThinkingEffort = "minimal" | "low" | "medium";

const RANK: Record<ThinkingEffort, number> = { minimal: 0, low: 1, medium: 2 };

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
  /** Most inline_data images one request may carry (0 = text only). Only image/jpeg or image/png. */
  allowImages: number;
  /** May send tools: [{"google_search":{}}]. Every other tool is always rejected. */
  allowSearch: boolean;
}

export const TASKS: Record<TaskName, TaskSpec> = {
  plan: {
    models: ALL_MODELS, defaultModel: CURRENT_MODEL,
    // Coach v3: 8192 output tokens (thinking counts toward them) and "medium" thinking, with a responseSchema.
    maxInputChars: 150_000, maxOutputTokens: 8192, maxThinking: "medium", reserveUsd: 0.04,
    allowImages: 0, allowSearch: false,
  },
  chat: {
    models: ALL_MODELS, defaultModel: CHEAP_MODEL,
    maxInputChars: 60_000, maxOutputTokens: 1000, maxThinking: "minimal", reserveUsd: 0.006,
    allowImages: 0, allowSearch: false,
  },
  postWorkout: {
    models: ALL_MODELS, defaultModel: CHEAP_MODEL,
    maxInputChars: 40_000, maxOutputTokens: 800, maxThinking: "minimal", reserveUsd: 0.005,
    allowImages: 0, allowSearch: false,
  },
  monthPlan: {
    models: ALL_MODELS, defaultModel: CURRENT_MODEL,
    maxInputChars: 100_000, maxOutputTokens: 4000, maxThinking: "minimal", reserveUsd: 0.02,
    allowImages: 0, allowSearch: false,
  },
  formFeedback: {
    models: ALL_MODELS, defaultModel: CHEAP_MODEL,
    maxInputChars: 30_000, maxOutputTokens: 600, maxThinking: "minimal", reserveUsd: 0.004,
    allowImages: 0, allowSearch: false,
  },
  // Meal estimation (nutrition phase 4): a description and/or ONE photo, optionally with Google Search for
  // restaurant menus. The app sends 3000 output tokens and "low" thinking; 4096 leaves headroom, no more.
  // The reserve covers an image (~1-2k input tokens) AND search grounding, which Google bills per request
  // (about $0.035 per grounded prompt, more if the model runs several searches) on top of tokens:
  // 0.035 grounding + ~0.008 output + input/thinking, rounded up and padded to 0.06. Settled to actual cost.
  mealEstimate: {
    models: ALL_MODELS, defaultModel: CURRENT_MODEL,
    // Counts text only; the image has its own body limit (MAX_BODY_CHARS_WITH_IMAGE in index.ts).
    maxInputChars: 60_000, maxOutputTokens: 4096, maxThinking: "low", reserveUsd: 0.06,
    allowImages: 1, allowSearch: true,
  },
  other: {
    models: [CHEAP_MODEL], defaultModel: CHEAP_MODEL,
    maxInputChars: 20_000, maxOutputTokens: 1024, maxThinking: "minimal", reserveUsd: 0.003,
    allowImages: 0, allowSearch: false,
  },
  // Old app builds that send no `task`. Only reachable when AI_ALLOW_LEGACY_CLIENTS is on; a client can
  // never ask for it by name. Old behaviour (both models, 8192 out, 200k body cap, thinking up to 1024
  // tokens / "low" / coach v3 "medium" up to 4096), reserved like a plan. Budgets, kill switch, ledger and rate limits still apply.
  legacy: {
    models: ALL_MODELS, defaultModel: CURRENT_MODEL,
    maxInputChars: 200_000, maxOutputTokens: 8192, maxThinking: "medium", reserveUsd: 0.04,
    allowImages: 0, allowSearch: false,
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
  if (model.startsWith("gemini-2.5")) {
    return { thinkingBudget: effort === "medium" ? 4096 : effort === "low" ? 1024 : 0 };
  }
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
    const b = requested.thinkingBudget;
    effort = b > 1024 ? "medium" : b > 0 ? "low" : "minimal";
  } else {
    effort = requested.thinkingLevel === "medium" ? "medium" : requested.thinkingLevel === "low" ? "low" : "minimal";
  }
  if (RANK[effort] > RANK[max]) effort = max;
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

/** Characters of text the task counts as input: like inputChars, but base64 image data is not counted. */
export function textInputChars(contents: unknown[], systemInstruction: unknown): number {
  let n = 0;
  try {
    for (const c of contents) {
      const parts = (c as { parts: Record<string, unknown>[] }).parts;
      n += JSON.stringify({ ...(c as object), parts: parts.map((p) => ("inline_data" in p ? { inline_data: {} } : p)) }).length;
    }
    if (systemInstruction) n += JSON.stringify(systemInstruction).length;
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

export const MAX_BODY_CHARS = 200_000;
export const MAX_BODY_CHARS_WITH_IMAGE = 3_000_000;
const MAX_PARTS_PER_CONTENT = 8;
const ALLOWED_IMAGE_MIME = new Set(["image/jpeg", "image/png"]);
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

/** True only for exactly [{"google_search":{}}]. */
export function isGoogleSearchTools(raw: unknown): boolean {
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
 * Strict rebuild of `contents` for a task that allows images: each item {role?, parts:[{text}|{inline_data}]},
 * user/model roles, at most 8 parts per item, at most `maxImages` images (image/jpeg or image/png, base64,
 * exactly the two keys mime_type + data). Anything else returns null. Tasks with maxImages 0 reject every
 * inline_data part, so they behave exactly like textOnlyContents.
 */
export function validateContents(raw: unknown, maxImages: number): { contents: unknown[]; images: number } | null {
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
        if (images > maxImages) return null;
        parts.push({ inline_data: { mime_type: data.mime_type, data: data.data } });
      } else {
        return null;
      }
    }
    contents.push(c.role === undefined ? { parts } : { role: c.role, parts });
  }
  return { contents, images };
}

export type ShapeCheck =
  | { ok: true; contents: unknown[]; images: number; useSearch: boolean }
  | { ok: false; message: string };

/**
 * The per-task media and tools gate used by index.ts: contents must be valid for the task (images only when
 * allowImages), and `tools` must be absent, or exactly the search tool on a task with allowSearch.
 * Legacy and every task without the flags reject both.
 */
export function checkContentsAndTools(task: TaskName, rawContents: unknown, rawTools: unknown): ShapeCheck {
  const spec = TASKS[task];
  const validated = validateContents(rawContents, spec.allowImages);
  if (!validated) {
    return {
      ok: false,
      message: spec.allowImages > 0
        ? "Invalid contents: use text parts or one image/jpeg or image/png inline_data"
        : "Only text content is supported",
    };
  }
  const useSearch = rawTools !== undefined;
  if (useSearch && (!spec.allowSearch || !isGoogleSearchTools(rawTools))) {
    return { ok: false, message: 'Invalid tools: only [{"google_search":{}}] is allowed, and only for meal estimates' };
  }
  return { ok: true, contents: validated.contents, images: validated.images, useSearch };
}
