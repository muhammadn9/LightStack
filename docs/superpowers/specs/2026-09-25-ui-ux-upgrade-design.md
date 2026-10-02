# UI/UX Upgrade — Design

**Date:** 2026-09-25
**Branch:** `claude/structured-modification-json`
**Deployment target:** iOS 17.0

## Goal

Upgrade LightStack's UI in four layered passes: accessibility/typography compliance,
component modularity, motion, then a performance audit.

## Audit Findings

An audit of the 49 view files corrected three of the four original Step 1 assumptions:

| Assumption | Reality |
| --- | --- |
| Deprecated layouts / `NavigationView` | 0 occurrences. Already 16 `NavigationStack`. |
| Hardcoded hex colors in views | 0 outside `AppTheme`. Already semantic (`.label`, `.systemGroupedBackground`). |
| Dynamic Type | **0 support.** 246 fixed-pt `AppTheme.*` font calls + 17 `.system(size:)`. |
| Accessibility | **0 `accessibilityLabel`** across all 49 view files. |

Additional findings:

- `AppTheme.playfair` / `playfairItalic` / `caveat` / `plexMono` are vestigial — all four
  already return `Font.system` with varying weights. The custom fonts were stripped in an
  earlier pass. This makes them a safe single point of change.
- **`TodayView.swift` (129 lines) is dead code** — never instantiated. The live Today path is
  `TodayTabContent` in `MainTabView.swift:113`. The two have already drifted: `TodayView`
  carries a `.navigationTitle("Today")` and a `StreakView` toolbar item that the live view
  lacks.
- 0 `AnyView` in the codebase (avoids the most common SwiftUI perf mistake).
- 0 haptics of any kind.
- `MainTabView` hides the native `UITabBar` in favour of a custom top strip (`NotebookTabRow`).

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Custom tab strip | **Keep, fix accessibility** | Brand identity. Migrating to native `TabView` would discard the notebook aesthetic. |
| Haptics API | **`.sensoryFeedback`** | iOS 17+ declarative, state-driven, respects system settings, no engine lifecycle. CoreHaptics rejected as unjustified complexity for tap/selection feedback. |
| Scope | **Theme-wide + Today/Month cards** | Font fix reaches all 246 sites via `AppTheme`; deep card/motion work confined to Today and MonthPlan. FormAnalysis, Auth, Settings untouched. |

`Tab` (iOS 18) is unavailable at the iOS 17.0 deployment target.

## Step 0 — Remove Dead Code

Delete `Features/Today/Views/TodayView.swift` and run `xcodegen generate`. It is never
instantiated, and leaving it in place guarantees future work gets applied to a file that never
renders. Its only unique content — the `.navigationTitle("Today")` and `StreakView` toolbar item
— is deliberately *not* ported: the live `TodayTabContent` sets `.navigationBarHidden(true)` by
design, and streak data is already surfaced on the Profile screen via its own stat presentation
(`ProfileView:208`). Verify the build still succeeds after removal.

Note: `TodayView.swift:80` is the **only** reference to the `StreakView` component
(`Features/Profile/Views/StreakView.swift`). Deleting `TodayView` orphans it. Leave `StreakView`
in place — it is small, correct, and a plausible candidate for reuse in the polished tab row —
but do not treat it as live code.

## Step 1 — Typography & Accessibility

### 1a. Dynamic Type via AppTheme

`Font.system(size:)` does not scale with user text-size settings; semantic text styles do.
Because all four `AppTheme` font helpers already resolve to `Font.system`, their internals can
be swapped to resolve size → nearest semantic `TextStyle` while **keeping their existing
`(size:weight:)` signatures**. All 246 call sites compile unchanged and inherit Dynamic Type.

Size → `TextStyle` mapping:

| Size | TextStyle |
| --- | --- |
| ≤ 11 | `.caption2` |
| 12 | `.caption` |
| 13 | `.footnote` |
| 14 | `.subheadline` |
| 15–16 | `.callout` |
| 17 | `.body` |
| 18–20 | `.title3` |
| 21–26 | `.title2` |
| ≥ 27 | `.title` |

`plexMono` retains `design: .rounded`. The 17 direct `.system(size:)` call sites are converted
individually.

### 1b. Scaled dimensions

Fixed icon frames break when text scales. Convert to `@ScaledMetric`:
`SetNumberCircle` (18pt), `PRStamp` (31pt), `RestTimerRing` (45pt).

### 1c. Dynamic Type clamp

Grid-dense screens cannot absorb the largest accessibility sizes. Apply
`.dynamicTypeSize(...DynamicTypeSize.accessibility3)` to MonthPlan day tiles only — not globally.

### 1d. VoiceOver

- `NotebookTabRow`: `.isButton` + `.isSelected` traits, label per tab.
- Energy dots in `WorkoutSetupView:62` — currently 5 separate buttons, exposed as 5 unlabelled
  controls. Collapse to one `.accessibilityRepresentation` adjustable element.
- `InkDotRating`: same adjustable treatment.
- `PRStamp`, `SetNumberCircle`, `RestTimerRing`: labels and values.
- Icon-only buttons throughout Today/Month: `.accessibilityLabel`.

## Step 2 — Style-Driven Components

Replace the `CardStyle` / `GlowingCardStyle` `ViewModifier`s with a protocol + environment
style, mirroring SwiftUI's own `ButtonStyle` pattern:

```swift
protocol LSCardStyle {
    associatedtype Body: View
    func makeBody(configuration: Configuration) -> Body
}
```

Concrete styles: `.plain`, `.accented` (leading accent strip), `.elevated`. Read from
`@Environment(\.lsCardStyle)` so a style set on a container cascades to descendant cards. The
24 existing `.cardStyle()` call sites keep working against a `.plain` default — migration is
opt-in per site.

`StatusBadge`: `PlannedSessionView:118` contains three near-identical branches (Done / Today /
Missed) differing only in label, foreground, and background tint. Collapse to a single component
driven by a status enum.

## Step 3 — Motion & Haptics

- Card expand/collapse: `.spring(response: 0.38, dampingFraction: 0.78)`.
- Tab indicator: `matchedGeometryEffect` replacing the current per-tab `Capsule` fill.
- Haptics: `.sensoryFeedback(.impact(weight: .light), trigger:)` on card tap,
  `.selection` on chip and tab change, `.success` on set logged and PR earned.
- **All spring animations gated behind `@Environment(\.accessibilityReduceMotion)`**, falling
  back to a short `.easeOut` or no animation.

## Step 4 — Performance Audit

Read-only pass over newly written code, plus these pre-identified targets:

- `MainTabView` holds all 5 tabs eagerly in the hierarchy via `TabView(.page)`.
- `.id(viewModel.phase)` forces full subtree teardown on every phase change.
- Only 3 `LazyVStack` app-wide — check History and MonthPlan list bodies.
- `InkFillBar` uses `GeometryReader`. One call site (`ProfileView:195`) but it sits **inside a
  `ForEach` over muscle groups**, so it instantiates once per group rather than once overall.
  Replace with a `GeometryReader`-free fill (overlay + `.containerRelativeFrame` or a
  proportional `HStack` spacer).
- `@EnvironmentObject` invalidation breadth on `AppEnvironment`.

## Sequencing

Steps 1 and 2 both touch `AppTheme.swift` and overlapping card call sites, so they run
**sequentially**. Step 3 begins after Step 2 lands. Step 4 is a read-only audit over the result.

Per `CLAUDE.md`: subagents implement but do not commit; the orchestrator builds, verifies
`EXIT=0`, and commits centrally.

## Out of Scope

- Migrating to a native bottom `TabView`.
- CoreHaptics custom patterns.
- FormAnalysis, Auth, and Settings surfaces.
- Reinstating real custom fonts (Playfair/Caveat/PlexMono).

## Open Item

`CLAUDE.md` states all work goes to `claude/v3-tests-and-ui`; the active branch is
`claude/structured-modification-json`. Proceeding on the active branch.
