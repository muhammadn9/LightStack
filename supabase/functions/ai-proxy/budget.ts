// Budget helpers for ai-proxy: maps ai_reserve refusals to HTTP errors and reads Gemini usage.
// Pure module so it can be unit-tested without Deno-only APIs.

export interface ProxyFailure {
  status: number;
  code: string;
  message: string;
}

const COACH_DOWN = "Coach temporarily unavailable. Please try again later.";

/** Reasons returned by public.ai_reserve -> the HTTP error the app receives. */
export function mapReserveReason(reason: string | null | undefined): ProxyFailure {
  switch (reason) {
    case "ai_disabled":
      return { status: 503, code: "ai_disabled", message: COACH_DOWN };
    case "budget_user_daily":
      return { status: 429, code: "budget_user_daily", message: "Daily AI limit reached. It resets tomorrow." };
    case "budget_user_monthly":
      return { status: 429, code: "budget_user_monthly", message: "Monthly AI limit reached. It resets next month." };
    case "budget_global":
      return { status: 503, code: "budget_global", message: COACH_DOWN };
    case "too_many_in_flight":
      return { status: 429, code: "too_many_in_flight", message: "Please wait for your current coach request to finish." };
    case "duplicate_in_flight":
    case "duplicate_completed":
      return { status: 409, code: "duplicate_request", message: "That request was already sent." };
    default:
      return { status: 503, code: "budget_unavailable", message: COACH_DOWN };
  }
}

export interface Usage {
  input: number | null;
  output: number | null;
  thinking: number | null;
}

/** Reads usageMetadata from a Gemini generateContent response body (JSON text). */
export function parseUsage(text: string): Usage {
  const none: Usage = { input: null, output: null, thinking: null };
  try {
    const m = JSON.parse(text)?.usageMetadata;
    if (!m || typeof m !== "object") return none;
    const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.floor(v) : null);
    const input = n(m.promptTokenCount);
    const output = n(m.candidatesTokenCount);
    const thinking = n(m.thoughtsTokenCount);
    if (input === null && output === null && thinking === null) return none;
    return { input: input ?? 0, output: output ?? 0, thinking: thinking ?? 0 };
  } catch {
    return none;
  }
}

/** A client request id: 8-64 chars of [A-Za-z0-9-]. Otherwise the server makes its own. */
export function cleanRequestId(raw: unknown, generate: () => string): string {
  return typeof raw === "string" && /^[A-Za-z0-9-]{8,64}$/.test(raw) ? raw : generate();
}
