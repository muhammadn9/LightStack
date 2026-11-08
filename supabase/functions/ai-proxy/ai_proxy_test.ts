// Run: deno test supabase/functions/ai-proxy/ai_proxy_test.ts   (no network, no external imports)
import { cleanRequestId, mapReserveReason, parseUsage } from "./budget.ts";
import {
  checkContentsAndTools,
  chooseModel,
  clampOutputTokens,
  clampThinking,
  inputChars,
  isGoogleSearchTools,
  resolveTask,
  TASKS,
  textOnlyContents,
  textOnlySystemInstruction,
  validateContents,
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

// ---- Meal estimation (nutrition phase 4): one photo + search, only for mealEstimate ----
const B64 = "QUJDREVGRw==";
const img = (mime = "image/jpeg", data = B64) => ({ inline_data: { mime_type: mime, data } });
const SEARCH = [{ google_search: {} }];
const mealContents = (...extra: unknown[]) => [{ role: "user", parts: [{ text: "Chipotle bowl" }, ...extra] }];

Deno.test("mealEstimate task: limits, flags, and phase 4's request fits", () => {
  const m = TASKS.mealEstimate;
  eq([m.allowImages, m.allowSearch], [1, true]);
  eq(resolveTask("mealEstimate"), { ok: true, name: "mealEstimate" });
  if (m.maxOutputTokens < 3000 || m.maxOutputTokens > 4096) throw new Error("output cap");
  eq(clampOutputTokens("mealEstimate", 3000), 3000);
  eq(clampThinking("mealEstimate", "gemini-2.5-flash", { thinkingBudget: 1024 }), { thinkingBudget: 1024 });
  eq(clampThinking("mealEstimate", "gemini-3.5-flash", { thinkingLevel: "medium" }), { thinkingLevel: "low" });
  if (m.reserveUsd < 0.035) throw new Error("reserve must cover search grounding");
  // Only mealEstimate may take images or search.
  for (const [name, spec] of Object.entries(TASKS)) {
    if (name !== "mealEstimate" && (spec.allowImages !== 0 || spec.allowSearch)) throw new Error(`${name} must not allow media or tools`);
  }
});

Deno.test("mealEstimate accepts one jpeg or png and the search tool", () => {
  const a = checkContentsAndTools("mealEstimate", mealContents(img()), SEARCH);
  eq(a.ok && [a.images, a.useSearch], [1, true]);
  const b = checkContentsAndTools("mealEstimate", mealContents(img("image/png")), undefined);
  eq(b.ok && [b.images, b.useSearch], [1, false]);
  const c = checkContentsAndTools("mealEstimate", mealContents(), SEARCH);
  eq(c.ok && [c.images, c.useSearch], [0, true]);
});

Deno.test("mealEstimate rejects 2 images, pdf/video/gif mime, bad base64, extra keys, other tools", () => {
  eq(checkContentsAndTools("mealEstimate", mealContents(img(), img()), undefined).ok, false);
  eq(checkContentsAndTools("mealEstimate", [{ role: "user", parts: [img()] }, { role: "user", parts: [img()] }], undefined).ok, false);
  for (const mime of ["application/pdf", "video/mp4", "image/gif", "image/webp"]) {
    eq(checkContentsAndTools("mealEstimate", mealContents(img(mime)), undefined).ok, false, mime);
  }
  eq(checkContentsAndTools("mealEstimate", mealContents(img("image/jpeg", "not base64!!")), undefined).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents(img("image/jpeg", "")), undefined).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents({ inline_data: { mime_type: "image/jpeg", data: B64, extra: 1 } }), undefined).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents({ fileData: { fileUri: "https://x" } }), undefined).ok, false);
  eq(checkContentsAndTools("mealEstimate", [{ role: "system", parts: [{ text: "a" }] }], undefined).ok, false);
  eq(checkContentsAndTools("mealEstimate", [{ role: "user", parts: Array(9).fill({ text: "a" }) }], undefined).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents(), [{ code_execution: {} }]).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents(), [{ google_search: {} }, { code_execution: {} }]).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents(), [{ google_search: { x: 1 } }]).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents(), [{ function_declarations: [] }]).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents(), []).ok, false);
  eq(checkContentsAndTools("mealEstimate", mealContents(), null).ok, false);
  eq(isGoogleSearchTools(SEARCH), true);
});

Deno.test("every other task and legacy still reject images and tools", () => {
  for (const name of ["plan", "chat", "postWorkout", "monthPlan", "formFeedback", "other", "legacy"] as const) {
    eq(checkContentsAndTools(name, mealContents(img()), undefined).ok, false, `${name} image`);
    eq(checkContentsAndTools(name, mealContents(img("image/png")), undefined).ok, false, `${name} png`);
    eq(checkContentsAndTools(name, mealContents(), SEARCH).ok, false, `${name} search`);
    eq(checkContentsAndTools(name, mealContents(img()), SEARCH).ok, false, `${name} both`);
    eq(checkContentsAndTools(name, mealContents(), undefined).ok, true, `${name} text ok`);
  }
  eq(validateContents(mealContents(img()), 0), null);
});

Deno.test("legacy (no task id) is not meal estimation and cannot ask for it by media", () => {
  eq(resolveTask(undefined, true), { ok: true, name: "legacy" });
  eq(checkContentsAndTools("legacy", mealContents(img()), SEARCH).ok, false);
  eq(TASKS.legacy.allowImages, 0);
});
