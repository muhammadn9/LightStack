# UI Test Harness — Plan

Approved by owner 2026-10-04.

## Goal

Make it possible to reproduce a user-reported bug as an automated UI test on the simulator, watch it fail, fix it, and watch it pass. The tests should also catch regressions before each TestFlight upload.

## App-side test mode

Test mode is compiled only in DEBUG. All of it sits inside `#if DEBUG`; Release and TestFlight archives must contain none of it. It's switched on by the launch argument `-uiTesting`. A second argument, `-uiTestingReset`, wipes test data first.

- **Auth.** `AuthService.currentUser()` returns a fixed test user with a constant UUID. `AppEnvironment` treats the user as authenticated and onboarded.
- **Storage.** `LocalStorageService` uses a separate on-disk store, `Lightstack-UITests.sqlite`, so tests never touch real data. The store survives a relaunch, which the relaunch scenario depends on. `-uiTestingReset` deletes it.
- **Seed data**, written on reset:
  - a profile with split days Push, Pull and Legs
  - one past Push workout: 2 exercises with 2 logged sets each, dated yesterday
- **AI.** The provider chain is replaced by a fake provider that returns canned responses:
  - a valid 3-exercise plan JSON for generation
  - a short note for the progression note
  - plain text for chat
- **Network.** Supabase calls may fail in test mode. Failures go to the offline queue, which is acceptable. The UI must never block on them.
- **Session state.** It's stored under a separate key, or reset by `-uiTestingReset`, so a stale session can't leak between tests.

## Accessibility identifiers

Add stable identifiers on the controls the tests need:
- tab buttons
- workout-type chips, Generate, Repeat last, Log Manually
- Start on the confirm screen
- the set rows' weight, reps and RIR fields and their log buttons, as `setRow.<exerciseIndex>.<rowIndex>.weight` or similar
- Add Set / Add Round, Superset with next, Unlink, Finish Workout, and Discard / Cancel workout
- the History list rows, Edit, Save and Import
- the import text editor, Check and Import

Prefer identifiers to visible labels.

## UI test target

`LightstackUITests` is a `bundle.ui-testing` target in `project.yml`. Its tests run in their own scheme, `LightstackUITests`, so the unit-test scheme stays fast. A shared helper launches the app with `-uiTesting -uiTestingReset` and attaches named screenshots with `XCTAttachment` and `.keepAlways`.

**Scenarios:**
1. **Finish:** generate (using the fake AI) → start → type numbers into one row without logging → Finish. Pass if there's no crash, the post-workout screen appears, and after saving, History shows the workout with that set.
2. **Relaunch:** start a workout → type into a row → terminate the app → relaunch with `-uiTesting` and no reset. Pass if the typed numbers are still there and each exercise appears once.
3. **Supersets:** start a workout → Superset with next. Pass if both exercises are on one page with round rows. Then Unlink, and pass if they're separate pages again.
4. **Edit:** History → open the seeded workout → Edit → change a weight → Save. Pass if the detail screen shows the new weight.
5. **Import:** History → Import → paste a small valid JSON (typed, or set through the pasteboard) → Check → Import. Pass if History shows the imported workout.

**Run command:**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Lightstack.xcodeproj -scheme LightstackUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -resultBundlePath /tmp/ui.xcresult > /tmp/ui.log 2>&1
echo EXIT=$?
```

Screenshots are exported with:

```
xcrun xcresulttool export attachments --path /tmp/ui.xcresult --output-path /tmp/ui-shots
```

## Release safety

After implementation:
- build the Release configuration
- confirm that `strings` on the binary finds no `uiTesting` and no fake-provider symbols
- confirm `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for Release does not include DEBUG
