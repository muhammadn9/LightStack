-- ============================================================
-- LIGHTSTACK — Supabase Schema v1.2
-- Run this in the Supabase SQL Editor to initialize the database
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- PROFILES
-- split_days is a free-form array — no preset enforcement.
-- The user labels their days however they want.
-- The AI reads the label and determines what workout to build.
-- equipment is a JSONB map of available gear (true/false per item).
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
  split_days            TEXT[],
  avoid_exercises       TEXT[],
  equipment             JSONB DEFAULT '{}'::jsonb,
  notes_to_coach        TEXT,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- WORKOUTS
-- Workout document structure:
--   Date:           02/04/2026
--   Workout Type:   Chest (free-form label from user's split_days)
--   Duration:       52 minutes
--   Energy Level:   8/10
--   User Note:      "Felt strong, shoulder tight on last set"
--   AI Note:        "DB press up 5 lbs from last session. Target 90s
--                    across all sets next time. Watch shoulder angle
--                    on inclines — keep elbows at 45 degrees."
-- ============================================================
CREATE TABLE IF NOT EXISTS workouts (
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
  planned_session_id       UUID,
  synced                   BOOLEAN DEFAULT TRUE,
  created_at               TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- EXERCISES
-- Set data example:
--   Dumbbell Chest Press:
--     Set 0: 80 lbs x 12
--     Set 1: 85 lbs x 10
--     Set 2: 90 lbs x 10
-- ============================================================
CREATE TABLE IF NOT EXISTS exercises (
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
  rir            INTEGER NOT NULL CHECK(rir BETWEEN 0 AND 5),
  user_feedback  TEXT,
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
-- MONTH PLANS
-- Created through a conversational AI session.
-- The user states a target goal and timeline; the AI builds
-- a full calendar of planned sessions.
-- ============================================================
CREATE TABLE IF NOT EXISTS month_plans (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title         TEXT,
  target_goal   TEXT,
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  ai_overview   TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- PLANNED SESSIONS
-- Individual days within a month plan.
-- completed + workout_id are set when the user logs that session.
-- is_rest_day = true means no workout is expected that day.
-- ============================================================
CREATE TABLE IF NOT EXISTS planned_sessions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  month_plan_id   UUID REFERENCES month_plans(id) ON DELETE CASCADE NOT NULL,
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  planned_date    DATE NOT NULL,
  workout_type    TEXT NOT NULL,
  focus_note      TEXT,
  is_rest_day     BOOLEAN DEFAULT FALSE,
  completed       BOOLEAN DEFAULT FALSE,
  workout_id      UUID REFERENCES workouts(id)
);

-- ============================================================
-- AI CONTEXT SUMMARIES
-- One row per user per workout type, updated after each session.
-- Solves the context window problem: instead of injecting full
-- history into every AI call, inject this compressed summary
-- plus only the last 1-2 raw sessions.
-- Target prompt size per call: 700-900 tokens regardless of
-- how long the user has been training.
-- ============================================================
CREATE TABLE IF NOT EXISTS ai_context_summaries (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  workout_type      TEXT NOT NULL,
  summary_text      TEXT NOT NULL,
  sessions_covered  INTEGER,
  last_updated      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, workout_type)
);

-- ============================================================
-- RATE LIMITS
-- Enforced via check_rate_limit() SECURITY DEFINER function.
-- Users cannot bypass this by calling the table directly.
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
CREATE INDEX IF NOT EXISTS idx_workouts_planned_session  ON workouts(planned_session_id);
CREATE INDEX IF NOT EXISTS idx_exercises_workout_id      ON exercises(workout_id);
CREATE INDEX IF NOT EXISTS idx_sets_exercise_id          ON sets(exercise_id);
CREATE INDEX IF NOT EXISTS idx_prs_user_id               ON personal_records(user_id);
CREATE INDEX IF NOT EXISTS idx_prs_exercise              ON personal_records(user_id, exercise_name);
CREATE INDEX IF NOT EXISTS idx_summaries_user_type       ON ai_context_summaries(user_id, workout_type);
CREATE INDEX IF NOT EXISTS idx_month_plans_user_id       ON month_plans(user_id);
CREATE INDEX IF NOT EXISTS idx_planned_sessions_plan     ON planned_sessions(month_plan_id);
CREATE INDEX IF NOT EXISTS idx_planned_sessions_date     ON planned_sessions(user_id, planned_date);
CREATE INDEX IF NOT EXISTS idx_rate_limits_user_endpoint ON rate_limits(user_id, endpoint, requested_at);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE workouts             ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercises            ENABLE ROW LEVEL SECURITY;
ALTER TABLE sets                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE personal_records     ENABLE ROW LEVEL SECURITY;
ALTER TABLE month_plans          ENABLE ROW LEVEL SECURITY;
ALTER TABLE planned_sessions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_context_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_limits          ENABLE ROW LEVEL SECURITY;

-- profiles
CREATE POLICY "Users manage own profile"
  ON profiles FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- workouts
CREATE POLICY "Users manage own workouts"
  ON workouts FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- exercises (scoped through workout ownership)
CREATE POLICY "Users manage own exercises"
  ON exercises FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM workouts
      WHERE workouts.id = exercises.workout_id
        AND workouts.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM workouts
      WHERE workouts.id = exercises.workout_id
        AND workouts.user_id = auth.uid()
    )
  );

-- sets (scoped through exercise → workout ownership)
CREATE POLICY "Users manage own sets"
  ON sets FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM exercises
      JOIN workouts ON workouts.id = exercises.workout_id
      WHERE exercises.id = sets.exercise_id
        AND workouts.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM exercises
      JOIN workouts ON workouts.id = exercises.workout_id
      WHERE exercises.id = sets.exercise_id
        AND workouts.user_id = auth.uid()
    )
  );

-- personal_records
CREATE POLICY "Users manage own PRs"
  ON personal_records FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- month_plans
CREATE POLICY "Users manage own month plans"
  ON month_plans FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- planned_sessions
CREATE POLICY "Users manage own planned sessions"
  ON planned_sessions FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ai_context_summaries
CREATE POLICY "Users manage own summaries"
  ON ai_context_summaries FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- rate_limits (service role only — enforced via SECURITY DEFINER function)
CREATE POLICY "Service role manages rate limits"
  ON rate_limits FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

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

-- ============================================================
-- ATOMIC RATE LIMIT CHECK
-- SECURITY DEFINER: runs as the function owner, not the caller.
-- auth.uid() is derived from the session — cannot be spoofed.
-- Window: 1 minute | Max: 10 requests
-- ============================================================
CREATE OR REPLACE FUNCTION check_rate_limit()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id   UUID;
  v_count     INTEGER;
  v_allowed   BOOLEAN;
  v_lock_key  BIGINT;
  v_oldest    TIMESTAMPTZ;
  v_window    INTERVAL := INTERVAL '1 minute';
  v_max       INTEGER  := 10;
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
    INSERT INTO rate_limits (user_id, endpoint, requested_at)
    VALUES (v_user_id, 'coach', NOW());
    v_count  := v_count + 1;
    v_oldest := COALESCE(v_oldest, NOW());
    v_allowed := TRUE;
  END IF;

  RETURN json_build_object(
    'allowed',           v_allowed,
    'request_count',     v_count,
    'oldest_request_at', v_oldest
  );
END;
$$;

-- ============================================================
-- VIEWS
-- ============================================================

-- Streak: consecutive days with at least one completed workout
CREATE OR REPLACE VIEW user_streaks AS
WITH daily AS (
  SELECT DISTINCT user_id, date FROM workouts
),
grouped AS (
  SELECT
    user_id,
    date,
    date - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY date))::INTEGER AS grp
  FROM daily
),
latest_grp AS (
  SELECT DISTINCT ON (user_id)
    user_id, grp
  FROM grouped
  ORDER BY user_id, date DESC
)
SELECT
  g.user_id,
  COUNT(*) AS current_streak
FROM grouped g
JOIN latest_grp lg ON lg.user_id = g.user_id AND lg.grp = g.grp
GROUP BY g.user_id;

-- Recent workout summary for history list view
CREATE OR REPLACE VIEW recent_workouts_summary AS
SELECT
  w.id,
  w.user_id,
  w.date,
  w.workout_type,
  w.duration_minutes,
  w.energy_level,
  w.ai_progression_note,
  COUNT(DISTINCT e.id)       AS exercise_count,
  COUNT(s.id)                AS total_sets,
  SUM(s.weight_lbs * s.reps) AS total_volume_lbs
FROM workouts w
LEFT JOIN exercises e ON e.workout_id = w.id
LEFT JOIN sets s      ON s.exercise_id = e.id
GROUP BY w.id, w.user_id, w.date, w.workout_type,
         w.duration_minutes, w.energy_level, w.ai_progression_note;

-- Month plan progress: sessions completed vs total per plan
CREATE OR REPLACE VIEW month_plan_progress AS
SELECT
  mp.id            AS plan_id,
  mp.user_id,
  mp.title,
  mp.target_goal,
  mp.start_date,
  mp.end_date,
  COUNT(ps.id) FILTER (WHERE NOT ps.is_rest_day)             AS total_sessions,
  COUNT(ps.id) FILTER (WHERE ps.completed AND NOT ps.is_rest_day) AS completed_sessions
FROM month_plans mp
LEFT JOIN planned_sessions ps ON ps.month_plan_id = mp.id
GROUP BY mp.id, mp.user_id, mp.title, mp.target_goal, mp.start_date, mp.end_date;

-- ============================================================
DO $$
BEGIN
  RAISE NOTICE 'Lightstack schema v1.2 created successfully.';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '1. Enable Email + Apple OAuth in Supabase Auth settings';
  RAISE NOTICE '2. Configure your app redirect URLs';
  RAISE NOTICE '3. Add SUPABASE_URL and SUPABASE_ANON_KEY to Config/Secrets.xcconfig';
END $$;
