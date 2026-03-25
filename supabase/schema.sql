-- ============================================================
-- LIGHTSTACK — Supabase Schema
-- Run in Supabase SQL Editor to initialise all tables,
-- RLS policies, indexes, functions, and views.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- PROFILES
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,
  display_name          TEXT,
  age                   INTEGER,
  height_inches         DECIMAL(5,2),
  weight_lbs            DECIMAL(5,2),
  training_age_months   INTEGER,
  primary_goals         TEXT[],
  split_type            TEXT,            -- 'PPL' | 'Bro Split' | 'Upper/Lower' | 'Arnold' | 'Custom'
  custom_split          JSONB,           -- { "day1": "Push", "day2": "Pull", "day3": "Legs" }
  avoid_exercises       TEXT[],          -- e.g. ['Barbell Back Squat']
  notes_to_coach        TEXT,            -- persistent coaching context (mirrors ChatGPT system prompt)
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- WORKOUTS
-- ============================================================
CREATE TABLE IF NOT EXISTS workouts (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id                  UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  local_id                 TEXT UNIQUE,           -- device-generated UUID for offline sync
  date                     DATE NOT NULL DEFAULT CURRENT_DATE,
  workout_type             TEXT NOT NULL,         -- 'Chest Day', 'Pull Day', etc.
  duration_minutes         INTEGER,
  energy_level             INTEGER CHECK (energy_level BETWEEN 1 AND 10),
  time_available_minutes   INTEGER,
  user_note                TEXT,                  -- post-workout free-text from user
  ai_progression_note      TEXT,                  -- AI-generated review saved after session
  created_at               TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- EXERCISES
-- ============================================================
CREATE TABLE IF NOT EXISTS exercises (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_id     UUID REFERENCES workouts(id) ON DELETE CASCADE NOT NULL,
  local_id       TEXT UNIQUE,
  name           TEXT NOT NULL,
  muscle_group   TEXT NOT NULL,
  order_index    INTEGER NOT NULL,
  target_sets    INTEGER,
  target_reps    TEXT,           -- '8-10', '12-15'
  target_rir     TEXT,           -- '1-2', '0-1'
  rest_seconds   INTEGER,
  coach_note     TEXT
);

-- ============================================================
-- SETS
-- ============================================================
CREATE TABLE IF NOT EXISTS sets (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  exercise_id    UUID REFERENCES exercises(id) ON DELETE CASCADE NOT NULL,
  local_id       TEXT UNIQUE,
  set_number     INTEGER NOT NULL,
  weight_lbs     DECIMAL(6,2) NOT NULL,
  reps           INTEGER NOT NULL,
  rir            INTEGER NOT NULL CHECK (rir BETWEEN 0 AND 5),
  user_feedback  TEXT,          -- 'felt strong', 'shaky form', 'joint pain'
  is_pr          BOOLEAN DEFAULT FALSE,
  recorded_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- PERSONAL RECORDS
-- ============================================================
CREATE TABLE IF NOT EXISTS personal_records (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  exercise_name   TEXT NOT NULL,
  weight_lbs      DECIMAL(6,2) NOT NULL,
  reps            INTEGER NOT NULL,
  date_achieved   DATE NOT NULL,
  workout_id      UUID REFERENCES workouts(id),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- AI CONTEXT SUMMARIES
-- Stores compressed per-workout-type history summaries.
-- Solves the context window problem: instead of injecting all
-- historical sessions, each new workout gets a compact summary
-- (~200 tokens) plus only the last 1-2 raw sessions.
-- ============================================================
CREATE TABLE IF NOT EXISTS ai_context_summaries (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  workout_type      TEXT NOT NULL,        -- 'Chest Day', 'Pull Day', etc.
  summary_text      TEXT NOT NULL,        -- AI-compressed rolling summary
  sessions_covered  INTEGER DEFAULT 0,
  last_updated      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, workout_type)          -- one summary per type per user
);

-- ============================================================
-- RATE LIMITS (prevents AI endpoint abuse)
-- ============================================================
CREATE TABLE IF NOT EXISTS rate_limits (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  endpoint      TEXT NOT NULL DEFAULT 'coach',
  requested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_profiles_user_id          ON profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_workouts_user_id          ON workouts(user_id);
CREATE INDEX IF NOT EXISTS idx_workouts_date             ON workouts(date);
CREATE INDEX IF NOT EXISTS idx_workouts_user_date        ON workouts(user_id, date);
CREATE INDEX IF NOT EXISTS idx_workouts_local_id         ON workouts(local_id);
CREATE INDEX IF NOT EXISTS idx_exercises_workout_id      ON exercises(workout_id);
CREATE INDEX IF NOT EXISTS idx_sets_exercise_id          ON sets(exercise_id);
CREATE INDEX IF NOT EXISTS idx_prs_user_id               ON personal_records(user_id);
CREATE INDEX IF NOT EXISTS idx_prs_exercise              ON personal_records(user_id, exercise_name);
CREATE INDEX IF NOT EXISTS idx_summaries_user_type       ON ai_context_summaries(user_id, workout_type);
CREATE INDEX IF NOT EXISTS idx_rate_limits_user_endpoint ON rate_limits(user_id, endpoint, requested_at);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE workouts             ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercises            ENABLE ROW LEVEL SECURITY;
ALTER TABLE sets                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE personal_records     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_context_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_limits          ENABLE ROW LEVEL SECURITY;

-- profiles
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "profiles_insert" ON profiles FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (auth.uid() = user_id);

-- workouts
CREATE POLICY "workouts_select" ON workouts FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "workouts_insert" ON workouts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "workouts_update" ON workouts FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "workouts_delete" ON workouts FOR DELETE USING (auth.uid() = user_id);

-- exercises (access through workouts)
CREATE POLICY "exercises_select" ON exercises FOR SELECT USING (
  EXISTS (SELECT 1 FROM workouts w WHERE w.id = exercises.workout_id AND w.user_id = auth.uid())
);
CREATE POLICY "exercises_insert" ON exercises FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM workouts w WHERE w.id = exercises.workout_id AND w.user_id = auth.uid())
);
CREATE POLICY "exercises_update" ON exercises FOR UPDATE USING (
  EXISTS (SELECT 1 FROM workouts w WHERE w.id = exercises.workout_id AND w.user_id = auth.uid())
);
CREATE POLICY "exercises_delete" ON exercises FOR DELETE USING (
  EXISTS (SELECT 1 FROM workouts w WHERE w.id = exercises.workout_id AND w.user_id = auth.uid())
);

-- sets (access through exercises -> workouts)
CREATE POLICY "sets_select" ON sets FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM exercises e
    JOIN workouts w ON w.id = e.workout_id
    WHERE e.id = sets.exercise_id AND w.user_id = auth.uid()
  )
);
CREATE POLICY "sets_insert" ON sets FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM exercises e
    JOIN workouts w ON w.id = e.workout_id
    WHERE e.id = sets.exercise_id AND w.user_id = auth.uid()
  )
);
CREATE POLICY "sets_update" ON sets FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM exercises e
    JOIN workouts w ON w.id = e.workout_id
    WHERE e.id = sets.exercise_id AND w.user_id = auth.uid()
  )
);
CREATE POLICY "sets_delete" ON sets FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM exercises e
    JOIN workouts w ON w.id = e.workout_id
    WHERE e.id = sets.exercise_id AND w.user_id = auth.uid()
  )
);

-- personal_records
CREATE POLICY "prs_select" ON personal_records FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "prs_insert" ON personal_records FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "prs_update" ON personal_records FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "prs_delete" ON personal_records FOR DELETE USING (auth.uid() = user_id);

-- ai_context_summaries
CREATE POLICY "summaries_select" ON ai_context_summaries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "summaries_insert" ON ai_context_summaries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "summaries_update" ON ai_context_summaries FOR UPDATE USING (auth.uid() = user_id);

-- rate_limits (service role only — enforced via SECURITY DEFINER function)
CREATE POLICY "rate_limits_service_only" ON rate_limits FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

-- Auto-update updated_at on profiles
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Atomic rate limit check (advisory lock prevents race conditions)
-- Uses auth.uid() internally — caller cannot spoof another user's ID.
-- Window: 1 minute | Max requests: 10
CREATE OR REPLACE FUNCTION check_rate_limit()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id  UUID;
  v_count    INTEGER;
  v_allowed  BOOLEAN;
  v_lock_key BIGINT;
  v_oldest   TIMESTAMPTZ;
  v_window   INTERVAL := INTERVAL '1 minute';
  v_max      INTEGER  := 10;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('allowed', FALSE, 'request_count', 0, 'oldest_request_at', NULL);
  END IF;

  v_lock_key := ('x' || left(replace(v_user_id::text, '-', ''), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  DELETE FROM rate_limits
  WHERE user_id = v_user_id
    AND endpoint = 'coach'
    AND requested_at < NOW() - v_window;

  SELECT COUNT(*), MIN(requested_at)
  INTO v_count, v_oldest
  FROM rate_limits
  WHERE user_id = v_user_id
    AND endpoint = 'coach'
    AND requested_at >= NOW() - v_window;

  IF v_count >= v_max THEN
    v_allowed := FALSE;
  ELSE
    INSERT INTO rate_limits (user_id, endpoint, requested_at) VALUES (v_user_id, 'coach', NOW());
    v_count  := v_count + 1;
    v_oldest := COALESCE(v_oldest, NOW());
    v_allowed := TRUE;
  END IF;

  RETURN json_build_object('allowed', v_allowed, 'request_count', v_count, 'oldest_request_at', v_oldest);
END;
$$;

-- ============================================================
-- VIEWS
-- ============================================================

-- Recent workout summary (last 20 workouts per user)
CREATE OR REPLACE VIEW recent_workouts_summary AS
SELECT
  w.id,
  w.user_id,
  w.date,
  w.workout_type,
  w.duration_minutes,
  w.energy_level,
  w.ai_progression_note,
  COUNT(DISTINCT e.id)  AS exercise_count,
  COUNT(s.id)           AS total_sets,
  SUM(s.weight_lbs * s.reps) AS total_volume_lbs
FROM workouts w
LEFT JOIN exercises e ON e.workout_id = w.id
LEFT JOIN sets      s ON s.exercise_id = e.id
GROUP BY w.id, w.user_id, w.date, w.workout_type, w.duration_minutes, w.energy_level, w.ai_progression_note;

-- Streak calculation helper
CREATE OR REPLACE VIEW workout_dates_by_user AS
SELECT DISTINCT user_id, date
FROM workouts
ORDER BY user_id, date DESC;

-- ============================================================
-- SUCCESS
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE 'Lightstack schema initialised successfully.';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '1. Enable Apple and Email providers in Supabase Auth settings';
  RAISE NOTICE '2. Set your app redirect URLs (lightstack.org/auth/callback)';
  RAISE NOTICE '3. Copy your SUPABASE_URL and SUPABASE_ANON_KEY into Config/Secrets.xcconfig';
END $$;
