# UI/UX Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring LightStack's UI to iOS accessibility and HIG compliance, rebuild its cards as style-driven components, add spring motion and haptics, then audit performance.

**Architecture:** All typography flows through four helpers in `AppTheme.swift`, so Dynamic Type is introduced there once and inherited by 246 call sites. Cards move from `ViewModifier` to an environment-driven style protocol mirroring SwiftUI's `ButtonStyle`. Motion and haptics are added last so they sit on stable components.

**Tech Stack:** Swift 5, SwiftUI, iOS 17.0 deployment target, XCTest, XcodeGen.

---

## Conventions For Every Task

**Build command** (from `CLAUDE.md`, run after every change):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Lightstack.xcodeproj -scheme Lightstack -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2' -quiet > /tmp/lightstack-build.log 2>&1; echo EXIT=$?
grep -E "error:|BUILD FAILED" /tmp/lightstack-build.log | head -30
```

Never pipe `xcodebuild` into `tail` before reading `$?` — `$?` reports `tail`'s status, so a failed
build looks like it passed.

**Test command:**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Lightstack.xcodeproj -scheme Lightstack -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2' -quiet > /tmp/lightstack-test.log 2>&1; echo EXIT=$?
grep -E "error:|failed|TEST FAILED" /tmp/lightstack-test.log | head -30
```

**Execution order — do not follow the numbering blindly:**

Task 7 (Motion constants) defines `AppMotion`, which Tasks 4 and 9 reference. Task 6 defines
`.lsCard()`, which Tasks 9 and 11 reference. Execute in this order:

```
0 → 1 → 2 → 3 → 6 → 7 → 4 → 5 → 5b → 8 → 9 → 10 → 11 → 12
```

Tasks 1, 2, 3, 5b, 8 and 10 are independent of each other and could be parallelised, but 1 and 2
both edit shared theme files, so run those two sequentially.

**Rules:**
- No force-unwraps. Use `guard`/`if let`.
- Swift + SwiftUI only.
- After adding or removing any file, run `xcodegen generate`.
- **Subagents must not commit or push.** The orchestrator commits centrally after verifying `EXIT=0`.

---

## File Structure

| File | Responsibility | Action |
| --- | --- | --- |
| `Lightstack/Core/Theme/AppTheme.swift` | Colors, dimensions, font helpers | Modify — Dynamic Type |
| `Lightstack/Core/Theme/CardStyle.swift` | Card style protocol + concrete styles | **Create** |
| `Lightstack/Core/Theme/StatusBadge.swift` | Status badge component + style | **Create** |
| `Lightstack/Core/Theme/Motion.swift` | Shared springs, reduce-motion helper | **Create** |
| `Lightstack/Core/Theme/NotebookComponents.swift` | Small shared widgets | Modify — ScaledMetric, a11y |
| `Lightstack/Features/Today/Views/TodayView.swift` | Dead duplicate of `TodayTabContent` | **Delete** |
| `Lightstack/App/MainTabView.swift` | Tab row + live Today path | Modify — a11y, matchedGeometry |
| `Lightstack/Features/Today/Views/WorkoutSetupView.swift` | Pre-workout form | Modify — a11y on energy dots |
| `Lightstack/Features/MonthPlan/Views/MonthDayTileView.swift` | Calendar day tile | Modify — clamp, a11y |
| `Lightstack/Features/MonthPlan/Views/PlannedSessionView.swift` | Session detail | Modify — use `StatusBadge` |
| `Lightstack/Features/Profile/Views/ProfileView.swift` | Stats | Modify — `InkFillBar` call site |
| `LightstackTests/AppThemeTypographyTests.swift` | Font mapping unit tests | **Create** |
| `LightstackTests/StatusBadgeTests.swift` | Badge status mapping tests | **Create** |

---

## Task 0: Delete Dead `TodayView.swift`

`TodayView` is never instantiated. The live Today path is `TodayTabContent` in
`MainTabView.swift:113`. Removing it first prevents every later task from being applied to a file
that never renders.

**Files:**
- Delete: `Lightstack/Features/Today/Views/TodayView.swift`

- [ ] **Step 1: Confirm it is genuinely unreferenced**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack/Lightstack
grep -rn "TodayView(" --include="*.swift" . | grep -v "struct TodayView"
```

Expected: **no output.** If there is any output, STOP and report — the premise is wrong.

- [ ] **Step 2: Delete the file and regenerate the project**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack
rm Lightstack/Features/Today/Views/TodayView.swift
xcodegen generate
```

- [ ] **Step 3: Build to prove nothing referenced it**

Run the build command. Expected: `EXIT=0`.

If the build fails with "cannot find 'TodayView'", something did reference it — restore with
`git checkout -- Lightstack/Features/Today/Views/TodayView.swift` and report.

> **Note:** `TodayView.swift:80` was the only user of the `StreakView` component. After this
> deletion `StreakView` is unreferenced. **Leave `StreakView.swift` in place** — it is small,
> correct, and a candidate for reuse in Task 5. Swift does not warn on unused types, so the build
> stays clean.

---

## Task 1: Dynamic Type In `AppTheme`

`Font.system(size:)` ignores the user's text-size setting. Semantic text styles honour it. All
four helpers already resolve to `Font.system`, so their internals can change while their
`(size:weight:)` signatures stay identical — all 246 call sites compile untouched.

**Files:**
- Modify: `Lightstack/Core/Theme/AppTheme.swift:73-98`
- Create: `LightstackTests/AppThemeTypographyTests.swift`

- [ ] **Step 1: Write the failing test**

Create `LightstackTests/AppThemeTypographyTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Lightstack

/// Tests the size -> semantic TextStyle mapping that gives AppTheme's font
/// helpers Dynamic Type support.
final class AppThemeTypographyTests: XCTestCase {

    func testSmallSizesMapToCaption2() {
        XCTAssertEqual(AppTheme.textStyle(for: 7),  .caption2)
        XCTAssertEqual(AppTheme.textStyle(for: 8),  .caption2)
        XCTAssertEqual(AppTheme.textStyle(for: 9),  .caption2)
        XCTAssertEqual(AppTheme.textStyle(for: 11), .caption2)
    }

    func testMidSizesMapToExpectedStyles() {
        XCTAssertEqual(AppTheme.textStyle(for: 12), .caption)
        XCTAssertEqual(AppTheme.textStyle(for: 13), .footnote)
        XCTAssertEqual(AppTheme.textStyle(for: 14), .subheadline)
        XCTAssertEqual(AppTheme.textStyle(for: 15), .callout)
        XCTAssertEqual(AppTheme.textStyle(for: 16), .callout)
        XCTAssertEqual(AppTheme.textStyle(for: 17), .body)
    }

    func testLargeSizesMapToTitleStyles() {
        XCTAssertEqual(AppTheme.textStyle(for: 18), .title3)
        XCTAssertEqual(AppTheme.textStyle(for: 20), .title3)
        XCTAssertEqual(AppTheme.textStyle(for: 21), .title2)
        XCTAssertEqual(AppTheme.textStyle(for: 26), .title2)
        XCTAssertEqual(AppTheme.textStyle(for: 27), .title)
        XCTAssertEqual(AppTheme.textStyle(for: 40), .title)
    }

    func testMappingIsMonotonic() {
        // A larger input size must never map to a smaller text style.
        let order: [Font.TextStyle] = [
            .caption2, .caption, .footnote, .subheadline,
            .callout, .body, .title3, .title2, .title
        ]
        var lastIndex = 0
        for size in stride(from: CGFloat(6), through: 40, by: 1) {
            guard let index = order.firstIndex(of: AppTheme.textStyle(for: size)) else {
                return XCTFail("size \(size) mapped outside the expected ladder")
            }
            XCTAssertGreaterThanOrEqual(index, lastIndex, "size \(size) went backwards")
            lastIndex = index
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack && xcodegen generate
```

Then run the test command. Expected: **FAIL** to compile with
`type 'AppTheme' has no member 'textStyle'`.

- [ ] **Step 3: Add the mapping and rewrite the helpers**

In `Lightstack/Core/Theme/AppTheme.swift`, replace the entire `// MARK: - Custom Fonts` section
(lines 73-98, the four functions `playfair`, `playfairItalic`, `caveat`, `plexMono`) with:

```swift
    // MARK: - Dynamic Type

    /// Maps a legacy point size to the nearest semantic text style.
    ///
    /// The font helpers below keep their `(size:weight:)` signatures for source
    /// compatibility, but resolve through this table so every call site scales with
    /// the user's text-size setting.
    ///
    /// Sizes below 11pt all resolve to `.caption2`. That is deliberate: 11pt is
    /// Apple's minimum legible size, so the handful of 7-9pt labels in the app
    /// render slightly larger than before. This is the intended correction.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5:  return .caption2
        case ..<12.5:  return .caption
        case ..<13.5:  return .footnote
        case ..<14.5:  return .subheadline
        case ..<16.5:  return .callout
        case ..<17.5:  return .body
        case ..<20.5:  return .title3
        case ..<26.5:  return .title2
        default:       return .title
        }
    }

    // MARK: - Font Helpers

    /// Page headers, section labels, buttons.
    static func playfair(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let resolved: Font.Weight
        switch weight {
        case .bold, .semibold, .heavy, .black: resolved = .bold
        default:                               resolved = .semibold
        }
        return .system(textStyle(for: size), design: .default, weight: resolved)
    }

    /// Elegant headings, wax-seal labels (no italic — matches previous behaviour).
    static func playfairItalic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        playfair(size, weight: weight)
    }

    /// Handwritten subtitles, labels, notes, tab text.
    static func caveat(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size),
                design: .default,
                weight: weight == .bold ? .medium : .regular)
    }

    /// Data display, stats, calendar numbers — rounded design.
    static func plexMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size), design: .rounded, weight: weight)
    }
```

Leave the `// MARK: - UIFont versions` block below it untouched — UIKit appearance APIs need
concrete sizes.

- [ ] **Step 4: Run the test to verify it passes**

Run the test command. Expected: `EXIT=0`, all four tests pass.

- [ ] **Step 5: Build the app**

Run the build command. Expected: `EXIT=0`. No call site should need editing — if any fails to
compile, the signature was changed by mistake; revert and keep the parameter list identical.

- [ ] **Step 6: Convert the 17 direct fixed-size call sites**

Find them:

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack/Lightstack
grep -rn "\.font(\.system(size:" --include="*.swift" .
```

For each, replace the fixed size with the semantic equivalent, preserving weight and design.
Example transformations:

```swift
// before
.font(.system(size: 28, weight: .light))
// after
.font(.system(.title, design: .default, weight: .light))

// before
.font(.system(size: 13, weight: .semibold))
// after
.font(.system(.footnote, design: .default, weight: .semibold))
```

Use `AppTheme.textStyle(for:)`'s table to pick the style for each size. **Exception:** leave any
`.font(.system(size:))` that sizes an SF Symbol inside a fixed-size frame — those are handled in
Task 2.

- [ ] **Step 7: Build**

Run the build command. Expected: `EXIT=0`.

---

## Task 2: Scale Fixed Icon Dimensions

Three components hardcode frames that will clip once their text scales.

**Files:**
- Modify: `Lightstack/Core/Theme/NotebookComponents.swift`

- [ ] **Step 1: Make `SetNumberCircle` scale**

Replace the `SetNumberCircle` struct (`NotebookComponents.swift:66-83`) with:

```swift
struct SetNumberCircle: View {
    let number: Int
    let isLogged: Bool

    @ScaledMetric(relativeTo: .caption2) private var diameter: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .fill(isLogged ? AppTheme.accent : Color.clear)
            Circle()
                .stroke(isLogged ? AppTheme.accent : AppTheme.bindingHole, lineWidth: 1.5)
            Text("\(number)")
                .font(AppTheme.plexMono(8, weight: .bold))
                .foregroundStyle(isLogged ? Color.white : Color.secondary)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set \(number)")
        .accessibilityValue(isLogged ? "Logged" : "Not logged")
    }
}
```

- [ ] **Step 2: Make `PRStamp` scale**

Replace `PRStamp` (`NotebookComponents.swift:88-101`) with:

```swift
struct PRStamp: View {
    @ScaledMetric(relativeTo: .caption2) private var diameter: CGFloat = 31

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.prStamp, lineWidth: 2)
            Text("PR")
                .font(AppTheme.playfairItalic(8, weight: .bold))
                .foregroundStyle(AppTheme.prStamp)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-12))
        .opacity(0.9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Personal record")
    }
}
```

- [ ] **Step 3: Make `RestTimerRing` scale**

Replace `RestTimerRing` (`NotebookComponents.swift:106-124`) with:

```swift
struct RestTimerRing: View {
    let progress: Double // 0.0 to 1.0

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 45

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.timerTrack, lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0), value: progress)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest timer")
        .accessibilityValue("\(Int(progress * 100)) percent remaining")
    }
}
```

- [ ] **Step 4: Build**

Run the build command. Expected: `EXIT=0`.

---

## Task 3: Clamp Dynamic Type On Calendar Tiles

`MonthDayTileView` packs two lines of text into a fixed 44pt height inside a 7-column grid. It
cannot absorb the largest accessibility sizes. Clamp this view only — never globally.

**Files:**
- Modify: `Lightstack/Features/MonthPlan/Views/MonthDayTileView.swift:19-59`

- [ ] **Step 1: Add the clamp, a flexible height, and an accessibility label**

In `MonthDayTileView.body`, change `.frame(height: 44)` to a scaled minimum height and add the
clamp plus a label. The `body` becomes:

```swift
    @ScaledMetric(relativeTo: .caption2) private var tileHeight: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(dayNumber)")
                    .font(AppTheme.plexMono(9, weight: .bold))
                    .foregroundStyle(textColor)

                if let session = session {
                    if session.isRestDay {
                        Text("R")
                            .font(AppTheme.caveat(7))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    } else if session.completed {
                        Circle()
                            .fill(AppTheme.success)
                            .frame(width: 5, height: 5)
                    } else if state == .today {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 4, height: 4)
                    } else {
                        Text(shortType(session.workoutType))
                            .font(AppTheme.caveat(7))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: tileHeight)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(borderColor, lineWidth: state == .today ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }
```

- [ ] **Step 2: Add the label helper**

Add to the `// MARK: - Computed` section of `MonthDayTileView`:

```swift
    private var accessibilityDescription: String {
        let day = DateFormatter.shortDate.string(from: date)
        switch state {
        case .empty:     return day
        case .rest:      return "\(day), rest day"
        case .today:     return "\(day), today, \(session?.workoutType ?? "planned")"
        case .completed: return "\(day), completed, \(session?.workoutType ?? "")"
        case .missed:    return "\(day), missed, \(session?.workoutType ?? "")"
        case .planned:   return "\(day), planned, \(session?.workoutType ?? "")"
        }
    }
```

- [ ] **Step 3: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 4: Visually verify the month grid**

Launch the app in the simulator, go to the Month tab, and confirm the grid still lays out in 7
columns with no clipped text. Then in the simulator set Settings → Accessibility → Display & Text
Size → Larger Text to a large value and confirm tiles grow but do not overflow.

---

## Task 4: VoiceOver For The Tab Row

`NotebookTabRow` renders five `Button`s whose selected state is conveyed only by colour. VoiceOver
users get no indication of which tab is active, and colour alone also fails contrast guidance.

**Files:**
- Modify: `Lightstack/App/MainTabView.swift:78-108`

- [ ] **Step 1: Add traits and a matched-geometry indicator**

Replace the `NotebookTabRow` struct with:

```swift
struct NotebookTabRow: View {
    @Binding var selectedTab: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var indicator
    private let tabs = ["Today", "Month", "History", "Profile", "Settings"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button {
                        withAnimation(reduceMotion ? nil : AppMotion.tabSwitch) {
                            selectedTab = i
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text(tabs[i])
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(i == selectedTab ? AppTheme.accent : Color.secondary)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)

                            ZStack {
                                Capsule()
                                    .fill(Color.clear)
                                    .frame(height: 3)
                                if i == selectedTab {
                                    Capsule()
                                        .fill(AppTheme.accent)
                                        .frame(height: 3)
                                        .matchedGeometryEffect(id: "tabIndicator", in: indicator)
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tabs[i])
                    .accessibilityHint("Shows the \(tabs[i]) screen")
                    .accessibilityAddTraits(
                        i == selectedTab ? [.isButton, .isSelected] : .isButton
                    )
                }
            }
            InkDivider()
        }
        .accessibilityElement(children: .contain)
        .background(.bar)
    }
}
```

This depends on `AppMotion.tabSwitch` from Task 7. **Do Task 7 before this task**, or temporarily
inline `.spring(response: 0.32, dampingFraction: 0.82)`.

- [ ] **Step 2: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 3: Verify with VoiceOver**

In the simulator, enable VoiceOver (Settings → Accessibility → VoiceOver). Swipe through the tab
row. Expected: each tab announces its name, and the active one announces "selected".

---

## Task 5: VoiceOver For The Energy Rating Controls

Two places render a rating as N separate tappable circles. VoiceOver sees N unlabelled buttons
instead of one value. Both become a single adjustable element.

**Files:**
- Modify: `Lightstack/Features/Today/Views/WorkoutSetupView.swift:58-78`
- Modify: `Lightstack/Core/Theme/AppTheme.swift` (the `InkDotRating` struct)

- [ ] **Step 1: Fix the energy level block in `WorkoutSetupView`**

Replace the `// Energy Level (5-dot scale)` `VStack` with:

```swift
                // Energy Level (5-dot scale)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Energy Level")
                        .notebookSectionHeader()
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { i in
                            Button(action: { viewModel.energyLevel = i * 2 }) {
                                Circle()
                                    .fill(i * 2 <= viewModel.energyLevel ? AppTheme.accent : Color.clear)
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(AppTheme.accent.opacity(0.6), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                        let displayDots = min(5, max(1, (viewModel.energyLevel + 1) / 2))
                        Text("\(displayDots) / 5")
                            .font(AppTheme.caveat(13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.leading, 4)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Energy level")
                    .accessibilityValue("\(min(5, max(1, (viewModel.energyLevel + 1) / 2))) out of 5")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            if viewModel.energyLevel < 10 { viewModel.energyLevel += 2 }
                        case .decrement:
                            if viewModel.energyLevel > 2 { viewModel.energyLevel -= 2 }
                        @unknown default:
                            break
                        }
                    }
                }
```

- [ ] **Step 2: Fix `InkDotRating` in `AppTheme.swift`**

Replace the `InkDotRating` struct with:

```swift
struct InkDotRating: View {
    let value: Int
    let max: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...max, id: \.self) { i in
                Button(action: { onChange(i) }) {
                    Circle()
                        .fill(i <= value ? AppTheme.accent : Color.clear)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(AppTheme.accent.opacity(0.6), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(value) out of \(max)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < max { onChange(value + 1) }
            case .decrement: if value > 1   { onChange(value - 1) }
            @unknown default: break
            }
        }
    }
}
```

Note `max` is both a property name and shadows `Swift.max` inside this type — that is why the
`WorkoutSetupView` code above spells out `min(5, max(1, ...))` but this type does not call `max()`.
Do not introduce a call to `Swift.max` inside `InkDotRating` without qualifying it.

- [ ] **Step 3: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 4: Verify**

With VoiceOver on, focus the energy control. Expected: one element announcing "Energy level, 3 out
of 5, adjustable". Swipe up/down changes the value.

---

## Task 5b: VoiceOver For Icon-Only Buttons

A button whose label is only an SF Symbol announces as its raw symbol name ("plus.circle.fill") or
as nothing at all. Every such button in Today and MonthPlan needs an explicit label.

**Files:**
- Modify: icon-only button sites in `Lightstack/Features/Today/Views/` and
  `Lightstack/Features/MonthPlan/Views/`

- [ ] **Step 1: Find the candidates**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack/Lightstack
grep -rn -B2 -A2 "Image(systemName:" Features/Today/Views Features/MonthPlan/Views \
  | grep -A4 "Button" | grep -v accessibilityLabel
```

Review each hit by opening the file. A button needs a label only when it has **no visible `Text`
alongside the symbol**. Buttons like `HStack { Image(systemName: "play.fill"); Text("Start This
Workout") }` already read correctly — skip those.

- [ ] **Step 2: Add a label to each icon-only button**

Pattern:

```swift
// before
Button(action: addSet) {
    Image(systemName: "plus.circle.fill")
}

// after
Button(action: addSet) {
    Image(systemName: "plus.circle.fill")
}
.accessibilityLabel("Add set")
```

Name the *action*, not the icon: "Add set", not "Plus circle". Where the button is destructive,
also add `.accessibilityAddTraits(.isButton)` and a hint describing the consequence, e.g.
`.accessibilityHint("Removes this exercise from the workout")`.

The stepper buttons in `WorkoutSetupView:94` and `:107` render `Text("−")` and `Text("+")`, which
VoiceOver reads as "minus" and "plus" with no context. Label them explicitly:

```swift
.accessibilityLabel("Decrease time")   // on the − button
.accessibilityLabel("Increase time")   // on the + button
```

- [ ] **Step 3: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 4: Verify with VoiceOver**

Enable VoiceOver and swipe through the Today setup screen and an active workout. Every control must
announce a human-readable name. No control should announce a symbol name.

---

## Task 6: Card Style Protocol

`CardStyle` and `GlowingCardStyle` are `ViewModifier`s, so a card's appearance is chosen by which
method you call. Replacing them with an environment-driven protocol lets a container set the style
for its descendants, mirroring how `ButtonStyle` works.

**Files:**
- Create: `Lightstack/Core/Theme/CardStyle.swift`
- Modify: `Lightstack/Core/Theme/AppTheme.swift` (remove old modifiers)

- [ ] **Step 1: Create the style protocol and concrete styles**

Create `Lightstack/Core/Theme/CardStyle.swift`:

```swift
import SwiftUI

// MARK: - Protocol

/// A card's visual treatment, resolved from the environment.
///
/// Mirrors SwiftUI's own `ButtonStyle` pattern: apply `.lsCardStyle(_:)` to any
/// ancestor and every `.lsCard()` beneath it adopts that treatment.
protocol LSCardStyle {
    /// Wraps the card's content in this style's chrome.
    func makeBody(content: AnyView) -> AnyView
}

// MARK: - Concrete Styles

/// Translucent material card with a hairline border.
struct PlainCardStyle: LSCardStyle {
    func makeBody(content: AnyView) -> AnyView {
        AnyView(
            content
                .padding(AppTheme.cardPadding)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
    }
}

/// Material card with a leading accent strip.
struct AccentedCardStyle: LSCardStyle {
    func makeBody(content: AnyView) -> AnyView {
        AnyView(
            content
                .padding(AppTheme.cardPadding)
                .background(.regularMaterial, in: shape)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.accent.opacity(0.8))
                        .frame(width: 3)
                        .clipShape(shape)
                }
                .overlay(shape.strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
    }
}

/// Material card lifted with a soft shadow.
struct ElevatedCardStyle: LSCardStyle {
    func makeBody(content: AnyView) -> AnyView {
        AnyView(
            content
                .padding(AppTheme.cardPadding)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
    }
}

// MARK: - Environment

private struct LSCardStyleKey: EnvironmentKey {
    static let defaultValue: any LSCardStyle = PlainCardStyle()
}

extension EnvironmentValues {
    var lsCardStyle: any LSCardStyle {
        get { self[LSCardStyleKey.self] }
        set { self[LSCardStyleKey.self] = newValue }
    }
}

// MARK: - View API

private struct LSCardBody: ViewModifier {
    @Environment(\.lsCardStyle) private var style

    func body(content: Content) -> some View {
        style.makeBody(content: AnyView(content))
    }
}

extension View {
    /// Applies the card treatment currently set in the environment.
    func lsCard() -> some View {
        modifier(LSCardBody())
    }

    /// Sets the card treatment for this view and its descendants.
    func lsCardStyle(_ style: any LSCardStyle) -> some View {
        environment(\.lsCardStyle, style)
    }
}
```

> **Why `AnyView` here:** the protocol needs a single concrete return type to be usable as an
> existential in the environment. This is the one place the codebase uses it, and it is bounded to
> card chrome — not view content. Task 12 will confirm this does not regress scroll performance.

- [ ] **Step 2: Keep the old API working as a shim**

In `AppTheme.swift`, replace the bodies of the two existing extension methods so they delegate to
the new styles. Change:

```swift
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func glowingCard() -> some View {
        modifier(GlowingCardStyle())
    }
```

to:

```swift
    /// Deprecated shim — prefer `.lsCard()` with `.lsCardStyle(_:)`.
    func cardStyle() -> some View {
        lsCardStyle(PlainCardStyle()).lsCard()
    }

    /// Deprecated shim — prefer `.lsCard()` with `.lsCardStyle(AccentedCardStyle())`.
    func glowingCard() -> some View {
        lsCardStyle(AccentedCardStyle()).lsCard()
    }
```

Then delete the now-unused `CardStyle` and `GlowingCardStyle` structs from `AppTheme.swift`.

All 24 existing call sites keep working unchanged.

- [ ] **Step 3: Regenerate and build**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack && xcodegen generate
```

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 4: Visually verify no card regressed**

Launch the app. Check Today (confirmation screen), Month (planned session detail), History
(workout detail), and Profile. Cards should look identical to before this task.

---

## Task 7: Shared Motion Constants

Centralise springs so every animation is consistent and reduce-motion is handled in one place.

**Files:**
- Create: `Lightstack/Core/Theme/Motion.swift`

- [ ] **Step 1: Create the motion file**

Create `Lightstack/Core/Theme/Motion.swift`:

```swift
import SwiftUI

/// Shared animation curves. Physics-based springs rather than fixed-duration
/// easing, so interrupted gestures retarget smoothly instead of snapping.
enum AppMotion {

    /// Card expand / collapse. Settles quickly with a trace of overshoot.
    static let cardExpand = Animation.spring(response: 0.38, dampingFraction: 0.78)

    /// Tab indicator slide. Slightly faster and flatter than `cardExpand`.
    static let tabSwitch = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Press-down feedback. Short and critically damped — no bounce.
    static let press = Animation.spring(response: 0.22, dampingFraction: 1.0)

    /// Phase / screen cross-fade.
    static let phaseChange = Animation.easeInOut(duration: 0.28)
}

// MARK: - Reduce Motion

/// Returns `animation` unless the user has asked iOS to reduce motion, in which
/// case it returns a short cross-fade.
///
/// Apply with `.animation(motion, value:)` so callers never branch themselves.
struct ReduceMotionAware: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation

    func body(content: Content) -> some View {
        content.transaction { transaction in
            transaction.animation = reduceMotion
                ? .easeOut(duration: 0.12)
                : animation
        }
    }
}

extension View {
    /// Applies `animation`, downgrading it to a brief fade under Reduce Motion.
    func accessibleAnimation(_ animation: Animation) -> some View {
        modifier(ReduceMotionAware(animation: animation))
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack && xcodegen generate
```

Run the build command. Expected: `EXIT=0`.

---

## Task 8: `StatusBadge` Component

`PlannedSessionView:118-146` is three near-identical `Text` blocks differing only in label,
foreground, and background tint. This collapses them to data plus one view.

**Files:**
- Create: `Lightstack/Core/Theme/StatusBadge.swift`
- Create: `LightstackTests/StatusBadgeTests.swift`
- Modify: `Lightstack/Features/MonthPlan/Views/PlannedSessionView.swift:118-146`

- [ ] **Step 1: Write the failing test**

Create `LightstackTests/StatusBadgeTests.swift`:

```swift
import XCTest
@testable import Lightstack

/// Tests the session -> badge status mapping.
final class StatusBadgeTests: XCTestCase {

    private let dayInSeconds: TimeInterval = 86_400

    func testCompletedTakesPrecedenceOverDate() {
        let past = Date().addingTimeInterval(-5 * dayInSeconds)
        XCTAssertEqual(BadgeStatus(completed: true, date: past), .done)
        XCTAssertEqual(BadgeStatus(completed: true, date: Date()), .done)
    }

    func testTodayIsDetected() {
        XCTAssertEqual(BadgeStatus(completed: false, date: Date()), .today)
    }

    func testPastIncompleteIsMissed() {
        let past = Date().addingTimeInterval(-5 * dayInSeconds)
        XCTAssertEqual(BadgeStatus(completed: false, date: past), .missed)
    }

    func testFutureIncompleteHasNoBadge() {
        let future = Date().addingTimeInterval(5 * dayInSeconds)
        XCTAssertNil(BadgeStatus(completed: false, date: future))
    }

    func testEveryStatusHasANonEmptyLabel() {
        for status in BadgeStatus.allCases {
            XCTAssertFalse(status.label.isEmpty, "\(status) has no label")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack && xcodegen generate
```

Then:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Lightstack.xcodeproj -scheme Lightstack -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.2' -only-testing:LightstackTests/StatusBadgeTests -quiet 2>&1 | tail -20; echo EXIT=$?
```

Expected: **FAIL** to compile with `cannot find 'BadgeStatus' in scope`.

- [ ] **Step 3: Create the component**

Create `Lightstack/Core/Theme/StatusBadge.swift`:

```swift
import SwiftUI

/// The state a dated, completable item can be in.
enum BadgeStatus: CaseIterable {
    case done
    case today
    case missed

    /// Derives status from completion plus date. Returns `nil` for future
    /// incomplete items, which intentionally carry no badge.
    init?(completed: Bool, date: Date) {
        if completed {
            self = .done
        } else if Calendar.current.isDateInToday(date) {
            self = .today
        } else if date < Calendar.current.startOfDay(for: Date()) {
            self = .missed
        } else {
            return nil
        }
    }

    var label: String {
        switch self {
        case .done:   return "Done"
        case .today:  return "Today"
        case .missed: return "Missed"
        }
    }

    var tint: Color {
        switch self {
        case .done:   return AppTheme.success
        case .today:  return AppTheme.accent
        case .missed: return AppTheme.warning
        }
    }
}

/// Capsule badge conveying a `BadgeStatus`.
struct StatusBadge: View {
    let status: BadgeStatus

    var body: some View {
        Text(status.label)
            .font(AppTheme.caveat(11, weight: .bold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(status.label)")
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the `StatusBadgeTests` command from Step 2. Expected: `EXIT=0`, five tests pass.

- [ ] **Step 5: Use it in `PlannedSessionView`**

Replace the whole `statusBadge` computed property (lines 118-146) with:

```swift
    @ViewBuilder
    private var statusBadge: some View {
        if let status = BadgeStatus(completed: session.completed, date: session.plannedDate) {
            StatusBadge(status: status)
        }
    }
```

Then delete the now-unused `isToday` and `isPast` helpers **only if nothing else references
them**. Check first:

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack/Lightstack
grep -n "isToday\|isPast" Features/MonthPlan/Views/PlannedSessionView.swift
```

`isToday` is also used in `actionButtons` (line 86), so **keep `isToday`** and delete only
`isPast`.

- [ ] **Step 6: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 7: Visually verify**

Open a planned session in the Month tab for a completed day, today, and a missed past day. Each
should show the correct badge; a future day should show none. Note the shape changes from a rounded
rectangle to a capsule — this is the intended refinement.

---

## Task 9: Card Motion And Haptics

**Files:**
- Modify: `Lightstack/Core/Theme/CardStyle.swift`

- [ ] **Step 1: Add an interactive, expandable card**

Append to `Lightstack/Core/Theme/CardStyle.swift`:

```swift
// MARK: - Expandable Card

/// A card that expands to reveal detail, with spring motion and haptics.
///
/// Motion is physics-based so a rapid second tap retargets the spring rather
/// than restarting it. Both the animation and the haptic defer to the user's
/// accessibility settings.
struct ExpandableCard<Header: View, Detail: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var header: Header
    @ViewBuilder var detail: Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppMotion.cardExpand) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    header
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Collapses details" : "Expands details")

            if isExpanded {
                detail
                    .padding(.top, 12)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal:   .opacity
                        )
                    )
            }
        }
        .lsCard()
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
        .animation(reduceMotion ? nil : AppMotion.cardExpand, value: isExpanded)
    }
}

// MARK: - Press Feedback

/// Scales and dims a card slightly while pressed. Skips the scale under
/// Reduce Motion, keeping only the opacity change.
struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(pressed: configuration.isPressed))
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(AppMotion.press, value: configuration.isPressed)
    }

    private func scale(pressed: Bool) -> CGFloat {
        guard pressed, !reduceMotion else { return 1.0 }
        return 0.98
    }
}
```

`.sensoryFeedback` requires iOS 17 — the deployment target is 17.0, so no availability check is
needed.

- [ ] **Step 2: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 3: Add selection haptics to chips**

In `AppTheme.swift`, add a haptic trigger to `JournalChip`. Replace its `body` with:

```swift
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.accent : Color(.secondarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
```

- [ ] **Step 4: Add selection haptics to the tab row**

In `MainTabView.swift`, add to `NotebookTabRow`'s outer `VStack`, next to the existing
`.background(.bar)`:

```swift
        .sensoryFeedback(.selection, trigger: selectedTab)
```

- [ ] **Step 5: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 6: Verify on a physical device**

Haptics do not fire in the simulator. On a device: tap tabs and chips and confirm a light
selection tick. Then enable Settings → Accessibility → Motion → Reduce Motion and confirm cards
cross-fade instead of springing.

---

## Task 10: Remove `GeometryReader` From `InkFillBar`

`InkFillBar` sits inside a `ForEach` over muscle groups in `ProfileView:195`, so its
`GeometryReader` is instantiated once per group. `GeometryReader` also fills its parent greedily,
which makes it awkward to compose.

**Files:**
- Modify: `Lightstack/Core/Theme/NotebookComponents.swift:129-149`

- [ ] **Step 1: Replace with a layout-free fill**

Replace the `InkFillBar` struct with:

```swift
struct InkFillBar: View {
    let progress: Double // 0.0 to 1.0

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 5)
            .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 1))
            .background(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.accent)
                    .containerRelativeFrame(.horizontal) { width, _ in
                        width * clamped
                    }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}
```

- [ ] **Step 2: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 3: Visually verify**

Open the Profile tab and check the muscle-group bars. Each fill width must match its percentage
label. If `containerRelativeFrame` measures the wrong container, fall back to a proportional
`HStack`:

```swift
HStack(spacing: 0) {
    Rectangle().fill(AppTheme.accent)
        .frame(maxWidth: .infinity)
        .layoutPriority(clamped == 0 ? 0 : Float(clamped))
    Rectangle().fill(Color.clear)
        .frame(maxWidth: .infinity)
        .layoutPriority(Float(1 - clamped))
}
```

---

## Task 11: Adopt The New Card Styles On Today And Month

The shims from Task 6 keep old call sites working. This task migrates the in-scope ones so the
new API is actually exercised.

**Files:**
- Modify: `Lightstack/Features/Today/Views/ConfirmWorkoutView.swift`
- Modify: `Lightstack/Features/MonthPlan/Views/PlannedSessionView.swift`
- Modify: `Lightstack/Features/MonthPlan/Views/MonthPlanView.swift`

- [ ] **Step 1: Find the in-scope call sites**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack/Lightstack
grep -rn "\.cardStyle()\|\.glowingCard()" \
  Features/Today/Views/ConfirmWorkoutView.swift \
  Features/MonthPlan/Views/PlannedSessionView.swift \
  Features/MonthPlan/Views/MonthPlanView.swift
```

- [ ] **Step 2: Migrate each one**

Apply these mechanical replacements at the sites found above:

```swift
// before
.cardStyle()
// after
.lsCard()

// before
.glowingCard()
// after
.lsCard(AccentedCardStyle())
```

In `PlannedSessionView`, `headerCard` is the primary card — give it emphasis by using
`.lsCard(AccentedCardStyle())`, and leave `detailsCard` as plain `.lsCard()`.

Leave call sites in FormAnalysis, Auth, Profile, and History on the shim — they are out of scope
per the spec.

- [ ] **Step 3: Build**

Run the build command. Expected: `EXIT=0`.

- [ ] **Step 4: Visually verify**

Check the Today confirmation screen and a planned-session detail. The header card should now carry
a leading accent strip; nothing should be clipped or double-padded.

---

## Task 12: Performance Audit

Read-only analysis over everything the previous tasks produced, plus the pre-identified targets
from the spec. Produce findings; do not refactor speculatively.

**Files:**
- Read: all files touched in Tasks 0-11
- Create: `docs/superpowers/notes/2026-09-25-perf-audit.md`

- [ ] **Step 1: Check for unstable identity and over-broad invalidation**

```bash
cd /Users/muhammadnaseem/IdeaProjects/LightStack/Lightstack
echo "--- AnyView (expect only CardStyle.swift) ---"
grep -rn "AnyView" --include="*.swift" .
echo "--- ForEach over array indices (unstable identity) ---"
grep -rn "ForEach(0\.\.<\|\.indices, id: \\\\.self" --include="*.swift" .
echo "--- .id( forcing teardown ---"
grep -rn "\.id(" --include="*.swift" .
echo "--- EnvironmentObject breadth ---"
grep -rln "@EnvironmentObject" --include="*.swift" . | wc -l
echo "--- non-lazy stacks inside ScrollView ---"
grep -rn "LazyVStack" --include="*.swift" . | wc -l
```

- [ ] **Step 2: Assess each finding against these criteria**

For every hit, record a verdict of **fix now**, **acceptable**, or **follow-up**:

- `AnyView` outside `CardStyle.swift` → fix now. Inside it → acceptable (bounded to chrome).
- `ForEach(tabs.indices, id: \.self)` over a fixed 5-element constant → acceptable.
- `ForEach(0..<n)` over **mutable model data** → fix now; switch to `Identifiable`.
- `.id(viewModel.phase)` in a phase switch → intentional teardown, but confirm it is not
  discarding in-progress user input. Record the verdict.
- `ScrollView` containing a plain `VStack` over an unbounded collection → fix now, use
  `LazyVStack`.

- [ ] **Step 3: Measure the real thing**

Launch on a physical device. In Xcode, Debug → View Debugging → enable **Color Blended Layers**
and check the card surfaces for heavy blending from stacked materials plus shadows. Then profile
with Instruments' Animation Hitches template: scroll History and Month, and expand/collapse cards.

Record the hitch ratio. Target: under 5ms of hitch time per second of scrolling.

- [ ] **Step 4: Write up the findings**

Create `docs/superpowers/notes/2026-09-25-perf-audit.md` with one section per finding: what it is,
file and line, verdict, and rationale. Include the Instruments numbers from Step 3.

- [ ] **Step 5: Apply only the "fix now" items**

Make those changes, then run the build command. Expected: `EXIT=0`. Leave "follow-up" items
documented but unimplemented.

---

## Verification Checklist

Before handing back for review, confirm all of:

- [ ] Build passes: `EXIT=0`
- [ ] Full test suite passes, including the two new test files
- [ ] `git status` shows `TodayView.swift` deleted and four new theme files added
- [ ] Simulator at default text size: Today, Month, History, Profile all look correct
- [ ] Simulator at Larger Text → maximum: no clipped or overlapping text
- [ ] VoiceOver: tab row announces selection; energy control is one adjustable element
- [ ] Reduce Motion on: cards fade rather than spring
- [ ] Physical device: selection haptics fire on tabs and chips

## Known Visual Changes

These are intended, not regressions — mention them at review:

1. **7-9pt text renders larger.** `.caption2` (~11pt) is the smallest semantic style, and 11pt is
   Apple's legibility floor. Affects `MonthDayTileView` "R" and short-type labels, `PRStamp`, and
   `SetNumberCircle`.
2. **Status badges are capsules**, previously rounded rectangles.
3. **`PlannedSessionView` header card gains a leading accent strip.**
4. **The tab indicator slides** between tabs instead of appearing instantly.
