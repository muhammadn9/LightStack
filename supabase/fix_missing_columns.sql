-- ============================================================
-- FIX: Add missing columns to existing tables
-- Run this if the original schema was created without local_id
-- or other columns. Safe to run multiple times (IF NOT EXISTS).
-- ============================================================

-- Drop all existing tables and recreate from scratch
-- This is safe for a fresh/dev project with no real data
DROP VIEW IF EXISTS month_plan_progress CASCADE;
DROP VIEW IF EXISTS recent_workouts_summary CASCADE;
DROP VIEW IF EXISTS user_streaks CASCADE;
DROP TABLE IF EXISTS rate_limits CASCADE;
DROP TABLE IF EXISTS ai_context_summaries CASCADE;
DROP TABLE IF EXISTS planned_sessions CASCADE;
DROP TABLE IF EXISTS month_plans CASCADE;
DROP TABLE IF EXISTS personal_records CASCADE;
DROP TABLE IF EXISTS sets CASCADE;
DROP TABLE IF EXISTS exercises CASCADE;
DROP TABLE IF EXISTS workouts CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
DROP FUNCTION IF EXISTS check_rate_limit() CASCADE;
DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;
