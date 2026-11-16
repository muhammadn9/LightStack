# UX Audit (launch readiness)

Date: 2026-11-05. Method: static read of SwiftUI views under `Lightstack/Features` and `Lightstack/App` on `claude/production-readiness-hardening`. Nothing was run on a device, so items marked (verify) need a simulator or TestFlight check. Severity: **B** = blocker for a public launch, **H** = should fix before launch, **N** = nice to have.

## 1. Summary

The core loop (generate, confirm, log sets, finish, review) is solid and has strong offline handling. The launch risks are mostly around trust and recovery: AI failures surface raw error text, there is no privacy consent or account deletion, kg users get lbs UI, and backup state is visible only deep in Settings.

## 2. Blockers

| # | Sev | Area | Finding | Where |
|---|---|---|---|---|
| 1 | B | AI error recovery | Plan generation failure shows a generic system "Error" alert with `error.localizedDescription`, e.g. "API error: ..." or "All AI providers are currently unavailable". No Retry button, no explanation of timeout (proxy times out at 45s), no "your workout is not lost, log manually" path. The 429 daily-limit text from the proxy shows through the same alert. | `Today/ViewModels/TodayViewModel.swift:327,446`; `Today/Views/WorkoutSessionSheet.swift:109-115`; `Core/Services/AIProvider.swift:140-150` |
| 2 | B | AI error recovery (chat) | Chat failure appends a coach bubble "Sorry, I couldn't respond right now. Please try again. (\<raw error\>)" with no retry control and leaks technical text. Month plan builder does the same. | `AICoach/ViewModels/CoachChatViewModel.swift:164`; `MonthPlan/ViewModels/PlanBuilderViewModel.swift:83` |
| 3 | B | Units | Settings offers lbs/kg (`weightUnit`) but logging and prompts are hard-coded to lbs: set rows say "lbs", the prompt sends "lb" and "weight in lb". The setting only affects the Live Activity. A kg user logs wrong numbers silently. Either implement conversion everywhere or remove the picker for launch. | `Settings/SettingsView.swift:51-56`; `Today/Views/ActiveWorkoutSetRows.swift:169`; `AICoach/Services/CoachPromptService.swift:59,89,154`; only consumer: `Today/LiveActivity/LiveActivityController.swift:96` |
| 4 | B | Consent / trust | Workout history, profile (age, weight, height, injuries or notes) go to Google Gemini with no consent screen, no AI disclosure in onboarding or login, and no privacy policy link anywhere in the UI. This is also an App Review blocker; see `APP_REVIEW_COMPLIANCE.md`. | `Auth/Views/LoginView.swift`, `Auth/Views/OnboardingView.swift`, `Settings/SettingsView.swift` |
| 5 | B | Account | No Delete Account and no data export in Settings (only Sign Out). Required by Apple 5.1.1(v). | `Settings/SettingsView.swift:75-88` |

## 3. High priority

| # | Sev | Area | Finding | Where |
|---|---|---|---|---|
| 6 | H | Sync visibility | Backup status exists (`BackupStatusRow`: backed up / failed / signed out) but only inside Settings > Backup, reached from Profile's gear. A signed-out banner shows (`SessionExpiredBanner`) but a failed or stalled queue shows nothing on Today/History. Users who lose a phone will not know changes were unsynced. Add a subtle "N changes waiting to back up" chip on Profile and Today when the queue is non-empty for more than a few minutes. | `Settings/SessionExpiredBanner.swift:50-82`; `App/MainTabView.swift:49` |
| 7 | H | Sync errors | "Couldn't back up" alert prints `type: code/message` lines (internal operation names) to the user. Translate to plain language and keep the technical detail behind Diagnostics. | `Settings/SessionExpiredBanner.swift:78-82` |
| 8 | H | Sign-out | Sign-out with unsynced changes says they "will upload next time you sign in on this device", but another user signing in or an app reinstall loses them. Offer "Back up now and sign out" as the primary action. | `Settings/SettingsView.swift:90-98` |
| 9 | H | First workout | First run: after onboarding the user lands on Today and must pick a type and wait for generation with a spinner (`ProgressView`), no cancel, no time expectation ("up to a minute"), and no fallback. Manual entry exists (`ManualWorkoutEntryView`) but is not offered from the failure state. | `Today/Views/WorkoutSessionSheet.swift:41,142`; `Today/Views/WorkoutSetupView.swift:233` |
| 10 | H | Rate limit | The 100/day and 10/min server limits give a message but the app does not show remaining quota or a countdown, and there is no upgrade path (no StoreKit). | `Core/Services/AIProvider.swift:144`; proxy `supabase/functions/ai-proxy/index.ts` |
| 11 | H | Onboarding | 3 steps (profile, split days, equipment) is reasonable, but requires age and a name, with free-text split days and no explanation of what the AI will do with the data or what is optional. No skip. Account is already created before onboarding so abandoning mid-way is possible; verify the resume path. | `Auth/Views/OnboardingView.swift:14-30,320-330` |
| 12 | H | Camera features | Form analysis is enabled (`formAnalysisEnabled = true`) but flag comment says "pending on-device validation". Ships camera plus pose model plus AI feedback unvalidated. Decide: validate on device, or set the flag to `false` for 1.0. | `Core/Utilities/FeatureFlags.swift:11`; gate `Today/Views/ExerciseHeaderView.swift:154,176` |

## 4. Nice to have

| # | Sev | Area | Finding | Where |
|---|---|---|---|---|
| 13 | N | Logging sets | Per-set inputs are three text fields with decimal or number pads. Prefill hints exist (good). Missing: quick +/- steppers for weight, "same as last set" copy, and a visible undo for an accidentally logged set. Verify keyboard "Done" handling with the number pad (no return key). | `Today/Views/ActiveWorkoutSetRows.swift:169-206` |
| 14 | N | Adjusting a workout | Mid-workout adjustments (swap exercise, reorder, add, coach chat modifications with a confirmation sheet) are rich. The AI modification path requires an AI call; no offline-friendly "swap with similar" is evident beyond `ExerciseSwapSheet`. Confirmation sheet is good. | `Today/Views/ExerciseSwapSheet.swift`; `AICoach/Views/ModificationConfirmationSheet.swift` |
| 15 | N | History | Good empty state ("No workout history yet"), edit and import exist. Import uses AI (`WorkoutImportService`) and can fail like plan generation; same error treatment needed (see #1). Pagination or search for large histories (verify). | `History/Views/HistoryListView.swift:115-123`; `History/Services/WorkoutImportService.swift` |
| 16 | N | Progress | Good empty states ("No workouts yet", "Log sets with weight and reps to see lift trends"). Charts rely on custom components with no VoiceOver summary (verify). | `Progress/Views/ProgressTabView.swift:82,141,210` |
| 17 | N | Accessibility | Accessibility identifiers are thorough (for UI tests), but labels and Dynamic Type were not audited. The custom serif (Playfair) italics may not scale. | App-wide |
| 18 | N | Disabled placeholder | Nutrition add-menu shows a disabled "AI search, coming soon" button. Ship without it or hide it. | `Nutrition/AddMenuSheet.swift:30` |
| 19 | N | Diagnostics | Diagnostics screen is user visible and useful for support; add "Contact support" with the log attached. | `Settings/DiagnosticsView.swift` |
| 20 | N | Nutrition scanner | A DEBUG-only scan stub exists (`#if DEBUG`), so it cannot ship; the real label scanner needs camera permission copy that covers both uses (it does: `Info.plist` NSCameraUsageDescription mentions both). | `Nutrition/NutritionScanStub.swift:1`; `Info.plist:52` |

## 5. Experimental or unfinished features and flags

All flags live in `Lightstack/Core/Utilities/FeatureFlags.swift` as compile-time `static let` constants (no remote kill switch).

| Feature | Flag | State | Notes / recommendation |
|---|---|---|---|
| Form analysis (camera, pose, AI feedback) | `formAnalysisEnabled = true` | On, "pending on-device validation" | Highest risk: camera permission, on-device performance, AI cost, and a health/safety claim ("form feedback"). Recommend off for 1.0, or on with a clear "beta" label and disclaimer. Also wants a remote kill switch. |
| Month plan | `monthTabEnabled = false` | Hidden; code fully present | Safe: tab and view model creation are both gated (`MainTabView.swift:36,58`). Dead code still compiles into the app and ships its AI prompt; acceptable. Confirm no other entry point reaches `MonthPlanView`/`PlanBuilderChatView` (grep shows only `MainTabView`). |
| Nutrition tab | `nutritionTabEnabled = true` | On | Active development (phases 1-3 merged: goals, journal, barcode, Open Food Facts). Sends barcodes and search text to Open Food Facts (third party; mention in privacy policy). "AI search, coming soon" is a disabled placeholder (#18). Calorie targets use Mifflin-St Jeor (`NutritionGoals.swift:213`): add a "not medical advice" note. |
| Live Activity | User setting, default on | On | Fine. |
| Debug sections | `#if DEBUG` | Excluded from Release | AI usage and sync queue debug sections do not ship. Good. |

Recommendation: turn flags into server-delivered config (a small `app_config` table or edge function) so form analysis and AI features can be disabled after release without an App Store build.

## 6. Flow-by-flow notes

- **Onboarding**: functional and short; missing consent, unit choice (lbs/kg) and goal-setting clarity (#3, #4, #11).
- **First workout generation**: good hands-off defaults ("time, energy, constraints and focus are all optional" in `TodayViewModel.generatePlan`). Weak failure path (#1, #9).
- **Logging sets**: strong (prefill hints, rest timer, supersets, per-arm, PR toast, Live Activity, session persistence for app kills via `WorkoutSessionPersistence`). Minor input ergonomics (#13).
- **Adjusting a workout**: swap, reorder, add, coach-driven modifications with confirmation. OK.
- **AI error recovery**: the weakest flow. Raw errors, no retry, no offline messaging (#1, #2, #10). A user in airplane mode gets "Couldn't reach..." style text from whichever layer fails first; add an explicit offline check before calling.
- **Sync/backup visibility**: infrastructure is excellent (offline queue, dead-letter, retry, restore, diagnostics) but not surfaced (#6, #7, #8).
- **History**: solid; edit, merge, import present (#15).
- **Progress**: solid with empty states (#16).
