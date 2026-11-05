# AI Cost Model

Status: estimate, 2026-11-05. Branch base: `claude/production-readiness-hardening`.
All dollar figures are USD. Token counts are estimates from the code, not measurements; replace them with real `usageMetadata` once logging exists (see "Instrument first").

## 1. Prices used

Source: web search of third-party aggregators (the official page, ai.google.dev/gemini-api/docs/pricing, was not reachable from the research sandbox). **Re-verify against the official page before launch.** Gemini bills thinking tokens at the output rate.

| Model | Input / 1M | Output (incl. thinking) / 1M | Confidence |
|---|---|---|---|
| gemini-2.5-flash | $0.30 | $2.50 | High (multiple sources agree) |
| gemini-2.5-flash-lite | $0.10 | $0.40 | High |
| gemini-3.5-flash | $1.50 | $9.00 | Medium (single source) |
| gemini-3.1-flash-lite | $0.25 | $1.50 | Medium (single source) |

Cached input is about 10% of the input price. Not modelled (the system prompt is a candidate for implicit caching; upside only).

Sources: [pricepertoken 2.5 Flash](https://pricepertoken.com/pricing-page/model/google-gemini-2.5-flash), [anotherwrapper 2.5 Flash-Lite](https://anotherwrapper.com/llm-pricing/gemini-2.5-flash-lite), [anotherwrapper Flash-Lite vs 3.5 Flash](https://anotherwrapper.com/tools/llm-pricing/gemini-2.5-flash-lite/gemini-3.5-flash), [morphllm Gemini pricing](https://www.morphllm.com/gemini-api-pricing).

**Important code fact:** `supabase/functions/ai-proxy/index.ts` currently allows only `gemini-3.5-flash` and `gemini-2.5-flash` (`ALLOWED_MODELS`). Flash-Lite routing needs a proxy change. The proxy also caps thinking at budget 1024 / level `low`, so the pending coach-v3 "medium thinking for plans" needs a proxy change too (and raises cost, below).

## 2. Tokens per call (estimated)

Caps come from `Lightstack/Core/Services/AIRequestOptions.swift` (`forTask`). Prompt sizes from `CoachPromptService.swift` (system prompt of roughly 140 lines plus the per-request message with last-session sets, trends and profile).

| Task | Input | Visible output | Thinking | Output cap | Thinking setting |
|---|---|---|---|---|---|
| Plan (today) | 3,500 | 1,200 | ~800 | 6,144 | low |
| Plan (coach-v3, medium) | 3,500 | 1,200 | ~4,300 (+2-5k) | 6,144 | medium |
| Chat turn | 2,000 | 300 | 0 | 1,000 | minimal |
| Post-workout review | 2,500 | 400 | 0 | 800 | minimal |
| Month plan | 3,000 | 2,500 | 0 | 4,000 | minimal |
| Form feedback | 1,500 | 300 | 0 | 600 | minimal |

Chat input grows with history; budget 2-4k late in a conversation. Treat 2,000 as the mean.

## 3. Cost per call

| Task | 2.5-flash | 3.5-flash | 2.5-flash-lite | 3.1-flash-lite |
|---|---|---|---|---|
| Plan (today) | $0.0061 | $0.0233 | $0.0012 | $0.0039 |
| Plan (coach-v3) | $0.0148 | $0.0548 | $0.0026 | $0.0091 |
| Chat turn | $0.0014 | $0.0057 | $0.0003 | $0.0010 |
| Post-workout | $0.0018 | $0.0074 | $0.0004 | $0.0012 |
| Month plan | $0.0072 | $0.0270 | $0.0013 | $0.0045 |
| Form feedback | $0.0012 | $0.0050 | $0.0003 | $0.0008 |

## 4. User profiles (per month)

| Profile | Plans | Chat turns | Post-workout | Month plans | Form feedback |
|---|---|---|---|---|---|
| Low | 4 | 10 | 2 | 0 | 0 |
| Average | 12 (3/wk) | 40 | 10 | 1 | 5 |
| Heavy | 24 | 150 | 20 | 4 | 30 |

Blended active-user mix used below: 50% low, 40% average, 10% heavy.

### Cost per user per month, single model for everything (plans at today's thinking)

| Model | Low | Average | Heavy | Blended |
|---|---|---|---|---|
| 2.5-flash | $0.04 | $0.16 | $0.45 | **$0.13** |
| 3.5-flash | $0.17 | $0.63 | $1.82 | $0.52 |
| 2.5-flash-lite | $0.01 | $0.03 | $0.10 | $0.03 |
| 3.1-flash-lite | $0.03 | $0.11 | $0.30 | $0.09 |

### Same, with coach-v3 medium-thinking plans

| Model | Low | Average | Heavy | Blended |
|---|---|---|---|---|
| 2.5-flash | $0.08 | $0.26 | $0.66 | **$0.21** |
| 3.5-flash | $0.29 | $1.01 | $2.57 | $0.81 |
| 2.5-flash-lite | $0.01 | $0.05 | $0.13 | $0.04 |
| 3.1-flash-lite | $0.05 | $0.17 | $0.43 | $0.13 |

### Monthly bill by active-user count (blended mix)

| Setup | 100 users | 1,000 users | 10,000 users |
|---|---|---|---|
| 2.5-flash everywhere (today's plans) | $13 | $128 | $1,282 |
| 2.5-flash everywhere (coach-v3 plans) | $21 | $209 | $2,087 |
| 3.5-flash everywhere (today's plans) | $52 | $517 | $5,169 |
| 3.5-flash everywhere (coach-v3 plans) | $81 | $807 | $8,067 |
| Routed: plans 2.5-flash, rest 2.5-flash-lite (today) | $8 | $77 | $771 |
| Routed: plans 2.5-flash, rest 2.5-flash-lite (coach-v3) | $16 | $158 | $1,576 |
| Routed: plans 3.5-flash, rest 2.5-flash-lite (coach-v3) | $54 | $541 | $5,410 |
| 2.5-flash-lite everywhere (coach-v3) | $4 | $40 | $402 |

Reading: model choice is a 4-6x lever; thinking on plans is a ~1.6x lever; user behaviour (heavy chat users) is another ~3x within a model.

## 5. Routing recommendation

1. **Plans** (the product's core, JSON-structured, quality matters): `gemini-2.5-flash`. Use `gemini-3.5-flash` only if side-by-side plan quality testing shows a clear gain; at 4x the price it is hard to justify below a $9.99 plan.
2. **Chat, post-workout summaries, form feedback, history import**: `gemini-2.5-flash-lite` (or 3.1-flash-lite if 2.5-lite quality is poor). Roughly 4x cheaper, short outputs, no thinking needed. Chat that returns a workout-modification JSON may need plan-tier quality; route by whether the turn can emit a modification (try lite first, fall back to flash on JSON parse failure).
3. **Month plan**: `gemini-2.5-flash`, no thinking (matches today's `.minimal`).
4. Add the lite models to `ALLOWED_MODELS` and add a server-side per-task default so the app cannot pick an expensive model by itself (the proxy trusts `body.model` from the client today).
5. Keep coach-v3 medium thinking to plan generation only, and cap plan thinking budget server-side (for example 4,096). Never medium for chat.
6. Try implicit/explicit context caching for the ~1.2k-token static system prompt; saves about 5-10% on input only, low priority.

## 6. Pricing recommendation

Assumptions: paying users skew heavier than the blended mix (use the Average-to-Heavy range, routed, coach-v3: about $0.20-0.70/month). Other variable costs are small (Supabase is flat tier; Open Food Facts is free).

- **Apple's cut:** 15% under the App Store Small Business Program (proceeds under $1M/yr) and for subscriptions after year one; 30% otherwise. Plan for 30% in year one if not enrolled.
- **Subscription:** **$6.99/month or $49.99/year** (about $4.17/month). Net after 30%: $4.90/month or $35.00/year. Worst-case AI cost for a heavy routed user: about $0.70. Gross margin on AI above 85% even at the heavy end and 30% cut; blended above 95%. A $4.99/month tier still works (net $3.49 at 30%) if you want a lower price point; margins stay above 80%.
- **Free tier** (target cost under $0.05 per free user per month):
  - 4 AI-generated plans per month (about one a week).
  - 20 chat turns per month, 2 post-workout reviews per week.
  - No month plans and no form feedback (or 3 form feedbacks to showcase it).
  - Core logging, history, progress, backup stay free and unlimited (they cost nothing in AI).
  - Expected cost of a fully-using free user on the routed setup: about $0.04-0.06.
- **Free-to-paid break-even:** each free user costs about $0.03-0.06 per month, so 1 paying user per ~100 free users covers the free base. A 2-5% conversion rate is comfortably profitable.
- The current app has **no paywall or StoreKit code**. Subscriptions require StoreKit 2 work plus server-side entitlement checks; budgets below assume entitlement is stored in a Supabase table the proxy can read.

## 7. Budgets and caps

Today: 10 requests/minute and 100 requests/day per user (`check_rate_limit`), with no cost weighting. 100 daily coach-v3 plan calls on gemini-3.5-flash would be about $5.50 per user per day, so request count alone is not a safe cap.

Recommended (weight calls by cost units; for example plan = 5, month = 5, chat/post/form = 1):

| Control | Free | Paid |
|---|---|---|
| Per-minute requests | 6 | 10 |
| Daily cost units | 15 (about 3 plans or 15 chats) | 60 |
| Monthly cost units | 60 | 400 |
| Hard monthly dollar ceiling per user (server-computed from `usageMetadata`) | $0.15 | $1.50 |
| Max output tokens | per-task caps in `AIRequestOptions` (keep) | same |
| Max thinking budget (server-enforced) | 1024 | 4096, plans only |
| Max request body | 200k chars today; tighten to ~40k chars (3-4k token prompts need about 16k) | same |

On exceeding a cap, return the existing 429 shape with a specific message ("You have used this month's free plans. Upgrade for more.") so the app can show an upgrade prompt instead of a generic error.

Global controls:

- **Global daily kill-switch:** a `global_ai_budget` row/function; when estimated spend for the UTC day exceeds a threshold (for example 3x expected daily spend), the proxy returns 503 "Coach is busy" for free users first, then everyone.
- **Google Cloud:** project budget with alerts at 50/90/100% of expected monthly spend, plus Gemini API per-project quota (requests/min and tokens/min) set to about 3x peak expectation. Budgets only alert; quotas actually stop spend. See `docs/release/RELEASE_CHECKLIST.md`.
- **Suggested monthly budget alerts:** 1,000 users at about $200 expected: alerts at $100/$200/$400, quota ceiling that cannot exceed about $600/month.
- Dedupe/guard retries: the proxy refunds a rate-limit slot on upstream 5xx/timeout (good) but a client that retries a 45s timeout still pays Google if the upstream actually completed. Keep the 45s timeout, and add an idempotency key per generation.

## 8. Instrument first

Before trusting any number above:

1. Have `ai-proxy` read `usageMetadata` (`promptTokenCount`, `candidatesTokenCount`, `thoughtsTokenCount`) from every Gemini response and write a row `(user_id, task, model, in, out, thoughts, cost_usd, at)` to an `ai_usage` table. This is also what enforces the dollar ceilings above.
2. Add `task` to the request (the app already knows it via `AITask`; it is only used for a DEBUG counter today).
3. After two weeks of TestFlight, replace this document's token assumptions with measured p50/p90 per task.
