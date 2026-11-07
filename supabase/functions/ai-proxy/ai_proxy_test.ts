// Run: deno test supabase/functions/ai-proxy/ai_proxy_test.ts   (no network, no external imports)
import { cleanRequestId, mapReserveReason, parseUsage } from "./budget.ts";
import {
  chooseModel,
  clampOutputTokens,
  clampThinking,
  inputChars,
  resolveTask,
  TASKS,
  textOnlyContents,
  textOnlySystemInstruction,
} from "./tasks.ts";

function eq(actual: unknown, expected: unknown, msg = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg} expected ${e} got ${a}`);
}

Deno.test("unknown task becomes other, missing becomes other, bad type is invalid", () => {
  eq(resolveTask("chat"), { ok: true, name: "chat" });
  eq(resolveTask("hack"), { ok: true, name: "other" });
  eq(resolveTask("toString"), { ok: true, name: "other" });
  eq(resolveTask(undefined), { ok: true, name: "other" });
  eq(resolveTask("legacy", true), { ok: true, name: "other" });
  eq(resolveTask(5), { ok: false });
  eq(resolveTask("x".repeat(65)), { ok: false });
});

Deno.test("other has the smallest limits", () => {
  for (const [name, spec] of Object.entries(TASKS)) {
    if (name === "other") continue;
    if (TASKS.other.maxInputChars > spec.maxInputChars) throw new Error(`other input > ${name}`);
    if (TASKS.other.reserveUsd > spec.reserveUsd) throw new Error(`other reserve > ${name}`);
  }
});

Deno.test("output tokens are clamped to the task", () => {
  eq(clampOutputTokens("chat", 8192), 1000);
  eq(clampOutputTokens("chat", 10), 10);
  eq(clampOutputTokens("chat", -5), 1);
  eq(clampOutputTokens("plan", undefined), 8192);
  eq(clampOutputTokens("other", 99999), 1024);
});

Deno.test("thinking is clamped and defaulted by the server", () => {
  eq(clampThinking("chat", "gemini-2.5-flash", { thinkingBudget: 1024 }), { thinkingBudget: 0 });
  eq(clampThinking("chat", "gemini-3.5-flash", { thinkingLevel: "low" }), { thinkingLevel: "minimal" });
  eq(clampThinking("plan", "gemini-2.5-flash", { thinkingBudget: 1024 }), { thinkingBudget: 1024 });
  eq(clampThinking("plan", "gemini-3.5-flash", { thinkingLevel: "low" }), { thinkingLevel: "low" });
  eq(clampThinking("plan", "gemini-3.5-flash", null), { thinkingLevel: "medium" });
  // Coach v3: plan may use medium / budget 4096; other tasks are clamped down.
  eq(clampThinking("plan", "gemini-3.5-flash", { thinkingLevel: "medium" }), { thinkingLevel: "medium" });
  eq(clampThinking("plan", "gemini-2.5-flash", { thinkingBudget: 4096 }), { thinkingBudget: 4096 });
  eq(clampThinking("chat", "gemini-3.5-flash", { thinkingLevel: "medium" }), { thinkingLevel: "minimal" });
  eq(clampThinking("monthPlan", "gemini-2.5-flash", { thinkingBudget: 4096 }), { thinkingBudget: 0 });
  eq(clampOutputTokens("plan", 8192), 8192);
  eq(clampThinking("chat", "gemini-2.5-flash", null), { thinkingBudget: 0 });
});

Deno.test("model must be in the task's list; routing prefers the cheap model", () => {
  eq(chooseModel("chat", "gpt-4", false), null);
  eq(chooseModel("other", "gemini-3.5-flash", false), null);
  eq(chooseModel("chat", "gemini-3.5-flash", false), "gemini-3.5-flash");
  eq(chooseModel("chat", "gemini-3.5-flash", true), "gemini-2.5-flash");
  eq(chooseModel("plan", "gemini-2.5-flash", true), "gemini-3.5-flash");
  eq(chooseModel("chat", "", false), "gemini-2.5-flash");
});

Deno.test("input size counts contents and system instruction", () => {
  const small = inputChars({ contents: [{ parts: [{ text: "hi" }] }] });
  const big = inputChars({ contents: [{ parts: [{ text: "hi" }] }], system_instruction: { parts: [{ text: "x".repeat(500) }] } });
  if (big - small < 500) throw new Error("system instruction not counted");
});

Deno.test("reserve reasons map to the documented errors", () => {
  eq(mapReserveReason("ai_disabled").status, 503);
  eq(mapReserveReason("ai_disabled").code, "ai_disabled");
  eq(mapReserveReason("budget_user_daily").status, 429);
  eq(mapReserveReason("budget_user_monthly").status, 429);
  eq(mapReserveReason("budget_global").status, 503);
  eq(mapReserveReason("too_many_in_flight").status, 429);
  eq(mapReserveReason("duplicate_in_flight").status, 409);
  eq(mapReserveReason(undefined).code, "budget_unavailable");
  eq(mapReserveReason("something_new").status, 503);
});

Deno.test("usageMetadata is read; absent usage is null (charged at reserve)", () => {
  eq(
    parseUsage(JSON.stringify({ usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5, thoughtsTokenCount: 2 } })),
    { input: 10, output: 5, thinking: 2 },
  );
  eq(parseUsage(JSON.stringify({ usageMetadata: { promptTokenCount: 10 } })), { input: 10, output: 0, thinking: 0 });
  eq(parseUsage("{}"), { input: null, output: null, thinking: null });
  eq(parseUsage("not json"), { input: null, output: null, thinking: null });
});

Deno.test("request ids are validated", () => {
  eq(cleanRequestId("123e4567-e89b-12d3-a456-426614174000", () => "gen"), "123e4567-e89b-12d3-a456-426614174000");
  eq(cleanRequestId("short", () => "gen"), "gen");
  eq(cleanRequestId("bad id with spaces!", () => "gen"), "gen");
  eq(cleanRequestId(undefined, () => "gen"), "gen");
});

Deno.test("legacy: only for a missing task, only when allowed; keeps old limits and plan reserve", () => {
  eq(resolveTask(undefined, true), { ok: true, name: "legacy" });
  eq(resolveTask(null, true), { ok: true, name: "legacy" });
  eq(resolveTask("nope", true), { ok: true, name: "other" });
  eq(resolveTask(5, true), { ok: false });
  eq(TASKS.legacy.maxOutputTokens, 8192);
  eq(TASKS.legacy.maxInputChars, 200_000);
  eq(TASKS.legacy.reserveUsd, TASKS.plan.reserveUsd);
  eq(chooseModel("legacy", "gemini-2.5-flash", false), "gemini-2.5-flash");
  eq(chooseModel("legacy", "gemini-3.5-flash", false), "gemini-3.5-flash");
  eq(clampOutputTokens("legacy", 8192), 8192);
  eq(clampThinking("legacy", "gemini-2.5-flash", { thinkingBudget: 1024 }), { thinkingBudget: 1024 });
  eq(clampThinking("legacy", "gemini-2.5-flash", { thinkingBudget: 4096 }), { thinkingBudget: 4096 });
});

Deno.test("contents are text only; media, file URIs and extra keys are refused", () => {
  eq(textOnlyContents([{ role: "user", parts: [{ text: "hi", extra: 1 }] }]), [{ role: "user", parts: [{ text: "hi" }] }]);
  eq(textOnlyContents([{ role: "user", parts: [{ inline_data: { mime_type: "video/mp4", data: "AA" } }] }]), null);
  eq(textOnlyContents([{ role: "user", parts: [{ fileData: { fileUri: "https://youtu.be/x" } }] }]), null);
  eq(textOnlyContents([{ role: "user", parts: [{ text: "a" }, { fileData: {} }] }]), null);
  eq(textOnlyContents([{ role: "system", parts: [{ text: "a" }] }]), null);
  eq(textOnlyContents([]), null);
  eq(textOnlySystemInstruction(undefined), undefined);
  eq(textOnlySystemInstruction({ parts: [{ text: "s" }] }), { parts: [{ text: "s" }] });
  eq(textOnlySystemInstruction({ parts: [{ inline_data: {} }] }), null);
  eq(textOnlySystemInstruction("s"), null);
});
