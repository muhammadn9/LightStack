# AI Setup

The app never contains an AI key. All AI calls go through the `ai-proxy` Supabase Edge Function.

```
App (GeminiService) ──Bearer <user session token>──▶ ai-proxy ──x-goog-api-key──▶ Gemini
                                                       │
                                                       └─ check_rate_limit()  (10/min, 100/day per user)
```

## How it works

1. `GeminiService` posts `{ model, system_instruction, contents, generationConfig }` to `<SUPABASE_URL>/functions/v1/ai-proxy`, signed with the user's session.
2. The function verifies the user and calls `check_rate_limit()` as that user. If the check itself fails, the request is refused.
3. The function forwards the request to Gemini with the `GEMINI_API_KEY` secret in a header. It allows only `gemini-3.5-flash` and `gemini-2.5-flash` and caps output tokens.
4. Gemini's response, including its status code, is passed straight back. The app keeps its existing parsing, 503 retry and model fallback (3.5 → 2.5).
5. The function's own refusals (rate limit, not signed in) carry an `x-ai-proxy-error` header. The app shows those messages as-is and doesn't retry another model.

## Changing the key

Supabase dashboard → project → **Edge Functions → Secrets** → edit `GEMINI_API_KEY`. No app release is needed.

## Changing the limits

Edit `v_max_minute` / `v_max_day` in `supabase/migrations/harden_ai_rate_limit.sql` (mirrored in `supabase_schema.sql`) and run it in the SQL Editor.

## Redeploying the function

Paste `supabase/functions/ai-proxy/index.ts` into the dashboard editor (Edge Functions → `ai-proxy`), or run `supabase functions deploy ai-proxy` with the Supabase CLI. Keep **JWT verification on**.

## Adding another provider

Add a branch in the Edge Function, with its key stored as another secret, and choose it by `model`. Never add a key to `Secrets.xcconfig` or `Info.plist`.
