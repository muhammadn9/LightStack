# AI cost controls

All Gemini traffic goes through the `ai-proxy` Edge Function. The server decides what is allowed and what it may cost. The app only names a task and sends a request id.

## How it works

1. **Task table** (`supabase/functions/ai-proxy/tasks.ts`). Each task (`plan`, `chat`, `postWorkout`, `monthPlan`, `formFeedback`, `other`) has allowed models, max input chars, max output tokens, max thinking and a cost reservation. The proxy clamps the app's config to it. Unknown task names become `other` (smallest limits). A missing thinking field is replaced by the task's own setting, so it can never mean unbounded dynamic thinking.
2. **Reserve** (`ai_reserve`, SQL). Before calling Gemini the proxy reserves the task's estimated cost. Under a global advisory lock and a per-user lock it checks: kill switch, in-flight requests per user, user day and month spend, global day and month spend. Spend is `reserved_usd` for open requests, otherwise `actual_usd`. Days and months are UTC.
3. **Settle** (`ai_settle`, SQL). After the call the proxy records `usageMetadata` token counts; cost = tokens / 1M x the model price in `ai_budget_config.prices` (thinking tokens use the `thinking` price). A failed upstream call costs 0. A success with no usage data, or an unpriced model, is charged at the reserved amount (conservative).
4. **Idempotency**. The app sends one `request_id` per logical request, reused for 503 retries and the fallback model. The ledger row is unique on `(user_id, request_id)`: a failed attempt is re-reserved on the same row, never counted twice. An in-flight or already successful id is refused with 409.
5. **Crash safety**. A reservation still open after 3 minutes is closed as `failed/expired` and charged at its reserved amount.
6. The existing rate limits (10/min, 100/day) still apply first. A budget refusal gives the rate-limit slot back.

The ledger stores ids, task, model, token counts, USD, status, latency and an error code. **No prompts or replies are stored.** Users can `SELECT` their own rows; only the service role writes.

### Errors (header `x-ai-proxy-error`)

| code | HTTP | meaning |
|---|---|---|
| `ai_disabled` | 503 | kill switch is off |
| `budget_global` | 503 | global day/month cap reached |
| `budget_user_daily` / `budget_user_monthly` | 429 | that user's cap reached |
| `too_many_in_flight` | 429 | too many open requests for the user |
| `invalid_task` / `invalid_model` | 400 | bad task, or model not allowed for the task |
| `input_too_large` | 413 | over the task's input cap |
| `duplicate_request` | 409 | same request id already in flight or done |
| `budget_unavailable` | 503 | budget check could not run (fails closed) |
| `rate_limit_minute` / `rate_limit_day` | 429 | existing rate limits |

The app maps these to "Daily AI limit reached, resets tomorrow." and "Coach temporarily unavailable." and does not try the second model for them.

## Changing limits and the kill switch

Run in the Supabase SQL editor. No app release is needed.

```sql
-- Kill switch
update ai_budget_config set ai_enabled = false, updated_at = now();   -- off
update ai_budget_config set ai_enabled = true,  updated_at = now();   -- on

-- Limits
update ai_budget_config set
  per_user_daily_usd = 0.50, per_user_monthly_usd = 5,
  global_daily_usd = 25, global_monthly_usd = 300,
  max_concurrent_per_user = 2, updated_at = now();

-- Prices (USD per 1M tokens)
update ai_budget_config set prices = '{
  "gemini-2.5-flash": {"input": 0.30, "output": 2.50, "thinking": 2.50},
  "gemini-3.5-flash": {"input": 0.50, "output": 3.00, "thinking": 3.00}
}'::jsonb, updated_at = now();

-- Spend today / this month
select date_trunc('day', created_at) d, task, model, count(*), sum(actual_usd) usd
from ai_usage_ledger where created_at >= date_trunc('month', now()) group by 1,2,3 order by 1 desc, usd desc;
```

**The seeded limits and prices are PLACEHOLDERS.** Web access was unavailable when this was written, so verify prices at https://ai.google.dev/gemini-api/docs/pricing (the `gemini-2.5-flash` figures are the last known list price; the `gemini-3.5-flash` figures are a guess) and set limits that fit your pricing before launch.

## Model routing (recommendation)

The app currently sends `gemini-3.5-flash` first and `gemini-2.5-flash` as fallback for every task. The server task table marks `chat`, `postWorkout`, `formFeedback` and `other` as cheap-model tasks and `plan` / `monthPlan` as current-model tasks. Routing is **off by default** (no behaviour change). To turn it on, set the function secret `AI_MODEL_ROUTING=1`: cheap tasks then always use `gemini-2.5-flash` with minimal thinking, and plans keep the current model. Same model family, lower cost; check reply quality for chat first. Turn it off by removing the secret.

## Deploy order

1. Apply the migration `20261105130000_ai_usage_ledger_budgets.sql`. Review the seeded limits and prices.
2. Run `supabase/tests/ai_budget.sql` (rolls back) and check it prints `AI BUDGET OK`.
3. Deploy the function: `supabase functions deploy ai-proxy`. It needs `SUPABASE_SERVICE_ROLE_KEY` (provided automatically). It fails closed with `budget_unavailable` if the migration is missing, so do not deploy it first.
4. Release the app. Older app builds keep working: they send no task, so they run as `other` (cheap model only, 1024 output tokens, 20k chars). This can break their plan generation. If many users are on old builds, raise the `other` limits in `tasks.ts` temporarily or ship the app first.

## Manual concurrency test

Two SQL sessions, same user, `per_user_daily_usd` just above one reservation: call `ai_reserve` in both at once with different request ids. Exactly one returns `ok: true`. (This was verified with 6 parallel sessions against Postgres 16.)

## Google Cloud backstop for the Gemini key

The database caps only protect traffic that goes through the proxy. Add Google-side limits too.

**Budget alert:** Google Cloud Console -> Billing -> Budgets & alerts -> Create budget. Pick the billing account and the project that owns the key, set a monthly amount, and add alert thresholds (50%, 90%, 100%) with email. A budget only alerts; it does not stop spending.

**Quota cap:** Console -> APIs & Services -> Enabled APIs & services -> Generative Language API -> Quotas & System Limits. Find the requests-per-day and tokens-per-minute quotas for your model, open Edit quota and set a ceiling you are comfortable paying for. This is the hard stop.

If you must stop everything at once: set `ai_enabled = false` (SQL above), or rotate/delete the `GEMINI_API_KEY` secret.
