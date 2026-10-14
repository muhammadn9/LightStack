# Lightstack — System Architecture (as of main 5539be5)

Verified against the code on 2026-10-13. Paths are relative to the repo root; app code is under `Lightstack/`.

> **`docs/BLUEPRINT.md` is outdated.** It describes a two-tab Today/Month layout and a client-side Gemini key. Today the app has four tabs, Today / History / Progress / Profile (`App/MainTabView.swift`). A Month tab exists only behind `FeatureFlags.monthTabEnabled = false` (`Core/Utilities/FeatureFlags.swift`). AI calls go through the `ai-proxy` Supabase Edge Function (`supabase/functions/ai-proxy/index.ts`). No AI key ships in the app. Settings is no longer a tab; `Features/Settings/SettingsView.swift` still exists.

## 1. Architecture map

### Presentation
- **Entry:** `App/LightstackApp.swift` creates `AppEnvironment` and injects it as an environment object. `App/RootView.swift` routes on `AppEnvironment` flags in this order: `needsEmailVerification` shows `EmailVerificationView`; `!isAuthenticated` shows `LoginView`; `!hasCompletedOnboarding` shows `OnboardingView`; otherwise `MainTabView`.
- **Tabs:** `MainTabView` holds Today (`TodayTabContent`, backed by `TodayViewModel`), History (`HistoryListView`), Progress (`ProgressTabView`), Profile (`ProfileView`) and, only when the flag is on, Month (`MonthPlanView`).
- **ViewModels:**
  - `TodayViewModel` owns the Today phase machine `TodayPhase`: setup, generating, confirmation, active, postWorkout.
  - `ActiveWorkoutViewModel` handles live logging UI, the elapsed clock and rest timers.
  - `WorkoutSetupViewModel`, `HistoryViewModel`, `ProfileViewModel`, `CoachChatViewModel`, `MonthPlanViewModel`, `PlanBuilderViewModel`, `FormAnalysisViewModel`.
  - `ProgressTabView` has no ViewModel; it uses `Features/Progress/Services/ProgressStatsService.swift`.
- **Feature folders:** Today, History (incl. import), Progress, Profile, AICoach, Auth, MonthPlan, FormAnalysis, Settings. Theme lives in `Core/Theme`.

### Dependency management: `AppEnvironment` (`App/AppEnvironment.swift`)
A single DI container (`ObservableObject`, also the `AuthServiceDelegate`). Its `init` builds, in order:
- `SupabaseClient` (PKCE auth flow, `flowType: .pkce`, redirect `lightstack://auth-callback`).
- `AuthService`, `LocalStorageService` (then `removeDuplicateExercises()` at launch), `SupabaseService`, `OfflineQueueManager`, `SyncService`, `ValidationService`.
- Two `GeminiService` instances (`gemini-3.5-flash`, fallback `gemini-2.5-flash`) pointing at the proxy URL, wrapped in `AIServiceManager`. Under UI-test mode this is replaced by a fake provider.
- `WorkoutStatsService`, `WorkoutSessionPersistence`.
- Repositories: `ProfileRepository`, `WorkoutRepository`, `PRRepository`, `MonthPlanRepository`, and `ExerciseMergeService`.
- `CoachPromptService`, `CoachContextBuilder`, `WorkoutSessionService`, `MonthPlanService`, `NotificationService`.

Factories: `makeTodayViewModel`, `makeInlineTodayViewModel` (fresh `WorkoutSessionService`, for inline flows), `makeWorkoutSetupViewModel`, `makeActiveWorkoutViewModel`, `makeProfileViewModel`, `makeHistoryViewModel`, `makeCoachChatViewModel`, `makeMonthPlanViewModel`, `makePlanBuilderViewModel`.

Lifecycle hooks:
- `checkExistingSession()` at init sets `isAuthenticated` from the Supabase session and `hasCompletedOnboarding` from the local profile.
- `authServiceDidSignIn` sets auth flags, checks the local profile, and calls `syncService.triggerFlush()`.
- `authServiceDidSignOut` resets flags and calls `offlineQueueManager.clearQueue()`.
- `authServiceNeedsEmailVerification` and `authService(_:didFailWith:)` set the verification and error state.

### Domain / services
| Component | File | Notes |
|---|---|---|
| `WorkoutSessionService` | `Features/Today/Services/WorkoutSessionService.swift` | Plan generation, start/resume, log set, finish, save, rolling summary, plan parsing (JSON, then markdown fallback). Delegate: `WorkoutSessionServiceDelegate` (implemented by `TodayViewModel`). |
| `WorkoutStatsService` | `Core/Services/WorkoutStatsService.swift` | Read-only stats over Core Data for Profile. |
| `ValidationService` | `Core/Services/ValidationService.swift` | Thin DI wrapper over `Core/Utilities/InputSanitizer.swift`. |
| `ExerciseMergeService` | `Core/Services/ExerciseMergeService.swift` | Rename exercises locally, recalculate PRs, sync rename (queue on failure). |
| `MonthPlanService` | `Features/MonthPlan/Services/MonthPlanService.swift` | Exists. AI month-plan generation and parsing; UI hidden by the feature flag. |
| Others | `ExerciseNameResolver`, `EquipmentClassifier`, `ExerciseGuideLibrary`, `RestPreference`, `NotificationService`, `WorkoutImport{Parser,Prompt,Service}` | Supporting services. |

### Persistence
- **`LocalStorageService`** (`Core/Services/LocalStorageService.swift`): Core Data `NSPersistentContainer("Lightstack")` with lightweight auto-migration. The store failing to load is a `fatalError`. The model `Lightstack.xcdatamodeld` has three versions, with `Lightstack 3.xcdatamodel` current (`.xccurrentversion`). Version 2 added `supersetGroupId`; version 3 added the `CDRestDay` entity. Entities: `CDUserProfile`, `CDWorkout`, `CDExercise`, `CDWorkoutSet`, `CDPersonalRecord`, `CDMonthPlan`, `CDPlannedSession`, `CDAIContextSummary`, `CDRestDay`.
- **Repositories** (local-first, then fire-and-forget remote write, queue on failure):
  - `WorkoutRepository`: workouts, exercises, sets, import, replace.
  - `ProfileRepository`: profile plus the only remote-to-local pull, `syncProfileFromRemote`.
  - `PRRepository`: PR detection and recalculation.
  - `MonthPlanRepository`: plans and sessions; `syncPlanFromRemote` runs only if a local plan exists.
- **`SupabaseService`** (`Core/Services/SupabaseService.swift`): plain PostgREST calls. Writes are `.insert` except `profiles` and `ai_context_summaries`, which are upserts.
- **Other stores:** `UserDefaults` holds the offline queue (`lightstack_offline_queue_v1`), the saved workout session (`com.lightstack.activeWorkoutSession`) and UI prefs. Keychain (`KeychainService`) holds the pending email-verification password.

### Sync
- `OfflineQueueManager` (`Core/Utilities/OfflineQueueManager.swift`): actor. 15 operation types, persisted as JSON in `UserDefaults`. `flush()` runs in FK-dependency order.
- `SyncService` (`Core/Services/SyncService.swift`): `NWPathMonitor`. Calls `triggerFlush()` on an offline-to-online transition. `AppEnvironment` also calls it after sign-in.
- There is no remote-to-local hydration of workouts, exercises, sets or PRs (see section 3).

### AI
- `AIServiceManager` (`Core/Services/AIServiceManager.swift`): tries providers in order. Proxy refusals (domain `AIProxy`) surface as-is. Rate-limit/503/unavailable-style errors fall to the next provider, which is the fallback model.
- `GeminiService` (`Features/AICoach/Services/GeminiService.swift`): POSTs to `<SUPABASE_URL>/functions/v1/ai-proxy` with the user JWT as Bearer plus the anon key. Retries HTTP 503 up to 3 times with 1s/2s/4s backoff. Retries once without `thinkingConfig` if Gemini rejects it.
- `supabase/functions/ai-proxy/index.ts`: verifies the user (`auth.getUser`), caps the body at 200k chars, allows only two models, clamps the generation config, calls the `check_rate_limit` RPC (10/min, 100/day; fail closed), then forwards to Gemini with a server-side key.
- `CoachContextBuilder` builds profile, rolling summary and the last 2 sessions of the same type from local data.
- `CoachPromptService` builds system and user prompts per task: plan, chat, postWorkout, month plan.
- `CoachChatViewModel`: chat state; first tries `LocalChatCommandParser` (remove / add sets / swap / rest). Otherwise it calls the AI, then parses with `WorkoutModificationJSONParser` (falling back to the legacy pipe-format `WorkoutModificationParser`).
- `ModificationConfirmationSheet` lists proposed changes. Apply calls `TodayViewModel.applyModification`.
- `PostWorkoutReply` parses the single post-workout JSON `{note, summary}`.

## 2. State ownership

| State | Owner | Notes |
|---|---|---|
| Active workout exercises (list, order, targets) | `TodayViewModel.exercises` | Mutated by `applyModification`, add/remove/reorder, superset linking. Persisted to Core Data via `WorkoutRepository` and to the session snapshot. |
| Logged sets, authoritative | `TodayViewModel.loggedSets` | Written by `TodayViewModel.logSet` and `deleteLoggedSet`. Feeds persistence, post-workout AI and chat context. |
| Logged sets, display copy | `ActiveWorkoutViewModel.loggedSets` | Seeded from Today's copy on appear (`ActiveWorkoutView` line 48). The view mirrors the PR flag into it after `todayViewModel.logSet` returns. |
| Pending (typed, unlogged) set rows | `ActiveWorkoutViewModel.pendingSets` | Snapshotted into `TodayViewModel.pendingSetsSnapshot` and the session state for relaunch; restored on appear. |
| Session persistence | `WorkoutSessionPersistence` (`UserDefaults`) | `TodayViewModel.saveSessionState()` stores workout, exercises, logged sets, phase, elapsed, hints, set targets, pending sets and pause flag. Stale after 24h. Cleared by `resetToSetup`. |
| Elapsed workout clock | `ActiveWorkoutViewModel` / `WorkoutClock`; mirrored to `TodayViewModel.activeWorkoutElapsed` | Restored on relaunch via `restoredElapsed` unless paused. |
| Rest timers | `ActiveWorkoutViewModel` (`restTimerTargetDates`, `activeRestExerciseId`, one `restTimerClock`) | Single active rest timer. Local notification scheduled via `onRestTimerStart` to `NotificationService`. |
| Current workout record | `WorkoutSessionService.currentWorkout / currentWorkoutId` | Also holds the pending rolling summary until the workout is saved. |
| Chat messages | `CoachChatViewModel.messages` | In memory only. `clearChat()` runs when Today returns to setup. `pendingModifications` lives here too. |
| Offline queue | `OfflineQueueManager` (`UserDefaults`) | Single key. Cleared on sign-out. |
| Auth session | Supabase SDK (`supabaseClient.auth`) | `AppEnvironment` mirrors it in `isAuthenticated`, `needsEmailVerification`. Verification password in Keychain. |
| Profile | Core Data `CDUserProfile` via `ProfileRepository` | Remote copy pulled only by `loadProfile` (Profile tab). |
| PRs | Core Data `CDPersonalRecord` via `PRRepository` | Detected on set log; rebuilt locally on edit/delete/merge/import and on Profile load. |
| Rolling AI summary | Core Data `CDAIContextSummary` (per user + workout type) | Written by `WorkoutSessionService.storeSummary`; upserted remotely. Read by `CoachContextBuilder`. |
| Month plans | Core Data via `MonthPlanRepository` | UI behind the feature flag. |
| Feature flags | `FeatureFlags` (compile-time constants) | `formAnalysisEnabled = true`, `monthTabEnabled = false`. |

## 3. Diagrams

### 3.1 Overall system architecture
```mermaid
flowchart TD
  subgraph Presentation
    Root[RootView] --> Tabs[MainTabView]
    Tabs --> TodayV[Today views + TodayViewModel]
    Tabs --> HistV[History views + HistoryViewModel]
    Tabs --> ProgV[ProgressTabView]
    Tabs --> ProfV[Profile views + ProfileViewModel]
    TodayV --> ActiveVM[ActiveWorkoutViewModel]
    TodayV --> ChatVM[CoachChatViewModel]
  end
  Env[AppEnvironment DI container]
  Env -.factories.-> TodayV
  Env -.factories.-> HistV
  Env -.factories.-> ProfV
  subgraph Domain
    WSS[WorkoutSessionService]
    Stats[WorkoutStatsService]
    Val[ValidationService]
    Merge[ExerciseMergeService]
    MPS[MonthPlanService]
  end
  TodayV --> WSS
  ProfV --> Stats
  HistV --> Merge
  subgraph Persistence
    WR[WorkoutRepository]
    PRR[PRRepository]
    PR[ProfileRepository]
    MPR[MonthPlanRepository]
    LS[(LocalStorageService - Core Data)]
    SB[SupabaseService]
  end
  WSS --> WR
  WR --> LS
  PRR --> LS
  PR --> LS
  MPR --> LS
  WR --> SB
  PRR --> SB
  PR --> SB
  MPR --> SB
  subgraph Sync
    OQ[OfflineQueueManager - UserDefaults]
    SS[SyncService - NWPathMonitor]
  end
  WR -->|on failure| OQ
  PRR -->|on failure| OQ
  PR -->|on failure| OQ
  SS -->|triggerFlush| OQ
  OQ --> SB
  subgraph AI
    Mgr[AIServiceManager]
    Gem[GeminiService x2 models]
    Proxy[[ai-proxy Edge Function]]
    CB[CoachContextBuilder]
    CP[CoachPromptService]
  end
  WSS --> Mgr
  ChatVM --> Mgr
  MPS --> Mgr
  Mgr --> Gem --> Proxy
  Proxy --> Gemini[(Gemini API)]
  WSS --> CB
  ChatVM --> CB
  CB --> LS
  SB --> Cloud[(Supabase Postgres + RLS)]
  Proxy --> Cloud
```

### 3.2 Authentication and onboarding
```mermaid
flowchart TD
  Launch[App launch] --> Check["AppEnvironment.checkExistingSession: session exists?"]
  Check -->|no| Login[LoginView]
  Check -->|yes| LocalProf{"Local profile in Core Data?"}
  LocalProf -->|yes| Main[MainTabView]
  LocalProf -->|no| Onb[OnboardingView]
  Login --> Method{Method}
  Method -->|email sign up| SignUp["signUp with redirect lightstack://auth-callback"]
  SignUp --> Verify["EmailVerificationView: user taps check, which re-signs in via checkEmailVerified, password kept in Keychain"]
  Verify -->|"signIn succeeds + emailConfirmedAt"| DidSignIn
  Verify -.->|link tapped| Deep["handleDeepLink: auth.session from url, PKCE"]
  Deep --> DidSignIn
  Method -->|email sign in| SignIn[auth.signIn]
  SignIn -->|"emailConfirmedAt nil"| Verify
  SignIn -->|confirmed| DidSignIn
  Method -->|Apple| Apple["SignInWithAppleButton + SHA256 nonce, signInWithIdToken"]
  Apple --> DidSignIn
  Method -->|Google| Google["GoogleSignIn SDK idToken, signInWithIdToken, fallback ephemeral web OAuth"]
  Google --> DidSignIn
  DidSignIn["authServiceDidSignIn: isAuthenticated = true"] --> LocalProf2{"fetchProfileSync - local only"}
  LocalProf2 -->|found| Main
  LocalProf2 -->|nil| Onb
  DidSignIn --> Flush[syncService.triggerFlush]
  Onb -->|"profileRepository.saveProfile"| Main
  Main -->|sign out| Out["authServiceDidSignOut: reset flags, clearQueue"]
  Out --> Login
```

### 3.3 Workout creation and completion
```mermaid
sequenceDiagram
  participant U as User
  participant S as WorkoutSetupView
  participant T as TodayViewModel
  participant W as WorkoutSessionService
  participant R as WorkoutRepository
  participant AI as AIServiceManager / ai-proxy
  participant A as ActiveWorkoutViewModel
  U->>S: choose type, time, energy, notes
  S->>T: generatePlan (phase = generating)
  T->>W: generatePlan
  W->>R: createWorkout (Core Data + background Supabase insert)
  W->>AI: plan prompt (context from CoachContextBuilder)
  AI-->>W: JSON plan (markdown table fallback)
  W->>R: deleteExercises + saveExercises
  W-->>T: didGeneratePlan (phase = confirmation)
  U->>T: confirmAndStartWorkout (phase = active)
  loop each set
    U->>A: type weight / reps / RIR
    A->>T: logSet
    T->>W: logSet
    W->>R: saveSet (Core Data + Supabase insert)
    T->>T: checkAndRecordPR, loggedSets, saveSessionState
  end
  U->>T: finishWorkout (phase = postWorkout)
  T->>W: finishSession (duration saved immediately)
  W->>AI: one call returns {note, summary}
  AI-->>W: note shown, summary held in memory
  U->>T: saveWorkout
  T->>W: saveCompletedWorkout
  W->>R: updateWorkout, reconcile removed exercises
  W->>W: store rolling summary, upsert remote or enqueue
  W-->>T: didSaveWorkout, resetToSetup
```

### 3.4 Offline to online sync (as it is today)
```mermaid
flowchart TD
  Write["User action, e.g. WorkoutRepository.saveSet"] --> Local["Write Core Data first"]
  Local --> Task["Detached Task, not awaited"]
  Task --> Remote{"Supabase call succeeds?"}
  Remote -->|yes| Done[Done]
  Remote -->|"no, any error"| Enq["OfflineQueueManager.enqueue: append to UserDefaults queue"]
  subgraph Triggers["Flush triggers - only these two"]
    NW["NWPathMonitor: offline to online"] --> TF
    SI["authServiceDidSignIn"] --> TF
  end
  TF["SyncService.triggerFlush: cancels previous Task, starts flush"] --> Load["flush: loadQueue snapshot, sort by FK order"]
  Enq --> Load
  Load --> Each["for each op: await execute"]
  Each -->|success| Next[Next op]
  Each -->|"failure: attempts += 1"| Keep{"attempts < 5?"}
  Keep -->|yes| Failed[Keep in failed list]
  Keep -->|no| Drop["Dropped silently"]
  Next --> Save
  Failed --> Save
  Drop --> Save
  Save["saveQueue of failed: overwrites persisted queue"]
  SO["Sign out"] --> Clear["clearQueue: unsynced ops deleted"]
  NoPull["No remote to local hydration: fetchWorkoutsForUser, fetchExercises, fetchSets, fetchPersonalRecords have no callers"]
```

### 3.5 AI chat and workout modifications
```mermaid
flowchart TD
  Msg[User sends message] --> San["validationService.sanitize"]
  San --> Local{"LocalChatCommandParser.parse matches?"}
  Local -->|yes| Reply["Append coach reply, e.g. Removing X."]
  Reply --> Pend
  Local -->|no| AI["aiServiceManager.generateChat, last 6 msgs + context message"]
  AI -->|failure| Err[Coach error bubble]
  AI -->|success| Strip["Strip JSON block for display"]
  Strip --> Parse["WorkoutModificationJSONParser, fallback WorkoutModificationParser"]
  Parse -->|"mods found"| Pend["pendingModifications + showModificationConfirmation"]
  Parse -->|"none, but JSON malformed or table"| Cant["Could not apply automatically message"]
  Parse -->|"none, plain answer"| End[Done]
  Pend --> Sheet[ModificationConfirmationSheet]
  Sheet -->|Cancel| Rej[rejectModifications]
  Sheet -->|Apply| Conf[confirmModifications]
  Conf --> Apply["TodayViewModel.applyModification per mod, preserveLoggedSets true"]
  Apply -->|"false: exercise not found"| Missing["Reported as Couldn't find X"]
  Apply -->|true| Sum["Chat line from appliedSummary"]
  Apply --> Persist["Update exercises, set targets, saveSessionState, targetsRevision += 1"]
```

### 3.6 Personal-record calculation
```mermaid
flowchart TD
  Log["TodayViewModel.logSet with reps > 0"] --> Check["PRRepository.checkAndRecordPR - NSLock"]
  Check --> E1["Epley e1RM = weight x (1 + reps / 30)"]
  E1 --> Cmp{"e1RM > stored PR e1RM?"}
  Cmp -->|no| NoPR[No PR]
  Cmp -->|yes| SaveLocal["savePersonalRecord (Core Data)"]
  SaveLocal --> Rem["Task: Supabase insertPersonalRecord, enqueue on failure"]
  SaveLocal --> Flag["set.isPR = true -> WorkoutRepository.updateSet (local only)"]
  Edit["History edit/delete, discard, delete logged set, exercise merge, import, remove exercise"] --> Recalc["recalculatePR(userId, name)"]
  ProfileLoad["ProfileViewModel stats load"] --> RecalcAll["recalculateAllPRs"]
  RecalcAll --> Recalc
  Recalc --> Del["deletePersonalRecord local"]
  Del --> Best["best remaining set by e1RM from Core Data"]
  Best --> SaveLocal2["savePersonalRecord local, dated to lifted date"]
  Recalc -.-> NoSync["No Supabase delete/insert: local only"]
```

### 3.7 Data ownership and dependencies
```mermaid
erDiagram
  AUTH_USERS ||--o| PROFILES : "user_id (unique)"
  AUTH_USERS ||--o{ WORKOUTS : "user_id"
  AUTH_USERS ||--o{ PERSONAL_RECORDS : "user_id"
  AUTH_USERS ||--o{ MONTH_PLANS : "user_id"
  AUTH_USERS ||--o{ PLANNED_SESSIONS : "user_id"
  AUTH_USERS ||--o{ AI_CONTEXT_SUMMARIES : "user_id, unique with workout_type"
  AUTH_USERS ||--o{ RATE_LIMITS : "user_id, service role only"
  WORKOUTS ||--o{ EXERCISES : "workout_id ON DELETE CASCADE"
  EXERCISES ||--o{ SETS : "exercise_id ON DELETE CASCADE"
  WORKOUTS ||--o{ PERSONAL_RECORDS : "workout_id nullable"
  MONTH_PLANS ||--o{ PLANNED_SESSIONS : "month_plan_id CASCADE"
  WORKOUTS ||--o{ PLANNED_SESSIONS : "workout_id nullable"
```
Core Data to Supabase mapping (all Core Data rows are scoped by `userId`, which is a column on `CDWorkout`, `CDUserProfile`, `CDPersonalRecord`, `CDMonthPlan` and `CDAIContextSummary`; exercises and sets are reached through the workout):

| Core Data entity | Supabase table | Ownership and RLS |
|---|---|---|
| `CDUserProfile` | `profiles` | `user_id = auth.uid()` (USING + WITH CHECK) |
| `CDWorkout` | `workouts` | same |
| `CDExercise` (to workout) | `exercises` | policy checks the parent workout's `user_id` |
| `CDWorkoutSet` (to exercise) | `sets` | policy joins exercises to workouts |
| `CDPersonalRecord` | `personal_records` | `user_id = auth.uid()` |
| `CDMonthPlan` | `month_plans` | same |
| `CDPlannedSession` | `planned_sessions` | same |
| `CDAIContextSummary` | `ai_context_summaries` | same |
| `CDRestDay` | none (local only) | n/a |
| none | `rate_limits` | RLS policy `service_role` only; written by the `check_rate_limit()` SECURITY DEFINER function |

Source: `supabase/supabase_schema.sql` plus `supabase/migrations/*.sql`. Core Data FKs are relationships (workout to exercises to sets), not UUID columns.
