# Multi-Provider AI Setup

This app automatically rotates between Gemini, OpenAI (ChatGPT), and Claude when rate limits are hit.

## How It Works

1. **Priority Order**: Gemini → OpenAI → Claude
2. **Automatic Fallback**: When one provider hits rate limit, automatically tries the next
3. **Rate Limit Tracking**: Remembers when each provider will be available again
4. **Smart Retry**: Extracts retry-after time from API error responses

## Setup Instructions

### 1. Add New Files to Xcode

Right-click on `Lightstack/Core/Services` folder in Xcode and select "Add Files to Lightstack":
- `AIProvider.swift`
- `AIServiceManager.swift`
- `OpenAIService.swift`
- `ClaudeService.swift`

Make sure "Copy items if needed" is **unchecked** and target is **Lightstack**.

### 2. Add API Keys to Secrets.xcconfig

Edit `Lightstack/Secrets.xcconfig` and add:

```
// Existing
SUPABASE_URL = your_supabase_url
SUPABASE_ANON_KEY = your_supabase_key
GEMINI_API_KEY = your_gemini_key

// NEW: Add these
OPENAI_API_KEY = your_openai_key
CLAUDE_API_KEY = your_claude_key
```

### 3. Update Info.plist

Add the new API keys to `Info.plist`:

```xml
<key>OPENAI_API_KEY</key>
<string>$(OPENAI_API_KEY)</string>
<key>CLAUDE_API_KEY</key>
<string>$(CLAUDE_API_KEY)</string>
```

### 4. Get Free Tier API Keys

#### Gemini (Already have)
- Free tier: 1,500 requests/day
- Model: gemini-2.0-flash

#### OpenAI ChatGPT
1. Go to https://platform.openai.com/api-keys
2. Create new key
3. Free tier: $5 credit for 3 months
4. Model: gpt-4o-mini

#### Claude
1. Go to https://console.anthropic.com/settings/keys
2. Create new key
3. Free tier: Rate-limited but generous
4. Model: claude-3-5-haiku

## Testing

1. Build and run the app
2. Try generating a workout or month plan
3. Watch console logs:
   ```
   [AIServiceManager] Starting chat generation with 3 providers available
   [AIServiceManager] Trying provider: Gemini
   [AIServiceManager] ❌ Failed with Gemini: rate limit
   [AIServiceManager] Marked Gemini as rate limited until ...
   [AIServiceManager] Trying provider: OpenAI
   [AIServiceManager] ✅ Success with OpenAI
   ```

## Rate Limit Reset

Rate limits are stored in UserDefaults with keys:
- `gemini_rate_limit_until`
- `openai_rate_limit_until`
- `claude_rate_limit_until`

To manually clear:
```swift
UserDefaults.standard.removeObject(forKey: "gemini_rate_limit_until")
```

Or delete the app to clear all UserDefaults.

## Current Usage

The AIServiceManager is used by:
- `WorkoutSessionService` (workout plan generation)
- `MonthPlanService` (month plan generation)
- `CoachChatViewModel` (AI coach chat)

All AI requests automatically benefit from the fallback system!
