# Lightstack

A native iOS strength-training app with an AI coach, progressive-overload tracking and offline-first workout logging.

SwiftUI · Core Data · Supabase · Gemini (via a Supabase Edge Function) · iOS 17+

## Features

- **Today**
  - Week strip and an "Equipment Worked This Week" card.
  - Workouts can come from an AI-generated plan, a past workout, or manual logging.
- **Active workout**
  - One card per exercise, with every set visible at once.
  - Rest timer, supersets, mid-workout reordering, PR detection.
  - A coach chat that can change the workout after you confirm.
- **History**: every logged workout (in-app and imported), with editing.
- **Progress**: streak, workouts per week, training heatmap, estimated 1RM trends and Top Lifts.
- **Profile**: training stats, top lifts, settings (behind the gear).
- **Import**: paste workouts from notes or another AI and they're parsed into history.

## Architecture

```
Lightstack/
  App/            AppEnvironment (service wiring), RootView, MainTabView, UITestMode (DEBUG)
  Core/
    Models/       Workout, Exercise, WorkoutSet, PersonalRecord, …
    Repositories/ Core Data first, then Supabase sync (offline queue on failure)
    Services/     LocalStorageService (Core Data), SupabaseService, AIServiceManager, stats
    Theme/        AppTheme tokens, cards, equipment icons
  Features/       Today, History, Progress, Profile, AICoach, Auth, Settings, …
  DesignLab/      DEBUG-only design previews (launch with -designLab)
supabase/
  supabase_schema.sql   Tables, row-level security, rate-limit function
  migrations/           Incremental SQL changes
  functions/ai-proxy/   Edge Function: the app's only path to Gemini
```

- **Local-first.** Everything is written to Core Data first and synced to Supabase in the background. Failed syncs are retried from an offline queue.
- **AI never ships keys.** The app calls the `ai-proxy` Edge Function with the user's session token. The function enforces a per-user rate limit (10/min, 100/day) and calls Gemini with a server-side key. See [docs/AI_PROVIDER_SETUP.md](docs/AI_PROVIDER_SETUP.md).
- **Row-level security.** Every table is scoped to the signed-in user.

## Setup

1. **Requirements:** Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
2. **Secrets:** copy `Lightstack/Config/Secrets.xcconfig.template` to `Lightstack/Config/Secrets.xcconfig` and fill in:
   - `SUPABASE_URL` and `SUPABASE_ANON_KEY` (Supabase → Project Settings → API).
   - `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` (Google Sign-In).

   The file is git-ignored. Never put AI keys in it.
3. **Generate the project:** `xcodegen generate`. The `.xcodeproj` is generated from `project.yml`, so don't edit `project.pbxproj` by hand.
4. **Backend (first time only):**
   - Run `supabase/supabase_schema.sql`, then any files in `supabase/migrations/`, in the Supabase SQL Editor.
   - Deploy `supabase/functions/ai-proxy` with **JWT verification on**.
   - Add the `GEMINI_API_KEY` secret under Edge Functions → Secrets.
5. **Build:**
   ```
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Lightstack.xcodeproj -scheme Lightstack -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -quiet
   ```

## Testing

| Suite | Scheme | Notes |
|---|---|---|
| Unit | `Lightstack` | Pure logic: parsing, stats, streaks, migrations, security helpers |
| UI | `LightstackUITests` | Real flows on the simulator |

```
xcodebuild test -project Lightstack.xcodeproj -scheme Lightstack -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
xcodebuild test -project Lightstack.xcodeproj -scheme LightstackUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -resultBundlePath /tmp/ui.xcresult
```

**Test mode** exists in DEBUG builds only; Release/TestFlight contain none of it.
- `-uiTesting`: a fixed signed-in test user, a separate seeded store and a fake AI provider. It never touches real data or Gemini.
- `-uiTestingReset`: wipes and reseeds the test store first.
- `-appColorScheme light|dark`: forces a theme.

**Bug workflow:** reproduce the bug with a failing UI test, fix it, and keep the test as a regression guard. See `CLAUDE.md`.

## Releasing

Run the unit and UI suites, then `scripts/testflight-release.sh --skip-tests`. It needs `scripts/asc-config.sh`; see the template next to it. The script bumps the build number, archives, uploads and adds the build to the tester group. Commit the bump afterwards (`Info.plist`, `project.yml`, `project.pbxproj`).

## Contributing

Each change goes on its own branch off `main` (`claude/<topic>`) and is merged via a PR once the `xcodebuild` check passes. Code style rules live in `CLAUDE.md`: SwiftUI only, `AppTheme` tokens, no force-unwraps, no new dependencies without approval.
