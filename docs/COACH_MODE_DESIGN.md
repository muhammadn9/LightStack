# Coach Mode: Design (draft for owner review)

Status: proposal. No code written.

## 1. Definition

Coach mode lets a user train **another person (a "client")** while doing their own workout.

- The coach logs their own sets exactly as today.
- In a separate **client area** inside the active workout, the coach also logs the client's weight / reps / RIR on the client's behalf.
- At the end, the client's session gets the same AI post-workout review (`CoachReviewDocument` pipeline) on the client's numbers.
- Afterwards: (1) **export** the client's workout, or (2) **sync it into the client's own LightStack account** if the client has authorised the coach. (3) The coach's History shows who they trained on which day, next to their own logs.

This replaces the earlier "guided session / periodisation / trainer sharing" interpretations. Guided-session ideas can come back later as a separate feature.

## 2. Principles

- The coach's workout stays one `Workout`. The client's session is a **second workout record** linked to it, never mixed into the coach's own sets, volume, PRs or streaks.
- Everything works offline and with no client account. Account linking is an upgrade, not a prerequisite.
- Reuse the existing engines: `ActiveWorkoutViewModel` logging, `ProgressionEngine` targets, `CoachReviewDocument`, `OfflineQueueManager`.

## 3. Clients and authorisation

**Client profile** (`CDClient`): `id`, `ownerUserId` (the coach), `displayName`, `linkedUserId` (nil for guests), `linkStatus` (`guest | invited | linked | revoked`), `createdAt`, `syncStatus`.

- **Guest client (phase 1):** local name only. Their history lives in the coach's account. Fully usable offline.
- **Linked client (phase 2):** the client has their own LightStack account and has approved this coach.

**Invite flow (phase 2)**
1. Coach opens a guest client and taps "Link account". App creates a `coach_links` row (`status = pending`, single-use invite code, 7-day expiry) and shows a code / share link.
2. Client opens Settings > Coaches in their own app, enters the code, sees "Alex wants to log workouts for you" with scope text, and taps Approve (`status = active`) or Decline.
3. Client can **revoke** any time (Settings > Coaches > Remove). Coach can also unlink. Revoke is immediate and stops all future inserts; already-written workouts stay in the client's account (client can delete them like any workout).
4. On link, existing guest history for that client stays with the coach only unless the coach explicitly taps "Send past sessions" (client sees them as a normal import). Default: do not send.

**Supabase**
```sql
CREATE TABLE coach_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,   -- null until accepted
  invite_code text UNIQUE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','revoked','declined')),
  can_write boolean NOT NULL DEFAULT true,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```
RLS: coach and client may SELECT their own rows; only the client may set `status = active/revoked/declined` and `client_id` (via a security-definer `accept_coach_link(code)` function that checks expiry and single use). No direct INSERT of `active` rows from the coach.

**Writing into the client's data.** Do **not** open broad RLS on `workouts`/`sets`. The coach never gets generic write access to the client's rows. Instead, a **security-definer RPC** `coach_insert_client_session(link_id, payload jsonb)`:
- verifies `auth.uid()` is the link's `coach_id` and `status = 'active' AND can_write`;
- inserts workout, exercises and sets with `user_id = client_id`, `logged_by = coach_id`, `source_session_id = coach's workout id` (idempotency key; unique per link, so retries are no-ops);
- fills every NOT NULL column explicitly (see section 4);
- returns the created ids.

An edge function is the fallback if payload validation (sane weights, max sets) outgrows SQL. The RPC is preferred: one round trip, atomic, no new deploy surface. The client reads these rows with their normal RLS and sees a "Logged by Alex" badge. Coach reads back only what they wrote (their own copy), never the client's other data.

## 4. Data model

**Core Data:** new model version `Lightstack 5.xcdatamodel` (never edit v4), set current, lightweight migration with defaults, new case in `CoreDataMigrationTests`.
- New entity `CDClient` (above).
- `CDWorkout` gains `clientId: UUID?` and `parentWorkoutId: UUID?`. A client session is a `CDWorkout` owned by the coach (`userId` = coach) with `clientId` set and `parentWorkoutId` = the coach's own workout. Own workouts keep both nil, so all existing queries stay correct once they add `clientId == nil`.
- `CDWorkoutSet` / `CDExercise` need no change: they hang off the client `CDWorkout`.
- `CDWorkout.syncStatus` is reused for the coach-side backup. Add `clientSyncStatus` (`none | pending | synced | failed`) for the push into the client's account.

**Isolation rule (critical):** every existing consumer must exclude `clientId != nil`: stats, PR detection, streaks, `ExerciseHistoryIndex`, month plan adherence, own-progression history, DuplicateWorkoutCleanup, StaleWorkoutCleanup. Centralise as one predicate in `WorkoutRepository` plus a unit test that a client workout changes none of the coach's PRs/volume.

**Supabase (coach's own backup):**
```sql
ALTER TABLE workouts ADD COLUMN client_id uuid;                       -- local client id, nullable
ALTER TABLE workouts ADD COLUMN parent_workout_id uuid;               -- nullable
ALTER TABLE workouts ADD COLUMN logged_by uuid REFERENCES auth.users(id);  -- nullable
CREATE TABLE coach_clients (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL, linked_user_id uuid, link_status text NOT NULL DEFAULT 'guest',
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
-- RLS: owner_id = auth.uid() for all operations.
```
Lessons from the `is_per_arm` incident: send **every NOT NULL column in every insert and bulk payload** (`link_status`, `created_at`, `updated_at`, the RPC's set fields); ship the migration **before** the app build; add a rollback file in `supabase/migrations/rollback`; add a payload test that asserts required keys. `coach_clients` is a new table in the `OfflineQueueManager` FK order, before workouts that reference it.

## 5. Active-workout UI (keep it simple)

**v1 limit: one client per session.** Multi-client is an open question.

- Start: workout setup gets a "Training someone?" row. Pick a client or "New client" (name only). Sets `activeClientId` on `ActiveWorkoutViewModel`.
- During the workout, the coach's exercise cards are unchanged. Under each exercise a **collapsible "Client: Alex" section** (tinted AppTheme accent, labelled) holds the client's pending/logged set rows, reusing `SetRowView` / `PendingSetInput` with a second state dictionary (`clientPendingSets`, `clientLoggedSets`, keyed by exercise id). A header chip "Logging for: You | Alex" is **not** used, because it invites logging to the wrong person; both areas are visible at once.
- The client area is prefilled with the client's own targets (section 6). "Copy my set" button copies the coach's last logged weight/reps for equal-load partners.
- Rest timer, Live Activity and superset logic follow the **coach's** sets only. Logging a client set never starts or resets the coach's rest timer.
- Client exercises mirror the coach's list by default; the coach can hide an exercise for the client or add one only the client does ("client-only" exercise, in the client area).
- Session persistence (`WorkoutSessionPersistence`) stores client state too so a kill/resume restores both.
- Finish: coach's normal post-workout flow, then a second "Client review" step (section 7).

## 6. Progression targets for the client

Targets come from **the client's own history**, never the coach's. `ExerciseHistoryIndex` is built per `clientId` (guest: from that client's stored workouts; linked: same, plus any history in their account within the last 90 days via a read RPC is deferred to phase 2.5). `ProgressionEngine.plan` runs with the client's index. New client with no history: no targets, empty rows, and the first session sets the baseline. No in-session adjuster prompts for the client in v1.

## 7. AI review for the client

- Same `CoachReviewDocument` pipeline, input = client session + client's history, stored on the client workout (`aiProgressionNote`).
- **Cost:** one extra Gemini call per client session. Coach session = 1-2 calls today, so a coach day is about 2-4 calls against 100/day and 10/min on the free tier. The two calls are **sequential, never parallel** and share the existing `check_rate_limit` and refund path.
- Order: coach review first; client review runs after. If rate-limited or 503, the client session is saved with "Review pending" and a retry button (existing "no auto-save on AI failure" rule applies: the session is saved, the review is not invented).
- The prompt states the person is a client trained by a coach ("coach-logged, not self-reported") and drops personal context (body weight, injuries) not stored for that client. Update `docs/COACH_PROMPT.md` and `CoachPromptServiceTests`.
- Review is optional per client session (toggle on the finish screen) to protect quota.

## 8. Export and sync-out

**Export (phase 1)**, from the client session detail and the History row:
- Text summary (default, for iMessage/WhatsApp), CSV (`date, exercise, set, weight, unit, reps, rir`), and PDF (one page, branded, with the review summary).
- Via `ShareLink` / share sheet; files generated into a temp dir and deleted after.
- Respect the coach's weight unit and print it in the file.

**Sync to client account (phase 2):** on finish, if the client's link is `active`, enqueue `coach_insert_client_session` through `OfflineQueueManager`. Status shown on the row: "Sent to Alex" / "Waiting to send" / "Alex removed access". The RPC's `source_session_id` makes retries idempotent. If the link is revoked mid-queue, the op dead-letters, the coach sees "Not sent, access removed" and can export instead. Children (sets) never wait on a dead-lettered parent: the RPC sends the session atomically as one op.

**Dedupe if the client also logs:** a client who logs the same day themselves is not merged. The coach-written workout is tagged `logged_by`, and the client app offers "Possible duplicate" when two workouts land within 3 hours with >= 60 percent exercise overlap, letting the client delete one. No silent merges.

## 9. History

- `HistoryViewModel` gets a filter: **All | Me | <client names>**. Default All. Client sessions render as normal rows with a small name badge ("Alex") and a linked-parent indicator; tapping opens `WorkoutDetailView` in read mode with Export and (re)Send actions.
- A coach day with a client shows grouped: "Mon 3 Nov: You (Push, 52 min) + Alex (Upper, 48 min)".
- Calendar/Progress/PR tabs show only "Me" data (see isolation rule). A "Clients" screen (Profile > Clients) lists each client with last-trained date and session count.
- Deleting a client asks: delete their sessions too, or keep as "Former client". Deleting a coach workout never cascades to the client's account.

## 10. Offline behaviour

Dual logging, targets, History and export are fully local. Backup sync of client sessions rides the existing queue. Linking, the push into a client's account and AI review need network and degrade to visible "waiting" states.

## 11. Privacy

- Client data is health data. Guest clients' data is the coach's; show a one-line consent note when creating a client ("Only add people who agree").
- Linked clients control access (revoke), see exactly what the coach wrote, and the coach never reads the client's own logs, profile or other workouts.
- No client name or data sent to Gemini beyond numbers and exercise names (no display name in prompts).
- Account deletion removes the coach's `coach_clients` and client workouts; a client's deletion cascades `coach_links`.
- Export files contain the name only if the coach includes it (toggle).

## 12. Accessibility and tests

Identifiers: `coach.clientRow` (setup), `coach.newClientButton`, `coach.clientName`, `coach.clientSection.<exerciseId>`, `coach.clientSet.weight`, `.reps`, `.rir`, `.logButton`, `coach.copyMySet`, `coach.finishClientReview`, `coach.exportButton`, `coach.history.filter`, `coach.history.clientBadge`, `coach.link.inviteCode`, `coach.link.status`, `settings.coaches.row`, `settings.coaches.approve`, `settings.coaches.revoke`.

VoiceOver: client section is a labelled group "Alex's sets for Bench press"; rows announce "Alex, set 2, 135 pounds, 8 reps". Colour is not the only coach/client distinction (text label too). Dynamic Type safe; targets >= 44 pt.

**Unit tests:** v4 to v5 migration defaults; client workouts excluded from stats/PRs/streaks/history index; per-client progression targets; export formatters (CSV/text); sync payload has all NOT NULL keys; dedupe heuristic.
**UI tests** (seeded `-uiTesting` store, fake AI): create client, dual-log a set each, finish, see client review, History filter by client, export sheet appears; phase 2 with a stubbed link state.
**RLS tests** (SQL): coach cannot insert for revoked/pending/other users' links; client cannot be written to without an active link; idempotent retry.

## 13. Phases

**Phase 1: local clients (no Supabase schema for linking).**
1. Core Data v5 (`CDClient`, `clientId`, `parentWorkoutId`) + isolation predicate + tests.
2. Setup picker + dual-logging area in active workout + session persistence.
3. Client progression targets + client AI review (optional toggle).
4. History filter/badge/grouping + Clients screen.
5. Export (text, CSV, PDF).
6. Backup of `coach_clients` and client workouts to the coach's own account.

**Phase 2: account linking.** `coach_links` + RPCs + RLS tests, invite/approve/revoke UI, queue op, sync status UI, duplicate prompt, "send past sessions" option.

## 14. Risks

- **Isolation leaks** (client sets polluting the coach's PRs/stats): mitigated by one shared predicate and tests.
- **Wrong-person logging / UI clutter** on a small screen: side-by-side areas, per-exercise collapse, UI test coverage.
- **Rate limits** with two reviews per session: sequential, optional, pending state.
- **RLS mistakes** exposing client data: security-definer RPC only, no direct policies, SQL tests.
- **Migration/sync wedges** (is_per_arm class): explicit NOT NULL columns, migration before build.
- **Scope creep** into a full trainer product (programs, billing, chat): out of scope.

## 15. Open questions

1. Multiple clients in one session (group training) in v1 or later?
2. Should the client be able to edit or reject a coach-written session, or only delete it?
3. Is guest-client data allowed to move into an account later automatically (on link), or only by the coach's explicit "send past sessions"?
4. Does the client area mirror the coach's exercise list by default, or start empty?
5. PDF branding and whether exports include the AI review text.
6. Any limit on the number of clients (free tier / storage)?
