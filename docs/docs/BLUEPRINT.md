# Lightstack iOS — Full Blueprint & Architecture

> Version 1.0 | March 2026 | Stack: Swift/SwiftUI · Supabase · Google Gemini

---

## 1. VISION

A native iOS personal trainer that behaves like your ChatGPT coaching relationship — persistent, context-aware, and smooth. Walk into the gym, pick your split day, set time and energy, and the AI generates a fully personalized plan informed by every previous session. Chat with the coach before, during, and after. All data saves progressively so context never gets full — the app compresses history into rolling summaries and injects only what's relevant into each AI call.

---

## 2. CORE FEATURES

| Feature | Phase |
|---|---|
| Auth (Email + Apple Sign-In) | 0 |
| User profile setup (age, weight, goals, split) | 0 |
| Quick-start workout (split day + time + energy) | 1 |
| AI workout generation | 1 |
| Live set logging (weight x reps x RIR per set) | 1 |
| Post-workout AI progression note | 1 |
| Streak / consistency tracking | 1 |
| Interactive AI chat (pre/during/post) | 2 |
| Rolling context summary system | 2 |
| Workout history and session detail view | 3 |
| PR detection | 3 |
| Profile editing | 3 |
| Offline mode with sync queue | 4 |
| Security hardening and TestFlight | 4 |

---

## 3. FOLDER STRUCTURE

```
Lightstack/
├── App/
│   ├── LightstackApp.swift
│   └── AppEnvironment.swift
├── Features/
│   ├── Auth/
│   │   ├── Views/LoginView.swift
│   │   ├── Views/OnboardingView.swift
│   │   └── Services/AuthService.swift
│   ├── Home/
│   │   ├── Views/HomeView.swift
│   │   └── ViewModels/HomeViewModel.swift
│   ├── WorkoutSession/
│   │   ├── Views/WorkoutSetupView.swift
│   │   ├── Views/ActiveWorkoutView.swift
│   │   ├── Views/ExerciseCardView.swift
│   │   ├── Views/SetRowView.swift
│   │   ├── Views/PostWorkoutView.swift
│   │   ├── ViewModels/WorkoutSetupViewModel.swift
│   │   ├── ViewModels/ActiveWorkoutViewModel.swift
│   │   └── Services/WorkoutSessionService.swift
│   ├── AICoach/
│   │   ├── Views/CoachChatView.swift
│   │   ├── Views/MessageBubbleView.swift
│   │   ├── ViewModels/CoachChatViewModel.swift
│   │   └── Services/GeminiService.swift
│   │   └── Services/CoachContextBuilder.swift
│   │   └── Services/CoachPromptService.swift
│   ├── History/
│   │   ├── Views/HistoryListView.swift
│   │   ├── Views/WorkoutDetailView.swift
│   │   └── ViewModels/HistoryViewModel.swift
│   └── Profile/
│       ├── Views/ProfileView.swift
│       └── ViewModels/ProfileViewModel.swift
├── Core/
│   ├── Models/
│   │   ├── UserProfile.swift
│   │   ├── Workout.swift
│   │   ├── Exercise.swift
│   │   ├── WorkoutSet.swift
│   │   ├── PersonalRecord.swift
│   │   └── ChatMessage.swift
│   ├── Services/
│   │   ├── SupabaseService.swift
│   │   ├── LocalStorageService.swift
│   │   ├── SyncService.swift
│   │   └── ValidationService.swift
│   ├── Repositories/
│   │   ├── WorkoutRepository.swift
│   │   ├── ProfileRepository.swift
│   │   └── PRRepository.swift
│   └── Utilities/
│       ├── InputSanitizer.swift
│       ├── OfflineQueueManager.swift
│       └── DateFormatter+Extensions.swift
├── Config/
│   ├── Secrets.xcconfig.template
│   └── .gitignore (Secrets.xcconfig excluded)
└── Resources/
    └── Assets.xcassets
```

---

## 4. DATABASE SCHEMA

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
  split_type            TEXT,
  custom_split          JSONB,
  avoid_exercises       TEXT[],
  notes_to_coach        TEXT,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);
```

### workouts
```sql
CREATE TABLE workouts (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id                  UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  local_id                 TEXT UNIQUE,
  date                     DATE NOT NULL DEFAULT CURRENT_DATE,
  workout_type             TEXT NOT NULL,
  duration_minutes         INTEGER,
  energy_level             INTEGER CHECK(energy_level BETWEEN 1 AND 10),
  time_available_minutes   INTEGER,
  user_note                TEXT,
  ai_progression_note      TEXT,
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

### ai_context_summaries  ← solves the context window problem
```sql
CREATE TABLE ai_context_summaries (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  workout_type      TEXT NOT NULL,
  summary_text      TEXT NOT NULL,
  sessions_covered  INTEGER,
  last_updated      TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 5. AI CONTEXT STRATEGY

The rolling summary system keeps prompt size fixed regardless of training history length.

```
Each workout completion:
  → AI writes a short progression summary for that workout type
  → Stored in ai_context_summaries

Next session of same type:
  → Summary (compressed history)      ~200 tokens
  → Last 1-2 raw sessions (full data) ~300-500 tokens
  → User profile + goals              ~100 tokens
  → Today input (split/time/energy)   ~50 tokens
  Total: ~700-850 tokens per call — always manageable
```

---

## 6. SECURITY

### Input Sanitization (ValidationService.swift)
All user text is sanitized before injection into AI prompts.

Blocked regex patterns:
- ignore (previous|all) instructions
- you are now
- system prompt
- [INST] and similar injection markers

Numeric inputs (weight, reps, RIR) are parsed strictly — no string passthrough.

### API Keys
Gemini and Supabase keys live in Config/Secrets.xcconfig, git-ignored.
Accessed via Bundle.main.infoDictionary — never hardcoded.

### Supabase RLS
All tables have Row Level Security enabled.
Users can only read and write their own rows.

---

## 7. OFFLINE-FIRST

1. Every write goes to Core Data first (no network required)
2. SyncService monitors NWPathMonitor for connectivity
3. On reconnect, OfflineQueueManager flushes pending records to Supabase
4. Conflicts resolved with last-write-wins (workout data is append-only)

Works offline: creating workouts, logging sets, viewing history, editing profile.
Requires network: AI chat, Supabase sync.

---

## 8. CODING STANDARDS

| Rule | Implementation |
|---|---|
| Single Responsibility | Each service/class has one job |
| Method size | Max 20-30 lines — extract helpers if longer |
| Naming | Method name = exactly what it does |
| No closure params | Use protocols and delegates |
| DRY | One ValidationService, one WorkoutRepository |
| No over-engineering | URLSession before Alamofire, simplest path first |
| Input safety | ValidationService used on all user-facing text |

---

## 9. SPLIT CONFIGURATION

Presets: PPL, Bro Split (Chest/Back/Arms/Legs), Upper/Lower, Arnold Split
Custom: user names each day freely (e.g. "Push", "Pull", "Legs + Core")
Stored in profiles.split_type and profiles.custom_split (JSONB)

---

## 10. DEVELOPMENT PHASES

| Phase | Deliverables |
|---|---|
| 0 | Repo, Xcode scaffold, Supabase schema, Core Data model, Auth flow |
| 1 | Home screen, workout setup, AI plan generation, live set logging, post-workout note, streaks |
| 2 | AI coach chat, context builder, rolling summary system |
| 3 | History list + detail, PR detection, profile editing |
| 4 | Offline queue + sync, security hardening, TestFlight |
