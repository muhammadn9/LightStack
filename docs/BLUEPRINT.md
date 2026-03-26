# Lightstack iOS — Full Blueprint & Architecture

> Version 1.2 | March 2026 | Stack: Swift/SwiftUI · Supabase · Google Gemini

---

## 1. VISION

A native iOS personal trainer that behaves like an ongoing coaching relationship —
not a static plan generator. Walk into the gym, tell the coach your day, how much
time you have, and how you're feeling. The AI generates a fully personalized plan
informed by your entire training history, adapts in real time mid-session if you
want to switch focus or prioritize a lift, and stays in conversation before, during,
and after every session.

The core technical problem it solves: **AI context never gets full.** After each
session, the coach compresses that workout type's history into a rolling summary.
Every new session gets a focused, efficient prompt — ~700-850 tokens — regardless
of how long you've been training.

---

## 2. APP STRUCTURE — TABS

The app has two primary tabs:

### Tab 1 — Today (Daily Workout)
The main coaching experience. The user gets their workout for the day, logs it live,
and chats with the coach. If no month plan exists, the AI generates a workout on
demand from the user's profile and history. If a month plan exists, today's session
is pulled from it — but the user can always override, switch focus, or reprioritize.

### Tab 2 — Month Plan
A calendar-style view showing a full month of planned sessions. The user converses
with the AI to build the plan based on their current stats and a specific target
(e.g. "I want to hit 100 lb dumbbells on chest press in 8 weeks"). Once set, each
day is a tap-to-log tile. Days are marked complete as workouts are finished. The
user fills it out as they go — the plan is a guide, not a contract.

### Supporting Tabs
- **History** — past workout sessions with full set logs and AI notes
- **Profile** — stats, goals, equipment, coach preferences, streak

---

## 3. CORE FEATURES

| Feature | Tab | Phase |
|---|---|---|
| Auth (Email + Apple Sign-In) | — | 0 |
| User profile setup | Profile | 0 |
| Equipment selection | Profile | 0 |
| Today workout: AI plan generation | Today | 1 |
| Today workout: live set logging (table format) | Today | 1 |
| Today workout: post-workout AI progression note | Today | 1 |
| Streak / consistency tracking | Profile | 1 |
| Today workout: AI chat (pre / during / post) | Today | 2 |
| Rolling AI context summary system | — | 2 |
| Month plan: AI-guided month builder | Month Plan | 2 |
| Month plan: calendar view with completion tracking | Month Plan | 2 |
| Workout history list + session detail | History | 3 |
| PR detection and display | History / Today | 3 |
| Profile editing | Profile | 3 |
| Muscle group heatmap (modern redesign) | Profile | 3 |
| Offline mode with background sync | — | 4 |
| Security hardening + TestFlight | — | 4 |

---

## 4. COACHING PHILOSOPHY (drives AI prompt design)

These principles must be reflected in the system prompt, not just the UI:

- **Ongoing relationship, not a template.** The AI references your previous
  sessions specifically ("last chest day you hit 85s for 10 — let's try 90s today").

- **Live adaptability.** If the user says "actually let's go strength focus today"
  or "I want to prioritize bench" mid-conversation, the AI rebuilds the plan around
  that input without losing context.

- **Realistic talk.** The AI tells you what's actually achievable. If a weight jump
  is too aggressive, it says so. If you're grinding through a rough week, it
  acknowledges it and adjusts volume.

- **RIR-based intensity.** All sets use Reps In Reserve as the effort metric.
  1-2 RIR is the standard working target.

- **Table format for workout plans.** The AI always presents the session plan as a
  table: Exercise | Weight | Reps | RIR | Rest. The user can see the whole workout
  at a glance. This applies to the chat view and the active workout screen.

- **Post-session check-in.** After logging, the AI asks what weights were used, how
  the session felt (pump, fatigue, joints), and updates its targets for next time.

- **The ChatGPT system prompt (attached in repo as docs/COACH_PROMPT.md) is the
  canonical personality reference.** It must be parameterized with the user's live
  profile data on every call.

---

## 5. FOLDER STRUCTURE

```
Lightstack/
├── App/
│   ├── LightstackApp.swift
│   └── AppEnvironment.swift            # DI container / shared environment object
│
├── Features/
│   ├── Auth/
│   │   ├── Views/
│   │   │   ├── LoginView.swift
│   │   │   └── OnboardingView.swift    # Profile + equipment setup
│   │   └── Services/
│   │       └── AuthService.swift
│   │
│   ├── Today/                          # Tab 1 — daily workout
│   │   ├── Views/
│   │   │   ├── TodayView.swift         # Entry point: shows plan or quick-start
│   │   │   ├── WorkoutSetupView.swift  # Day label + time + energy picker
│   │   │   ├── ActiveWorkoutView.swift # Live logging — table layout
│   │   │   ├── ExerciseTableView.swift # Full session table (all exercises visible)
│   │   │   ├── SetRowView.swift        # Single set row: weight × reps × RIR
│   │   │   └── PostWorkoutView.swift   # Summary + AI progression note + user note
│   │   ├── ViewModels/
│   │   │   ├── TodayViewModel.swift
│   │   │   ├── WorkoutSetupViewModel.swift
│   │   │   └── ActiveWorkoutViewModel.swift
│   │   └── Services/
│   │       └── WorkoutSessionService.swift
│   │
│   ├── AICoach/                        # Shared across Today + Month Plan tabs
│   │   ├── Views/
│   │   │   ├── CoachChatView.swift     # Conversational chat — ephemeral per session
│   │   │   └── MessageBubbleView.swift # Reusable message bubble component
│   │   ├── ViewModels/
│   │   │   └── CoachChatViewModel.swift
│   │   └── Services/
│   │       ├── GeminiService.swift          # All Gemini API calls
│   │       ├── CoachContextBuilder.swift    # Builds prompt context from saved data
│   │       └── CoachPromptService.swift     # System prompt + parameterization
│   │
│   ├── MonthPlan/                      # Tab 2 — month planning
│   │   ├── Views/
│   │   │   ├── MonthPlanView.swift     # Calendar grid view
│   │   │   ├── MonthDayTileView.swift  # Reusable day tile (planned / done / rest)
│   │   │   ├── PlanBuilderChatView.swift  # AI conversation to build the plan
│   │   │   └── PlannedSessionView.swift   # Detail view for a planned day
│   │   ├── ViewModels/
│   │   │   ├── MonthPlanViewModel.swift
│   │   │   └── PlanBuilderViewModel.swift
│   │   └── Services/
│   │       └── MonthPlanService.swift
│   │
│   ├── History/
│   │   ├── Views/
│   │   │   ├── HistoryListView.swift
│   │   │   └── WorkoutDetailView.swift
│   │   └── ViewModels/
│   │       └── HistoryViewModel.swift
│   │
│   └── Profile/
│       ├── Views/
│       │   ├── ProfileView.swift
│       │   ├── EquipmentPickerView.swift   # Select available machines/equipment
│       │   └── StreakView.swift
│       └── ViewModels/
│           └── ProfileViewModel.swift
│
├── Core/
│   ├── Models/
│   │   ├── UserProfile.swift
│   │   ├── Workout.swift
│   │   ├── Exercise.swift
│   │   ├── WorkoutSet.swift
│   │   ├── PersonalRecord.swift
│   │   ├── MonthPlan.swift
│   │   ├── PlannedSession.swift
│   │   └── ChatMessage.swift           # In-memory only — not persisted
│   │
│   ├── Services/
│   │   ├── SupabaseService.swift       # Remote CRUD operations
│   │   ├── LocalStorageService.swift   # Core Data CRUD
│   │   ├── SyncService.swift           # Offline queue → Supabase on reconnect
│   │   └── ValidationService.swift    # Input sanitization + regex patterns
│   │
│   ├── Repositories/
│   │   ├── WorkoutRepository.swift     # Coordinates local + remote workout data
│   │   ├── ProfileRepository.swift
│   │   ├── PRRepository.swift
│   │   └── MonthPlanRepository.swift
│   │
│   └── Utilities/
│       ├── InputSanitizer.swift        # Prompt injection defense
│       ├── OfflineQueueManager.swift   # Queues writes when offline
│       └── DateFormatter+Extensions.swift
│
├── Config/
│   ├── Secrets.xcconfig.template      # Committed — contains placeholder keys only
│   └── Secrets.xcconfig               # Git-ignored — never committed, no exceptions
│
└── Resources/
    └── Assets.xcassets
```

---

## 6. DATABASE SCHEMA

### profiles
```sql
CREATE TABLE profiles (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,
  display_name          TEXT,
  age                   INTEGER,
  height_inches         DECIMAL(5,2),
  weight_lbs            DECIMAL(5,2),
  training_age_months   INTEGER,
  primary_goals         TEXT[],
  split_days            TEXT[],         -- free-form day labels: ['Chest', 'Back', 'Heavy Pull', 'Legs']
                                        -- no preset enforcement — user names these however they want
  avoid_exercises       TEXT[],
  equipment             JSONB,          -- { "cables": true, "dumbbells": true, "legPress": true, ... }
  notes_to_coach        TEXT,           -- persistent context injected into every AI call
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);
```

> **Split design note:** `split_days` is a free-form array. The app suggests common
> patterns (PPL, Bro Split, Upper/Lower, Arnold) during onboarding as a starting
> point only. The AI reads the day label and determines what to generate — there is
> no lookup table or preset enforcement. "Heavy Pull", "Chest Volume", "Leg Grind"
> are all equally valid labels.

### workouts
```sql
CREATE TABLE workouts (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id                  UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  local_id                 TEXT UNIQUE,
  date                     DATE NOT NULL DEFAULT CURRENT_DATE,
  workout_type             TEXT NOT NULL,          -- matches user's split_days label
  duration_minutes         INTEGER,
  energy_level             INTEGER CHECK(energy_level BETWEEN 1 AND 10),
  time_available_minutes   INTEGER,
  user_note                TEXT,
  ai_progression_note      TEXT,
  planned_session_id       UUID,                   -- FK to planned_sessions if from month plan
  synced                   BOOLEAN DEFAULT TRUE,
  created_at               TIMESTAMPTZ DEFAULT NOW()
);
```

### exercises
```sql
CREATE TABLE exercises (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_id     UUID REFERENCES workouts(id) ON DELETE CASCADE NOT NULL,
  local_id       TEXT UNIQUE,
  name           TEXT NOT NULL,
  muscle_group   TEXT NOT NULL,
  order_index    INTEGER NOT NULL,
  target_sets    INTEGER,
  target_reps    TEXT,
  target_rir     TEXT,
  rest_seconds   INTEGER,
  coach_note     TEXT
);
```

### sets
```sql
CREATE TABLE sets (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  exercise_id    UUID REFERENCES exercises(id) ON DELETE CASCADE NOT NULL,
  local_id       TEXT UNIQUE,
  set_number     INTEGER NOT NULL,
  weight_lbs     DECIMAL(6,2) NOT NULL,
  reps           INTEGER NOT NULL,
  rir            INTEGER NOT NULL CHECK(rir BETWEEN 0 AND 5),
  user_feedback  TEXT,
  is_pr          BOOLEAN DEFAULT FALSE,
  recorded_at    TIMESTAMPTZ DEFAULT NOW()
);
```

### personal_records
```sql
CREATE TABLE personal_records (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  exercise_name   TEXT NOT NULL,
  weight_lbs      DECIMAL(6,2) NOT NULL,
  reps            INTEGER NOT NULL,
  date_achieved   DATE NOT NULL,
  workout_id      UUID REFERENCES workouts(id),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### month_plans
```sql
CREATE TABLE month_plans (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title           TEXT,                  -- e.g. "8-Week Strength Block"
  target_goal     TEXT,                  -- e.g. "Hit 100 lb DBs on chest press"
  start_date      DATE NOT NULL,
  end_date        DATE NOT NULL,
  ai_overview     TEXT,                  -- AI-generated summary of the plan strategy
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### planned_sessions
```sql
CREATE TABLE planned_sessions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  month_plan_id   UUID REFERENCES month_plans(id) ON DELETE CASCADE NOT NULL,
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  planned_date    DATE NOT NULL,
  workout_type    TEXT NOT NULL,
  focus_note      TEXT,                  -- AI note for this specific day's intent
  is_rest_day     BOOLEAN DEFAULT FALSE,
  completed       BOOLEAN DEFAULT FALSE,
  workout_id      UUID REFERENCES workouts(id)  -- set when user logs the session
);
```

### ai_context_summaries
```sql
CREATE TABLE ai_context_summaries (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  workout_type      TEXT NOT NULL,
  summary_text      TEXT NOT NULL,
  sessions_covered  INTEGER,
  last_updated      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, workout_type)
);
```

### rate_limits
```sql
CREATE TABLE rate_limits (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  endpoint      TEXT NOT NULL DEFAULT 'coach',
  requested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 7. AI CONTEXT STRATEGY

### Rolling Summary System
Keeps prompt size fixed regardless of training history length.

```
Each workout completion:
  → AI writes a short progression summary for that workout type
  → Stored in ai_context_summaries (one row per user per workout type, overwritten)

Next session of same type:
  → Summary (compressed history)         ~200 tokens
  → Last 1-2 raw sessions (full data)    ~300-500 tokens
  → User profile + goals + equipment     ~150 tokens
  → Today's input (day label/time/energy)~50 tokens
  Total: ~700-900 tokens per call — always manageable
```

### Month Plan Context
When a month plan exists, the AI also receives:
- The plan's `target_goal` and `ai_overview`
- The current week's planned sessions
- How many sessions are completed vs remaining

This lets the coach say things like "you're 3 weeks into your strength block —
today's session needs to push the bench to stay on track for your 100 lb target."

### Why Not RAG / Vector Database?
RAG is designed for semantic search over large unstructured document collections.
This app has a small, structured, highly personal dataset where we always know
exactly what context to inject. The rolling summary approach gives equivalent
results with zero added complexity, no embedding pipeline, and no extra cost.
A vector DB would be appropriate only if a general exercise search library is
added in a future version.

---

## 8. SECURITY

### Input Sanitization (ValidationService.swift)
All user-provided text is sanitized before being injected into AI prompts.

```swift
// Blocked regex patterns — prompt injection defense
private let blockedPatterns: [NSRegularExpression] = [
    try! NSRegularExpression(pattern: "ignore (previous|all) instructions",
                             options: .caseInsensitive),
    try! NSRegularExpression(pattern: "you are now",        options: .caseInsensitive),
    try! NSRegularExpression(pattern: "system prompt",      options: .caseInsensitive),
    try! NSRegularExpression(pattern: "\\[INST\\]",         options: []),
    try! NSRegularExpression(pattern: "<\\|system\\|>",     options: []),
    try! NSRegularExpression(pattern: "jailbreak",          options: .caseInsensitive),
]
```

Numeric inputs (weight, reps, RIR) are strictly parsed to their target type —
no raw string passthrough to the prompt ever.

### API Keys
- Keys live in `Config/Secrets.xcconfig` only
- `Secrets.xcconfig` is git-ignored — **never committed under any circumstances,
  not even with placeholder values, not even as comments**
- `Secrets.xcconfig.template` is committed and contains only the key names with
  empty values: `GEMINI_API_KEY=` and `SUPABASE_ANON_KEY=`
- Keys are accessed at runtime via `Bundle.main.infoDictionary` only

### Supabase RLS
All tables have Row Level Security enabled. Users can only read and write their
own rows. The `check_rate_limit()` function is SECURITY DEFINER so it cannot be
spoofed by the caller.

---

## 9. OFFLINE-FIRST

**Works fully offline:**
- Creating and logging workouts
- Adding sets with weight, reps, RIR
- Viewing full workout history
- Viewing month plan calendar
- Editing profile

**Requires network:**
- AI chat and plan generation
- Supabase sync (queued for reconnect)

**Sync flow:**
1. Every write goes to Core Data first (immediate, no network needed)
2. `SyncService` monitors connectivity via `NWPathMonitor`
3. On reconnect, `OfflineQueueManager` flushes pending records to Supabase
4. `local_id` (device-generated UUID) prevents duplicate inserts on retry
5. Conflict resolution: last-write-wins (workout data is append-only by nature)

---

## 10. CODING STANDARDS

| Rule | How It's Applied |
|---|---|
| Single Responsibility | `GeminiService` only calls the API. `CoachContextBuilder` only builds context. Never mixed. |
| Method size | Max 20-30 lines. If longer, extract a private named helper. |
| Naming | Method name = exactly what it does. `fetchRecentWorkouts()` not `getData()`. Booleans: `isOnline`, `isPR`, `hasSynced`. |
| No closure params | Use protocols and delegates. Pass typed service objects. |
| DRY | One `ValidationService`. One `WorkoutRepository`. One `MessageBubbleView`. Reuse everywhere. |
| No over-engineering | URLSession before any networking library. Core Data before a custom sync engine. Simplest path first. |
| Input safety | `ValidationService` is called on every user-provided string before it touches the AI prompt. |
| API keys | Zero keys anywhere in the codebase — not in code, not in comments, not in strings. |

---

## 11. SCREEN FLOW

```
Splash
  ↓
Login / Sign Up (Email or Apple)
  ↓ (first time)
Onboarding
  ├── Profile setup (age, weight, training age, goals)
  ├── Split setup (suggest PPL / Bro Split / Upper-Lower / Arnold as starting points,
  │               user renames/customizes freely — these are just suggestions)
  └── Equipment selection (checkboxes: cables, dumbbells, barbell, machines, etc.)
  ↓
Main App (Tab Bar)
  ├── TODAY TAB
  │     ├── No plan: WorkoutSetupView (day label + time + energy)
  │     │     ↓ AI generates plan (table format — full session visible at once)
  │     │     ↓ ActiveWorkoutView (log sets inline)
  │     │     ├── [Chat] floating button → CoachChatView (ephemeral)
  │     │     └── [Finish] → PostWorkoutView (AI note + user note + save)
  │     └── Month plan active: today's session pre-loaded, same logging flow
  │
  ├── MONTH PLAN TAB
  │     ├── No plan: PlanBuilderChatView
  │     │     (User chats with AI: "I want to hit 100 lb DBs in 8 weeks"
  │     │      AI asks about current stats, schedule, recovery
  │     │      AI generates full month calendar)
  │     └── Plan exists: MonthPlanView (calendar grid)
  │           ├── Tap future day → PlannedSessionView (preview + notes)
  │           └── Tap today → links to Today tab
  │
  ├── HISTORY TAB
  │     ├── HistoryListView (chronological list with workout type + volume)
  │     └── WorkoutDetailView (full set log table + AI note + user note)
  │
  └── PROFILE TAB
        ├── Stats (streak, total sessions, PRs)
        ├── Equipment picker
        ├── Split day editor
        ├── Coach preferences (notes_to_coach field)
        └── Account settings
```

---

## 12. MONTH PLAN — DETAILED DESIGN

### How It Works
1. User opens Month Plan tab with no active plan
2. `PlanBuilderChatView` opens — conversational AI interface
3. User states their target: "I want to add 20 lbs to my bench in 8 weeks"
4. AI asks clarifying questions: current bench, how many days/week available,
   any constraints
5. AI generates a structured month plan: each day gets a workout type, a focus
   note, and a progressive overload target
6. Plan is saved to `month_plans` + `planned_sessions` tables
7. `MonthPlanView` renders a calendar grid:
   - **Rest day:** grey tile
   - **Planned, future:** label + focus note preview
   - **Planned, today:** highlighted, taps to Today tab
   - **Completed:** checkmark + workout type label
   - **Missed:** amber indicator (not red — no shame UX)

### Plan Flexibility
The month plan is a **guide, not a contract.** The user can:
- Tap any future day and edit the planned workout type
- Start a completely different session from the Today tab (it just won't link to
  the plan for that day)
- Ask the AI to revise the remaining plan at any time

### AI Context for Plan Generation
```
Profile: age, weight, training age, goals, split preferences, equipment
Current PRs: all-time bests per exercise
Last 4 weeks of workout history: compressed summaries per workout type
Target: user's stated goal + timeline
```

---

## 13. DEVELOPMENT PHASES

| Phase | Deliverables |
|---|---|
| 0 | Repo scaffold, Xcode project structure, Core Data model, Supabase schema, Auth (email + Apple), onboarding (profile + equipment + split setup) |
| 1 | Today tab: workout setup, AI plan generation (table format), live set logging, post-workout AI note, streak tracking |
| 2 | Today tab: AI coach chat (ephemeral). Month Plan tab: plan builder chat + calendar view + completion tracking. Rolling context summary system. |
| 3 | History tab: list + detail view. PR detection. Profile editing. Muscle group heatmap (modern redesign — no flat SVG). |
| 4 | Offline queue + background sync. Security hardening. Input sanitization audit. TestFlight beta. |
