# Local Data and Session Security Audit

Scope: data LightStack writes on the device, logging, and session handling. Status is **Fixed** (in this change) or **Recommended** (needs an edit in a file owned by another workstream).

## 1. Local data inventory

| Item | Location | Contents | Sensitivity | Protection after this change |
|---|---|---|---|---|
| Core Data store | `Application Support/Lightstack.sqlite` (+ `-wal`, `-shm`); UI tests use `Lightstack-UITests.sqlite` | profile (age, height, weight, goals, notes to coach), workouts, nutrition, food log, water, notes | High (health data) | `completeUntilFirstUserAuthentication`, set on the store description and re-applied to the three files after load |
| Offline queue | `Application Support/OfflineQueue/*.json` (queue, failed) | JSON payloads of pending writes, tagged with `ownerUserId` | High (same data as above) | Written with `.atomic` only. **Recommended:** add `.completeFileProtectionUntilFirstUserAuthentication` at `OfflineQueueManager.swift:1524` and `:1565` (and the directory attributes at `:1479`/`:1563`) |
| Legacy queue | UserDefaults `lightstack_offline_queue_v1` | old copy, left in place for one release | High | **Recommended:** delete the key once `lightstack_offline_queue_v1_migrated` is set (`OfflineQueueManager.swift:~1485`). UserDefaults plist is not file-protected by class C beyond the app default |
| Coach debug snapshot | UserDefaults `coach.debug.lastPlan` | full prompt and AI reply (training history, goals, notes) | High | **Fixed:** Release stores only labels and lengths (`[redacted, N chars]`), no adjustments or review. DEBUG keeps full text. 24 h expiry. 50 KB cap. Cleared by `CoachDebugStore.clearAll()` |
| Diagnostics | `Application Support/Diagnostics/diagnostics.json`, export copy in `tmp/` | MetricKit crash/hang summaries and top frames (no user content) | Low | **Fixed:** protection class C, excluded from backup, export file protected, `DiagnosticsStore.clearAll()` removes both |
| OpenFoodFacts cache | JSON cache file written by `OpenFoodFactsService.swift:176` | public product data and search strings the user typed | Low-medium (search terms reveal diet) | **Recommended:** add `.completeFileProtectionUntilFirstUserAuthentication` to the write; store in Caches (not backed up) |
| `lightstack.lastKnownSignedInUserId` | UserDefaults | user UUID | Low | Removed on sign-out (`AuthService.swift:434`) |
| `lightstack.expiredSessionUserId` | UserDefaults | user UUID, drives the expired banner | Low | Cleared on sign-in and sign-out |
| `pending_verification_password` | Keychain (`WhenUnlockedThisDeviceOnly`) | password during email verification | High | OK. Deleted when set to nil. See finding L-4 |
| `coach.exerciseFeedback`, `coach.focus`, `lightstack.perArmPreferences.v1`, `com.lightstack.activeWorkoutSession`, `ai_usage_debug_v1`, `lightstack.lastSuccessfulRestore.<uuid>` | UserDefaults | training feedback, coach preferences, in-progress workout, AI token counts, restore timestamps | Medium | Not cleared on sign-out. See finding S-3 |
| UI prefs (`weightUnit`, `selectedTab`, `appSide`, `nutritionSelectedTab`, `restTimerNotificationsEnabled`, `liveActivityEnabled`, `appColorScheme`, `hasCompletedOnboarding`, `nutritionWaterUnit`, `nutritionSetupSkipped`, rest seconds, `distanceMiles` etc.) | UserDefaults | preferences | Low | None needed |
| Auth session (access and refresh token) | Supabase Swift stores it itself. The client is created at `AppEnvironment.swift:103` with the default auth storage, which on iOS is the Keychain (`KeychainLocalStorage`, not UserDefaults) | JWT and refresh token | High | OK. Confirm the pinned supabase-swift version still defaults to Keychain; see L-5 |
| Coach chat threads, goals | Not persisted outside Core Data (`CDAIContextSummary`) and `ChatMessage` is in memory | AI summaries of the user | High | Covered by the Core Data protection and `wipeAllUserData()` |

### Why `completeUntilFirstUserAuthentication` and not `.complete`

`.complete` makes the file unreadable whenever the device is locked. LightStack writes to Core Data from background sync (BGTask and app refresh), rest-timer notification handling and Live Activity updates, all of which run while locked. A `.complete` store would throw on open or on write in those cases and drop or wedge sync. `completeUntilFirstUserAuthentication` still encrypts the data at rest until the user unlocks once after boot (which covers a stolen, powered-off device) and keeps background work working.

### Backup

- Core Data store and offline queue stay **included** in device and iCloud backups on purpose: unsynced edits would be lost on a restore otherwise. They are protected by the backup's own encryption.
- Diagnostics are now excluded from backup (`isExcludedFromBackup`).
- Recommended: exclude the OpenFoodFacts cache.

## 2. Logging

`os.Logger` interpolations of non-numeric values are redacted (`<private>`) in logs captured from a device unless a debugger is attached, but Console on a debug build shows them. Nothing in the app logs tokens, emails or passwords. Prompts and AI replies are logged at `debug` level in these places (not in files this workstream owns):

| File:line | Issue | Change |
|---|---|---|
| `Lightstack/Features/AICoach/Services/GeminiService.swift:258` | `logger.debug("Raw API response: \(responseString)")` logs the full AI reply | `\(responseString, privacy: .private)` or delete; wrap in `#if DEBUG` |
| `Lightstack/Features/AICoach/Services/GeminiService.swift:268` | `API error: \(message)` may echo server text | `\(message, privacy: .private)` |
| `Lightstack/Features/MonthPlan/Services/MonthPlanService.swift:66` | `Raw AI response: \(responseText)` | same as above |
| `Lightstack/Features/Auth/Services/AuthService.swift:344` | message mentions token exchange but logs no token | no change |
| `Lightstack/Core/Services/LocalStorageService.swift:66,70` | split days (not personal) | left as is; default redaction applies |

No `print(` calls exist in the app target. Status: owned files clean; others **Recommended**.

## 3. Session security review

| # | Finding | Severity | Status |
|---|---|---|---|
| S-1 | **Sign-out keeps all local data on disk**: `AppEnvironment.authServiceDidSignOut` (`AppEnvironment.swift:426`) only resets flags. Core Data reads are filtered by `userId`, so user B never sees user A's rows in the UI, but A's health data stays readable on the device (and in backups) after A signs out and B signs in. | Medium | Recommended |
| S-2 | **Account deletion** has no local wipe (no `deleteAccount` in the app). After deletion the user's data, queue and caches remain. | High (when delete-account ships) | API added: `LocalStorageService.wipeAllUserData()`. Caller must also clear the queue (workstream E) |
| S-3 | **UserDefaults leak across accounts**: `coach.exerciseFeedback`, `coach.focus`, per-arm prefs, `activeWorkoutSession` and `lightstack.lastSuccessfulRestore.*` are not user-scoped or cleared on sign-out. User B inherits A's coach preferences and could resume A's in-progress workout. | Medium | Recommended |
| S-4 | **Legacy queue operations with `ownerUserId == nil`** are adopted by whoever signs in next (`OfflineQueueManager.swift:1293-1301`, `belongs` at `:1315`). Such ops predate owner tagging. If B signs in first they upload under B. | Low | Recommended |
| S-5 | **Sign-out with pending queue** is handled well: ops keep their owner, `flush` re-checks `ownerProvider() == owner` (`OfflineQueueManager.swift:1133`), and `expiry.handleSignIn` reports `.differentUser` without touching A's ops. They stay on disk until A signs in again. This is the right trade-off for not losing data, but combined with S-1 means A's data persists indefinitely. | Info | OK |
| S-6 | **Sign-out failure path**: `signOut()` (`AuthService.swift:415`) clears the debug store and sets `userSignOutAt` before the network call. If `auth.signOut()` throws a non-`sessionMissing` error (offline), `finishSignOut()` never runs, so the session may still be valid locally and `notifySignOut()` is never sent while the user believes they signed out. | Medium | Recommended |
| S-7 | **Expiry detection** relies on a 10 second window after a user sign-out (`AuthService.swift:455`). Reasonable. `isSessionRejected` correctly treats 4xx (except 408, 429) as dead. Refresh is handled by supabase-swift's auto-refresh. | Info | OK |
| S-8 | **Unauthorized requests after logout**: Supabase calls read the current session from the client, so after `signOut` they have no JWT and fail with `sessionMissing`/401, and the classifier maps that to the expired state. The only unguarded path is S-6. | Low | OK apart from S-6 |
| L-4 | `pendingVerificationPassword` kept in Keychain until verification ends. Item is `WhenUnlockedThisDeviceOnly`, which is right. Confirm it is deleted on every exit path (verification success, cancel, sign-out): sign-out sets it to nil at `AppEnvironment.swift:441`. | Low | OK |
| L-5 | Session token storage: default supabase-swift auth storage. Verify against the resolved package version in `Package.resolved`; if an old version used UserDefaults, pass `auth: .init(storage: KeychainLocalStorage(...))` explicitly at `AppEnvironment.swift:104`. | Low | Verify |
| L-1 | Core Data store had no explicit protection class (iOS default for app files is class C already `completeUntilFirstUserAuthentication`, but it was not declared and not guaranteed for the wal/shm files). | Low | Fixed |
| L-2 | `CoachDebugStore` persisted full prompts and replies in Release. | Medium | Fixed |
| L-3 | Diagnostics export left a copy in `tmp/` after sign-out and was backed up. | Low | Fixed |

### Recommended code changes in files this workstream does not own

1. `AuthService.swift:416` replace `CoachDebugStore.shared.clear()` with `LocalStorageService.clearSessionScopedCaches()`. Also call it from `finishSignOut()` (`:432`) so it runs after a successful sign-out, not only when the button is pressed.
2. `AuthService.swift:415-428` S-6: in the generic `catch` branch, either call `await finishSignOut()` as well (local sign-out always wins) after trying `signOut(scope: .local)`, or surface the error and keep the UI in the signed-in state. Prefer the first: `try? await supabaseClient.auth.signOut(scope: .local)` then `finishSignOut()`.
3. `AppEnvironment.swift:426` (`authServiceDidSignOut`): when the signing-out user's queue is empty (`offlineQueue` has no ops for that owner) call `localStorageService.wipeAllUserData()` and clear the user-scoped UserDefaults keys from S-3; when the queue is not empty keep the data (current behaviour) and show the existing unsynced-changes warning. Always call `LocalStorageService.clearSessionScopedCaches()`. Only wipe while `flush` is idle (cancel the flush task and wait first).
4. `AppEnvironment.swift:397-402` (`.differentUser`): before B continues, if A has no queued ops, wipe A's rows with `wipeAllUserData()`; otherwise leave A's rows (they are `userId` scoped).
5. `OfflineQueueManager.swift:1524, 1565`: use `.atomic` plus `.completeFileProtectionUntilFirstUserAuthentication`; create the directory with `attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]` (`:1479`, `:1563`). Delete the legacy UserDefaults queue key after migration (`:1485`).
6. `OfflineQueueManager.swift:1315` (`belongs`): stop treating `ownerUserId == nil` as belonging to any user once `adoptLegacyOperations` has run for one release.
7. `OpenFoodFactsService.swift:176`: add `.completeFileProtectionUntilFirstUserAuthentication`.
8. `GeminiService.swift:258,268` and `MonthPlanService.swift:66`: see section 2.
9. Account deletion flow (workstream C): after the server confirms deletion call, in order: cancel sync and flush, clear the offline queue, `localStorageService.wipeAllUserData()`, `LocalStorageService.clearSessionScopedCaches()`, remove the S-3 UserDefaults keys, then sign out.

## 4. APIs added

- `LocalStorageService.applyFileProtection(to:)` and `LocalStorageService.protectStoreFiles(at:)`
- `LocalStorageService.wipeAllUserData() -> Bool` (instance, `@discardableResult`; returns false and changes nothing if a `performBatch` is open; uses batch deletes on the view context and merges the result, so open fetched results see the deletion)
- `LocalStorageService.clearSessionScopedCaches()` (static; clears coach debug store and diagnostics)
- `CoachDebugStore.clearAll()` (static)
- `DiagnosticsStore.clearAll()` (static)
- `CoachDebugStore.init(defaults:redactContent:)`, `CoachDebugStore.redacted(_:)`, `CoachDebugStore.maxAge`

## 5. Tests (not executed; no Xcode on this machine)

`LightstackTests/SecurityHardeningTests.swift`, class `LocalDataProtectionTests`: store description carries the protection key, Release-mode redaction, snapshot expiry, `clearAll`, diagnostics `clear`, `wipeAllUserData`.
