# Sync design: restore (Phase 2.3)

Writes go local-first, then through the ordered outbox (`OfflineQueueManager`) as upserts. Restore is the read half:
`SyncRestoreService` downloads the account's cloud data into Core Data.

## Rules
1. **Restore never uploads what it downloads.** Remote-origin writes use `LocalStorageService` bulk upserts and
   never touch the outbox. Only the repair step (rule 8) queues anything.
2. **Tombstones win**, including over pending upserts: restore drops queued upserts for tombstoned records (deletes and
   tombstones stay queued), so they cannot recreate a stray cloud row. Tombstoned workouts, exercises, sets, plans, planned sessions and rest days (by id) are deleted
   locally and never restored. The active workout is never deleted. A rest day is one row per (user, date): a cloud rest day
   on a day that already has a local row updates that row in place (adopting the cloud id).
3. **Local pending changes win.** A record with any queued or dead-lettered operation (`PendingChangeIndex`, includes
   deletes and pending tombstones) is skipped. Workouts are judged as a unit: an operation on the header, its
   exercises, or any of their sets keeps the whole workout local.
4. **Otherwise the cloud wins**, upserting by id. Profile, context summaries (by user + workout type), the active
   month plan and its sessions follow the same rules.
5. **The active workout is skipped** (saved session state or `WorkoutSessionService.currentWorkout`).
6. **No junk.** Cloud workouts with no worked exercise are not restored; exercises with no sets are dropped. Nothing is
   deleted from the cloud.
7. **PRs are recomputed locally** from the restored sets (`recalculateAllPRs(uploadChanges: false)`). Cloud
   `personal_records` (an append-only log) are not read.
8. **Repair upload.** After EVERY fetch completed, local workouts (with exercises and sets) and rest days that are
   not in the cloud, not tombstoned and have no pending operation are queued as normal upserts. A cloud workout with
   no worked exercise gets its local exercises and sets queued (header untouched). Empty workouts and setless
   exercises are never uploaded. A failed or partial fetch repairs nothing and does not record a successful restore.
9. Everything is scoped to the signed-in user; the user is re-checked after every await and a change aborts the restore.

## First reconciliation (existing installs)
Before tombstones existed, the old queue silently dropped some edits (history edits, set updates), so on an existing
install the local copy can be NEWER than the cloud. Until one complete restore has finished for a user on this device
(`lightstack.firstReconciliationDone.<userId>`), a restore on a device that already has data for that user (a profile, a
workout or a rest day) runs LOCAL-AUTHORITATIVE:
- Tombstones still apply first (deleted elsewhere on purpose), and pending-op / active-workout rules are unchanged.
- Cloud workouts with no local counterpart are added (whole subtree, junk rules apply), unless tombstoned.
- A workout that exists locally is never changed locally and never gains cloud-only exercises or sets. If its header,
  an exercise or a set differs, the local version is queued as an upsert.
- Cloud-only exercises and sets of such a workout are queued for deletion with tombstones, but ONLY when the local copy
  has at least one worked exercise (an empty or damaged local copy never triggers deletes).
- Rest days on the same day with different ids: keep local, upload local. Cloud-only days are added.
- Profile: a local profile is kept and upserted. Context summaries: local kept and upserted if different; cloud-only added.
  A local month plan with the same id is kept.
- PRs are recomputed locally (no cloud PR operations), local-only rows are repaired as usual.
- The flag is set only after the whole run succeeded. A fresh install (no local data, or the blocking restore right after
  a profile was restored) uses the normal remote-wins rules and sets the flag too. After that the normal rules apply.

## Fetching
- History: one embedded select, `workouts?select=*,exercises(*,sets(*))`, `order=date.desc,id.asc`, pages of 100 until a
  short page.
- Tombstones are always fetched in full. A "since" cursor is unsafe: a tombstone keeps the device's deletion time and an
  offline device uploads it days later.
- `DATE` columns come back as `yyyy-MM-dd`, which the Supabase client's decoder rejects. `RemoteRecords.swift` decodes them.
- **Writes:** every DATE column (`workouts.date`, `personal_records.date_achieved`, plan start/end, planned session date,
  `rest_days.date`) is sent as the device-local `yyyy-MM-dd` (`SupabaseDateRows.swift`, `SupabaseWorkout`). Older builds sent a
  full instant, so Postgres kept the UTC day (an evening workout west of UTC sits one day late).
- **Reading workout dates:** if `created_at` falls on the stored UTC day the row is treated as legacy and `created_at` is the
  date; otherwise the stored day at local noon. Both give the right local day for legacy and current rows.

## When it runs
- **No local profile for the signed-in user** (sign-in or launch): full-screen restore (`restoreProgressView`). Profile
  lookup has a 15 s deadline. Found: profile saved, onboarding skipped, history restored on the same screen (bounded to
  60 s; the rest continues on the next trigger). Not found: onboarding. Unreachable: "Couldn't reach your account"
  with Retry / Set up as new.
- **Onboarding's Finish** re-checks the cloud first: an existing profile is adopted instead of overwritten; if the cloud
  cannot be reached nothing is saved.
- **Background** on launch and foreground when signed in: after the outbox flush, at most every 6 hours per user
  (`lightstack.lastSuccessfulRestore.<userId>` in UserDefaults).

## Known limits
- Repair works at workout level. A cloud workout that has some but not all of its exercises is not completed.
- A change made in the instant between computing the pending index and applying a page can be overwritten.
