import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Palette mirrors AppTheme (the extension can't link the app's theme file).
private enum Palette {
    static let accent = Color(red: 0.239, green: 0.863, blue: 0.290)
    static let secondary = Color.white.opacity(0.65)
    static let chip = Color.white.opacity(0.14)
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LightstackWorkoutAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color(red: 0.043, green: 0.051, blue: 0.055))
                .activitySystemActionForegroundColor(Palette.accent)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(state.allDone ? "Done" : state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: 180, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedView(state: state)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    SetSummary(state: state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ControlsView(state: state)
                }
            } compactLeading: {
                Text(state.allDone ? "OK" : Self.initials(state.exerciseName))
                    .font(.caption.bold())
                    .foregroundStyle(Palette.accent)
            } compactTrailing: {
                if let end = state.restEndDate, end > Date() {
                    RestCountdown(end: end)
                        .font(.caption.monospacedDigit().bold())
                        .frame(width: 40)
                } else {
                    Text(state.allDone ? "-" : "\(state.setNumber)")
                        .font(.caption.monospacedDigit().bold())
                }
            } minimal: {
                if let end = state.restEndDate, end > Date() {
                    RestCountdown(end: end)
                        .font(.system(size: 10).monospacedDigit().bold())
                        .minimumScaleFactor(0.5)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Palette.accent)
                }
            }
            .keylineTint(Palette.accent)
        }
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "LS" : String(letters).uppercased()
    }
}

// MARK: - Pieces

private struct RestCountdown: View {
    let end: Date
    var body: some View {
        let now = Date()
        Text(timerInterval: now...max(now, end), countsDown: true)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(Palette.accent)
    }
}

private struct ElapsedView: View {
    let state: LightstackWorkoutAttributes.ContentState
    var body: some View {
        if state.isPaused {
            Text(String(format: "%d:%02d", state.pausedElapsedSeconds / 60, state.pausedElapsedSeconds % 60))
        } else {
            Text(state.elapsedAnchor, style: .timer)
        }
    }
}

private struct SetSummary: View {
    let state: LightstackWorkoutAttributes.ContentState

    var body: some View {
        if state.allDone {
            Text("All sets logged. Finish in the app.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
        } else {
            VStack(spacing: 2) {
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                Text(detail)
                    .font(.title3.monospacedDigit().bold())
            }
        }
    }

    private var headline: String {
        var text = "Set \(state.setNumber) of \(state.totalSets)"
        if let label = state.setLabel { text += " · \(label)" }
        return text
    }

    private var detail: String {
        if state.isCardio { return state.cardioText ?? "Cardio" }
        var text = state.weightText == "BW" ? "BW" : "\(state.weightText) \(state.unit)"
        text += " × \(state.reps)"
        if let rir = state.rir { text += " @RIR \(rir)" }
        return text
    }
}

private struct StepButton: View {
    let symbol: String
    let action: LiveActivityAction
    let setKey: String

    var body: some View {
        Button(intent: WorkoutActionIntent(action, setKey: setKey)) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.chip))
        }
        .buttonStyle(.plain)
    }
}

private struct ControlsView: View {
    let state: LightstackWorkoutAttributes.ContentState

    var body: some View {
        if state.allDone {
            EmptyView()
        } else if let end = state.restEndDate, end > Date() {
            HStack {
                Text("Rest")
                    .foregroundStyle(Palette.secondary)
                RestCountdown(end: end)
                    .font(.title2.monospacedDigit().bold())
                Spacer()
                Button(intent: WorkoutActionIntent(.skipRest, setKey: state.setKey)) {
                    Text("Skip rest")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Palette.chip))
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 10) {
                if !state.isCardio {
                    StepButton(symbol: "minus", action: .weightDown, setKey: state.setKey)
                    Text("Wt").font(.caption).foregroundStyle(Palette.secondary)
                    StepButton(symbol: "plus", action: .weightUp, setKey: state.setKey)
                    Spacer(minLength: 4)
                    StepButton(symbol: "minus", action: .repsDown, setKey: state.setKey)
                    Text("Reps").font(.caption).foregroundStyle(Palette.secondary)
                    StepButton(symbol: "plus", action: .repsUp, setKey: state.setKey)
                    Spacer(minLength: 4)
                } else {
                    Spacer()
                }
                Button(intent: WorkoutActionIntent(.logSet, setKey: state.setKey)) {
                    Text("Log set")
                        .font(.subheadline.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(state.canLog ? Palette.accent : Palette.chip))
                }
                .buttonStyle(.plain)
                .disabled(!state.canLog)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: LightstackWorkoutAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.allDone ? "Workout complete" : state.exerciseName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                ElapsedView(state: state)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.secondary)
            }
            SetSummary(state: state)
                .frame(maxWidth: .infinity, alignment: .leading)
            ControlsView(state: state)
            if let next = state.nextExercise, !state.allDone {
                Text("Next: \(next)")
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
    }
}
