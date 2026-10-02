# SwiftUI Performance Audit — UI/UX Upgrade Branch

**Branch:** `claude/structured-modification-json`  
**Scope:** Commits `a51e0a6` → `aec7c8d` (Dynamic Type, CardStyle, Motion, StatusBadge, matchedGeometryEffect, InkFillBar, a11y additions)  
**Date:** 2026-09-25

---

## Executive Summary

Three issues warrant attention before this branch ships, in priority order. **First**, the workout timer fires every second and, because `ActiveWorkoutView` observes the same `ActiveWorkoutViewModel` that owns the timer, the entire workout screen — including all set rows, the scroll view, and a volume-loop across every logged set — re-renders on every tick. This is the most likely source of dropped frames during a live workout. **Second**, `currentWeekSessions` in `MonthPlanView` is a computed property called from `body` that allocates `Calendar` components, creates two `Date` objects, and runs a full `.filter` + `.sorted` over the sessions array on every render pass; combined with the `calendarWeeks` property that does a similar array-building job, `MonthPlanView`'s body does a non-trivial amount of heap work every time any observed property changes. **Third**, the inline `Binding(get:set:)` for alert presentation in both `WorkoutSessionSheet` and `TodayTabContent` is re-created on every render of those views, which — given the timer invalidation described above — means it is re-allocated at 1 Hz during an active workout.

---

## Finding 1 — Timer ticks re-render the entire active-workout screen

**File:** `Lightstack/Features/Today/Views/ActiveWorkoutView.swift`  
**Severity:** High

### What happens

`ActiveWorkoutViewModel.startTimer` fires a `Timer` every second and increments `elapsedSeconds`, which is `@Published`. `ActiveWorkoutView` holds `@ObservedObject var viewModel: ActiveWorkoutViewModel`. Every time `elapsedSeconds` changes, SwiftUI calls `body` on `ActiveWorkoutView`.

That `body` includes:

1. `timerBar` — passes `viewModel.runningVolume(exercises: todayViewModel.exercises)` as a computed argument. `runningVolume` loops over every exercise and every logged set on each call (line 131, `ActiveWorkoutView.swift`; function body at lines 44–51, `ActiveWorkoutViewModel.swift`).
2. `currentExerciseView` — a large `ScrollView` containing the logged-set `ForEach`, the pending-set `ForEach`, column headers, rest-timer banner, and navigation buttons. All of this is re-evaluated every second.
3. The `@ObservedObject var todayViewModel: TodayViewModel` is also read inside `body`, so any change to `todayViewModel` additionally re-renders the full view.

The rest timer (`restTimerClock`) calls `objectWillChange.send()` directly (line 385, `ActiveWorkoutViewModel.swift`) rather than mutating a `@Published` property, which means it produces the same one-per-second full re-render even while a rest timer is active alongside the workout timer — potentially two full re-renders per second.

### Why it costs frames

At 120 Hz ProMotion the render budget is ~8 ms. A full re-render of `ActiveWorkoutView` with e.g. five exercises and three logged sets each involves resolving `runningVolume` (5 × 3 iterations), diffing every row view, and re-laying out a ScrollView. This is very unlikely to drop frames on its own, but it does burn unnecessary CPU time and makes the view fragile — any future addition to `body` (e.g. a gradient or a live animation) is now charged every second.

### Fix

Split `ActiveWorkoutTimerBar` so it owns its own `@ObservedObject` reference to the view model, or — better — extract the `elapsedSeconds` and `isPaused` properties into a separate `TimerState` observable. `ActiveWorkoutView.body` should not re-run on every tick; only the timer bar needs to. The `runningVolume` computation should be memoised: cache the value in a `@Published` property updated only when `loggedSets` changes, not recomputed inline in `body`.

For `objectWillChange.send()` in the rest-timer clock: replace it with a `@Published var restTimerTick: Int = 0` incremented each second, and observe that from a small `RestTimerBannerView` instead of the full screen.

---

## Finding 2 — `calendarWeeks` and `currentWeekSessions` do real work in `body`

**File:** `Lightstack/Features/MonthPlan/Views/MonthPlanView.swift`, lines 253–285  
**Severity:** Medium

### What happens

Both `calendarWeeks` and `currentWeekSessions` are plain computed properties with no caching. They are read directly from `body` (via `calendarGrid` and `thisWeekSection` at lines 233 and 247).

`calendarWeeks` (lines 253–271):
- Calls `Calendar.current.component(.weekday, from:)` — locale-aware, heap-allocating
- Builds two intermediate `[Date?]` arrays (`allSlots` and the final chunked result)
- Uses `stride` to produce an `[[Date?]]` — a new allocation on each render

`currentWeekSessions` (lines 274–285):
- Calls `Calendar.current.dateComponents(...)` and `Calendar.date(from:)` twice — two more `Calendar` operations
- Runs `.filter` over all sessions, comparing two `Date` values per session
- Runs `.sorted` — O(n log n) over the week's sessions

`MonthPlanView` observes `MonthPlanViewModel` via `@ObservedObject`. Any `@Published` change on that view model — including ones irrelevant to the calendar layout, such as a network loading flag — triggers a re-render and re-runs both computations.

### Why it costs frames

Individual `Calendar` operations are fast, but they are not free (locale lookup, bridging). More importantly, this pattern means the calendar grid is recomputed on every `objectWillChange` event from the view model, even during streaming AI plan generation where updates fire frequently. It is also a correctness time-bomb: `currentWeekSessions` calls `Date()` inline, so it can return different results for the same render pass if it straddles midnight.

### Fix

Move both computations into `MonthPlanViewModel` as `@Published` properties, updated lazily in `setUserId` / `loadPlan` / `selectPlan`. Pass the pre-computed arrays as plain `let` values to `MonthCalendarGridView` and `ThisWeekSectionView`. This eliminates all Calendar work from the view layer entirely.

---

## Finding 3 — Inline `Binding(get:set:)` for alert presentation re-allocates every render

**Files:**
- `Lightstack/Features/Today/Views/WorkoutSessionSheet.swift`, line 108
- `Lightstack/App/MainTabView.swift`, line 199

**Severity:** Low (correctness concern more than a frame-drop risk)

### What happens

Both files construct a `Binding<Bool>` inline at the call site of `.alert(isPresented:)`:

```swift
.alert("Error", isPresented: .init(
    get: { todayViewModel.errorMessage != nil },
    set: { if !$0 { todayViewModel.errorMessage = nil } }
))
```

Because this `Binding` is created inside `body`, SwiftUI discards and re-creates it on every render pass. During an active workout (Finding 1), `WorkoutSessionSheet.body` re-renders every second, meaning the binding closure captures `todayViewModel` afresh every second.

### Why it matters

The construct is not a feedback loop on its own — the `set` closure only fires when the user dismisses the alert. However, because it creates a fresh `Binding` identity each render, SwiftUI cannot tell that the alert's "is presented" state is stable. In practice this is safe with the current code, but it is fragile: any future use of `withAnimation` around `errorMessage` changes could cause the alert to flash or re-present.

### Fix

Add a dedicated `@Published var showError: Bool = false` on each view model (or derive it with a simple computed property), and pass `$viewModel.showError` directly. This is the standard pattern for error alerts and eliminates the inline binding entirely.

---

## Verified Healthy

The following items were specifically checked and found to have no meaningful performance issue:

**`AnyView` in `LSCardStyle.makeBody` (Audit Item 1):**  
There are exactly six `.lsCard()` call sites outside of `CardStyle.swift` itself:
- `PlannedSessionView.swift` line 79 — one card per sheet navigation
- `MonthPlanView.swift` lines 81, 203 — the entire calendar section and an empty-state card, each appearing once
- `ConfirmWorkoutView.swift` lines 48, 69 — two cards on a static confirmation screen

None of these are inside a `ForEach` over a large or mutable list. The `AnyView` erasure prevents SwiftUI from diffing the card's internal tree, but since each call site renders a single, mostly-static card and not a recycled list of cells, there is no structural diffing to lose. The AnyView cost here is negligible and does not warrant refactoring.

**Unstable `ForEach` identity (Audit Item 2):**  
`ForEach(tabs.indices, id: \.self)` in `NotebookTabRow` iterates over `let tabs = ["Today", "Month", "History", "Profile", "Settings"]`, a compile-time constant. The array never mutates, so identity is perfectly stable. `ForEach(Array(weeks.enumerated()), id: \.offset)` in `MonthCalendarGridView` is over a pre-computed `[[Date?]]`; the offset is a position in the calendar grid, which is also stable relative to the plan data. `ForEach(["M","T","W","T","F","S","S"], id: \.self)` uses `\.self` on strings that have repeated values ("T" appears twice, "S" appears twice), which means SwiftUI cannot distinguish those cells. However, since these are purely decorative static day-header labels that never animate or change state, this is a non-issue in practice. No findings.

**`@ScaledMetric` cost (Audit Item 6):**  
`SetNumberCircle`, `PRStamp`, `RestTimerRing`, and `MonthDayTileView` each declare one `@ScaledMetric` property. `SetNumberCircle` is rendered once per set per exercise — typically 3–5 instances on screen at once. A `@ScaledMetric` read is a single environment value lookup; it is not re-evaluated during scrolling or animation, only on trait-collection changes (Dynamic Type size changes). This is negligible.

**`matchedGeometryEffect` in `NotebookTabRow` (Audit Item 7):**  
The effect is applied to a single `Capsule` view keyed `"tabIndicator"` inside a five-element `ForEach`. Only one tab is selected at a time, so only one source and one destination exist in the namespace simultaneously. The animation is bounded by `AppMotion.tabSwitch` (spring, response 0.32 s). This is the canonical usage pattern for a sliding tab indicator and carries no meaningful layout-pass cost. No findings.

**Animation modifiers applied too broadly (Audit Item 8):**  
All `.animation(_:value:)` calls in the changed files use the `value:` parameter — no context-free `.animation(_:)` calls were found anywhere in the Lightstack source tree. `ExpandableCard` applies `.animation` on `value: isExpanded`, scoped to the card itself. No broad container animations were found. No findings.

**DateFormatter construction in `body` (Audit Item 5, partial):**  
All `DateFormatter` instances in the app are declared as `static let` properties on `DateFormatter` (see `DateFormatter+Extensions.swift`). Call sites in `body` use these singletons (e.g. `DateFormatter.monthName.string(from:)`). No `DateFormatter()` is constructed inline in any view's `body`. The two `let` bindings in `MonthPlanView.monthHeader` at lines 147–148 call `.string(from:)` on existing static formatters, which is a string allocation but not a formatter construction. This is fine.
