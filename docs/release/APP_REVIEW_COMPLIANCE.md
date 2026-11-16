# App Review Compliance Audit

Date: 2026-11-05. Repo state: `claude/production-readiness-hardening`. Method: repo grep plus web search. Apple's guideline pages were not directly fetchable from the research sandbox, so wording below comes from Apple's App Review Help snippets and secondary coverage; **re-read the live guidelines (developer.apple.com/app-store/review/guidelines) before submission.** This is an engineering checklist, not legal advice.

Sources: [Apple: account deletion (5.1.1)](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion), [Apple news: account deletion requirement](https://developer.apple.com/news?id=12m75xbj), [TechCrunch: Nov 2025 guideline update on third-party AI](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai), [QAwerk: AI data sharing declarations](https://qawerk.com/blog/apple-app-store-ai-data-sharing-guidelines/), [Apple forums: 5.1.2(i) rejection](https://developer.apple.com/forums/thread/820209), [NativeScript: privacy manifests](https://blog.nativescript.org/ios-privacy-manifests/).

## 1. Gap list

| # | Severity | Requirement | Finding in repo | Fix |
|---|---|---|---|---|
| 1 | **Blocker** | 5.1.1(v) Account deletion in-app | None. `Settings/SettingsView.swift` Account section has only Sign Out. No edge function or RPC deletes a user (grep for `deleteUser`/`delete_user` in `supabase/` and `Lightstack/` is empty). | Add Delete Account (Settings > Account) with confirmation; edge function `delete-account` using `SUPABASE_SERVICE_ROLE_KEY`: delete user rows (cascade or explicit), `auth.admin.deleteUser`, and revoke the Apple token when the user signed in with Apple. Clear local store and queue. State "deleted immediately". |
| 2 | **Blocker** | 5.1.1(v) + Sign in with Apple token revocation | The app supports Sign in with Apple (`LoginView.swift:162`, `AuthService.signInWithApple`). On deletion the Apple refresh token must be revoked via Apple's REST API (`/auth/revoke`). Needs the Apple team ID, key ID, `.p8` private key, services ID (client_id) held server-side, and the authorization code captured at sign-in. The code is only valid about 10 minutes (forum report), so exchange it for a refresh token at sign-in and store it server-side. Nothing exists today. | Implement in the same edge function; store Apple secrets as function secrets (see release checklist). |
| 3 | **Blocker** | 5.1.2(i) Consent before sharing personal data with third-party AI (Nov 2025 update) | Workout history, body stats (age, weight, height), training notes, nutrition goals and chat text are sent via `ai-proxy` to Google Gemini. No in-app disclosure or consent anywhere (grep: no consent, disclosure or privacy strings in Swift). A privacy-policy line alone is reported to be insufficient in rejections. | First-run (and post-update) consent screen, before any AI call: names Google Gemini as the recipient, lists exactly what is sent (workout history, profile stats, chat messages, notes), why, links the privacy policy, with explicit Agree / Not now. Store consent (timestamp, version) locally and in Supabase; the proxy should refuse AI calls without recorded consent. Must work if the user declines (manual logging stays usable). Add a Settings toggle to withdraw. Mention it in App Review notes and show reviewers how to reach it (rejection threads report reviewers missing the screen). |
| 4 | **Blocker** | Privacy policy URL (App Store Connect field) and in-app link | No privacy policy or terms link anywhere in the app (`grep -i "privacy policy"` finds none). No policy document in the repo. | Publish a policy at a stable HTTPS URL; add it to App Store Connect (required) and add links in Login, Settings and the consent screen. Add Terms of Use link too (needed once subscriptions exist; see 5.1.1 and 3.1.2). |
| 5 | **High** | PrivacyInfo.xcprivacy manifest | **No `PrivacyInfo.xcprivacy` exists** (`find` returns nothing). Since 1 May 2024 App Store Connect rejects apps using Required Reason APIs without declared reasons (ITMS-91053). | Add the file to the app target (and the widget extension if it uses the APIs). See section 3. |
| 6 | **High** | Privacy Nutrition Labels | Not yet filled in or documented. Mapping in section 2. | Complete in App Store Connect before first external TestFlight and review. |
| 7 | **High** | Health/fitness claims, 1.4.1 and 5.1.3 | The app gives training and nutrition guidance (calorie targets by Mifflin-St Jeor in `Core/Models/NutritionGoals.swift:213`, AI coaching, form feedback). No disclaimer in UI. | Add a "not medical advice; consult a professional" notice at onboarding and on the nutrition setup, avoid claims of injury prevention, accuracy of calorie or body measurements, or medical benefit in metadata. Form analysis should be labelled as guidance only (or disabled for 1.0). |
| 8 | Medium | 4.8 Login Services (Sign in with Apple when third-party login is offered) | **Compliant**: Google Sign-In (`LoginView.swift:143`) is offered alongside Sign in with Apple (`LoginView.swift:162`) and email/password. Keep Apple at least as prominent as Google. | Verify button ordering/size on device. Test Apple "Hide My Email" relays: confirm the password-reset and verification emails work for relay addresses. |
| 9 | Medium | 5.1.1(ii)/(iii) Data minimisation and permission strings | Only `NSCameraUsageDescription` is declared (`Info.plist:52`): covers form analysis and label scanning. No microphone, photos, location or HealthKit use found. Camera string should state that frames are processed on device (pose estimation uses Vision, `PoseEstimationService.swift`) and not uploaded; confirm that is true. | Verify no frames reach the AI proxy; update copy to say so. |
| 10 | Medium | 5.1.2 Third-party SDK/data disclosures | Open Food Facts (barcode and search text sent to `world.openfoodfacts.org`, `search.openfoodfacts.org`), Google Sign-In, Supabase (hosting), Gemini. No analytics or ad SDKs found (grep for Firebase, Sentry, Crashlytics, PostHog: none), so no ATT prompt is needed and `NSUserTrackingUsageDescription` is correctly absent. | List all four recipients in the privacy policy. Keep "Data used to track you" = No. |
| 11 | Medium | Sandbox/test accounts for review (2.1) | Review needs a working login. App Review cannot use real Apple or Google accounts. | Create a demo email/password account pre-seeded with history; put it in App Review Information. Make sure the AI path works for it (the daily 100-call limit and any future paywall must not block the reviewer). |
| 12 | Medium | 3.1.1 In-app purchase (if subscriptions are added) | No StoreKit code exists. Selling AI credits or subscriptions must use IAP. | Adopt StoreKit 2 before enabling any paid tier; include Restore Purchases and auto-renew disclosure text. See cost model for pricing. |
| 13 | Low | 5.1.1(i) Privacy policy for user content and 1.2 UGC | Chat messages go to the AI only. No user-to-user content, so 1.2 does not apply. AI-generated content: keep a way to report bad output if reviewers ask (Apple has asked generative-AI apps for reporting). | Add a "Report a problem" action on coach messages (email link is enough). |
| 14 | Low | 2.3.1 Hidden/undocumented features and 2.2 betas | Month plan is flag-hidden and nutrition AI search is a disabled "coming soon" button (`Nutrition/AddMenuSheet.swift:30`). Apple dislikes "coming soon" UI. | Remove placeholder for 1.0. |
| 15 | Low | Export compliance | `ITSAppUsesNonExemptEncryption = false` is set (`Info.plist`). Correct for standard HTTPS only. | None. |

## 2. Privacy Nutrition Label mapping

"Linked to you" because everything is tied to a Supabase account. "Tracking" = No for all (no third-party advertising or data broker use found).

| Apple data type | Collected? | What in the app | Linked | Purpose |
|---|---|---|---|---|
| Contact Info: Email Address | Yes | Account email (email, Apple relay, Google) | Yes | App functionality |
| Contact Info: Name | Yes | Display name from onboarding / Apple / Google | Yes | App functionality, personalization |
| Health & Fitness: Health | Yes | Body weight, age, height, training age, injuries/notes sent in profile and prompts | Yes | App functionality |
| Health & Fitness: Fitness | Yes | Workouts, sets, reps, weights, PRs, form feedback | Yes | App functionality, personalization |
| Sensitive Info | Review | Dietary or nutrition goals, body composition targets; Apple lists "health" under Health & Fitness, so likely not needed | Yes | App functionality |
| User Content: Other User Content | Yes | Chat messages, workout notes, nutrition journal and saved foods | Yes | App functionality |
| Identifiers: User ID | Yes | Supabase user UUID | Yes | App functionality |
| Usage Data | No for now | Debug-only AI usage counters; no analytics SDK. If you add `ai_usage` server logs (see cost model), declare Product Interaction, linked, for analytics/app functionality | | |
| Diagnostics | Check | `DiagnosticsStore` is local and user-exported only (no upload found). Supabase/Google/proxy logs keep IP and request metadata. Declare Crash/Performance Data only if you adopt TestFlight/Xcode crash data off-device (Apple's own is not "collected by you") | | |
| Photos or Video / Camera | Yes (Photos or Videos) | Form-check camera frames stay on device; meal photos the user chooses to send for AI meal logging go to Google Gemini via `ai-proxy`, not stored by LightStack. Declare as Photos or Videos, not linked, app functionality | | |
| Purchases | Not yet | Add when StoreKit is added | | |
| Location, Contacts, Browsing, Search History | No | Barcode and food search queries go to Open Food Facts: if Apple counts them, declare Search History, not linked to identity (no user id is sent) | | |

Third-party AI statement for the label and policy: user content, meal descriptions, meal photos and health/fitness data are shared with Google (Gemini API, and Google Search for restaurant meals) to generate responses. Confirm the Gemini API paid-tier terms (data not used to train models) and write that into the policy; the free tier does use data for product improvement, so **use the paid tier in production**.

## 3. PrivacyInfo.xcprivacy and Required Reason APIs

Findings from grep over `Lightstack`, `Shared`, `LightstackWidgets`:

| API category | Used? | Evidence | Declare |
|---|---|---|---|
| UserDefaults (`NSPrivacyAccessedAPICategoryUserDefaults`) | **Yes, heavily** | `@AppStorage` and `UserDefaults` in about 20 files, including `App/AppEnvironment.swift`, `Core/Services/AIProvider.swift`, `Core/Utilities/OfflineQueueManager.swift`, `Core/Utilities/SessionExpiry.swift`, `Features/Today/LiveActivity/LiveActivityController.swift`, `Features/Settings/SettingsView.swift`. No app-group suite found (`suiteName`/`group.` grep is empty), so reasons: `CA92.1` (app-only data). If the widget or Live Activity extension reads defaults, add the same declaration to that target, and if an app group is later added use `1C8F.1`. |
| File timestamp (`...FileTimestamp`) | Not found in app code | grep for `creationDate`, `modificationDate`, `contentModificationDateKey`, `attributesOfItem` finds none. `OfflineQueueManager` moves corrupt files aside but does not read timestamps. | Not needed; re-check dependencies |
| Disk space (`...DiskSpace`) | Not found | No `volumeAvailableCapacity`, `systemFreeSize`, `attributesOfFileSystem` | Not needed |
| System boot time | Not found | No `systemUptime`, `mach_absolute_time` | Not needed |
| Active keyboard | Not found | | Not needed |

Also needed:

- `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []`.
- `NSPrivacyCollectedDataTypes` entries mirroring the label above (email, name, health, fitness, user content, user ID), all linked, none for tracking.
- Third-party SDKs: supabase-swift (`from: 2.0.0`) and GoogleSignIn-iOS (9.x) should ship their own manifests. After archiving, run Xcode > Product > Archive > Generate Privacy Report and confirm no missing-manifest warnings; the "from: 2.0.0" range for Supabase is unpinned, so lock the version for release.
- Project is generated by XcodeGen: add the file under `Lightstack/Resources` (or similar), run `xcodegen generate`; never edit the pbxproj by hand (per CLAUDE.md).

## 4. Pre-submission order of work

1. Privacy policy page and links (#4).
2. AI consent screen and server-side consent check (#3).
3. Delete Account plus Apple revoke (#1, #2).
4. `PrivacyInfo.xcprivacy` (#5), then App Store Connect labels (#6).
5. Disclaimers and metadata review (#7), demo account (#11), remove placeholders (#14).
6. Keep Sign in with Apple and Google parity (#8); no change needed.

Suggested App Review notes: describe the AI coach, name Google Gemini as the processor, where consent is shown, how to delete the account (Settings > Account > Delete), the demo credentials, and that camera frames are processed on device.
