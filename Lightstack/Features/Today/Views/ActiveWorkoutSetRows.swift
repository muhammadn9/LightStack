import SwiftUI

// MARK: - Logged Set Rows

/// Logged set row — dispatches to strength or cardio variant.
struct LoggedSetRow: View {
    let workoutSet: WorkoutSet
    let number: Int
    let exercise: Exercise
    let onDelete: () -> Void

    var body: some View {
        if exercise.trackingType == .cardio {
            CardioLoggedSetRow(workoutSet: workoutSet, number: number, onDelete: onDelete)
        } else {
            StrengthLoggedSetRow(workoutSet: workoutSet, number: number, onDelete: onDelete)
        }
    }
}

private struct StrengthLoggedSetRow: View {
    let workoutSet: WorkoutSet
    let number: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            SetNumberCircle(number: number, isLogged: true)

            Text(String(format: "%.1f", workoutSet.weightLbs))
                .font(AppTheme.caveat(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("lbs")
                .font(AppTheme.caveat(12))
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            Text("×\(workoutSet.reps)")
                .font(AppTheme.caveat(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            if workoutSet.isPR {
                PRStamp()
            } else {
                Text("✓ RIR \(workoutSet.rir.map(String.init) ?? "—")")
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.success)
                    .accessibilityLabel(workoutSet.rir.map { "RIR \($0)" } ?? "RIR not recorded")
            }

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.body)
            }
            .accessibilityLabel("Delete set")
            .accessibilityHint("Removes this logged set")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .background(AppTheme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct CardioLoggedSetRow: View {
    let workoutSet: WorkoutSet
    let number: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            SetNumberCircle(number: number, isLogged: true)

            let summary = CardioFormatting.loggedSummary(
                durationSeconds: workoutSet.durationSeconds,
                distanceMiles: workoutSet.distanceMiles,
                inclineLevel: workoutSet.inclineLevel
            )
            Text(summary.isEmpty ? "—" : summary)
                .font(AppTheme.caveat(14, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Text("✓")
                .font(AppTheme.caveat(12))
                .foregroundStyle(AppTheme.success)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.body)
            }
            .accessibilityLabel("Delete set")
            .accessibilityHint("Removes this logged set")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .background(AppTheme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Pending Set Rows

/// Pending (not-yet-logged) strength set row with editable weight/reps/RIR fields.
struct StrengthPendingSetRow: View {
    let index: Int
    let setNumber: Int
    @Binding var pendingSets: [PendingSetInput]
    let exerciseId: UUID
    let onLog: () -> Void
    let onDelete: () -> Void

    private var hint: PreviousSetHint? { entry.previous }
    private var canLog: Bool { !entry.reps.isEmpty || hint != nil }

    private func hintPrompt(_ text: String) -> Text {
        Text(text).foregroundStyle(AppTheme.textSecondary.opacity(0.6))
    }

    private var weightHintText: String {
        guard let hint else { return "lbs" }
        return hint.weightLbs == 0 ? "BW" : String(format: "%g", hint.weightLbs)
    }

    /// Rows can briefly outlive their entry (e.g. while fading out after Finish
    /// logs every pending set at once), so never subscript `pendingSets` blindly.
    private var isValid: Bool { pendingSets.indices.contains(index) }
    private var entry: PendingSetInput {
        isValid ? pendingSets[index] : PendingSetInput(weight: "", reps: "", rir: "")
    }
    private func field(_ keyPath: WritableKeyPath<PendingSetInput, String>) -> Binding<String> {
        Binding(
            get: { isValid ? pendingSets[index][keyPath: keyPath] : "" },
            set: { if isValid { pendingSets[index][keyPath: keyPath] = $0 } }
        )
    }

    var body: some View {
        if isValid { content }
    }

    private var content: some View {
        HStack(spacing: 9) {
            SetNumberCircle(number: setNumber, isLogged: false)

            // Weight field
            VStack(spacing: 3) {
                TextField("lbs", text: field(\.weight), prompt: hintPrompt(weightHintText))
                    .keyboardType(.decimalPad)
                    .font(AppTheme.plexMono(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 78)
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityLabel(hint.map { "Weight, last time \($0.weightLbs == 0 ? "bodyweight" : String(format: "%g", $0.weightLbs))" } ?? "Weight")
                Rectangle()
                    .fill(entry.weight.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 78, height: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: entry.weight.isEmpty)
            }

            Text("×")
                .font(AppTheme.caveat(18))
                .foregroundStyle(AppTheme.border)

            // Reps field
            VStack(spacing: 3) {
                TextField("reps", text: field(\.reps), prompt: hintPrompt(hint.map { String($0.reps) } ?? "reps"))
                    .keyboardType(.numberPad)
                    .font(AppTheme.plexMono(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 67)
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityLabel(hint.map { "Reps, last time \($0.reps)" } ?? "Reps")
                Rectangle()
                    .fill(entry.reps.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 67, height: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: entry.reps.isEmpty)
            }

            // RIR field
            VStack(spacing: 3) {
                TextField("RIR", text: field(\.rir), prompt: hintPrompt(hint.map { $0.rir.map(String.init) ?? "—" } ?? "RIR"))
                    .keyboardType(.numberPad)
                    .font(AppTheme.plexMono(16))
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityLabel(hint.map { "RIR, last time \($0.rir.map(String.init) ?? "not recorded")" } ?? "RIR")
                Rectangle()
                    .fill(AppTheme.border.opacity(0.5))
                    .frame(width: 56, height: 1.5)
            }

            // Log button
            Button(action: onLog) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(!canLog ? AppTheme.surfaceElevated : AppTheme.accent)
                        .frame(width: 31, height: 31)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(!canLog
                                         ? AppTheme.textSecondary
                                         : AppTheme.background)
                }
                .shadow(color: AppTheme.accent.opacity(!canLog ? 0 : 0.3), radius: 2, x: 1, y: 2)
            }
            .disabled(!canLog)
            .accessibilityLabel("Log set")

            // Delete pending
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.body)
            }
            .accessibilityLabel("Remove set")
            .accessibilityHint("Removes this pending set from the exercise")
        }
    }
}

/// Pending (not-yet-logged) cardio set row with editable duration/distance/incline fields.
struct CardioPendingSetRow: View {
    let index: Int
    let setNumber: Int
    @Binding var pendingSets: [PendingSetInput]
    let exerciseId: UUID
    let onLog: () -> Void
    let onDelete: () -> Void

    /// Rows can briefly outlive their entry (e.g. while fading out after Finish
    /// logs every pending set at once), so never subscript `pendingSets` blindly.
    private var isValid: Bool { pendingSets.indices.contains(index) }
    private var entry: PendingSetInput {
        isValid ? pendingSets[index] : PendingSetInput(weight: "", reps: "", rir: "")
    }
    private func field(_ keyPath: WritableKeyPath<PendingSetInput, String>) -> Binding<String> {
        Binding(
            get: { isValid ? pendingSets[index][keyPath: keyPath] : "" },
            set: { if isValid { pendingSets[index][keyPath: keyPath] = $0 } }
        )
    }

    var body: some View {
        if isValid { content }
    }

    private var content: some View {
        HStack(spacing: 9) {
            SetNumberCircle(number: setNumber, isLogged: false)

            // Time field
            VStack(spacing: 3) {
                TextField("mm:ss", text: field(\.duration))
                    .keyboardType(.numbersAndPunctuation)
                    .font(AppTheme.plexMono(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 78)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(entry.duration.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 78, height: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: entry.duration.isEmpty)
            }

            Text("·")
                .font(AppTheme.caveat(18))
                .foregroundStyle(AppTheme.border)

            // Distance field
            VStack(spacing: 3) {
                TextField("mi", text: field(\.distance))
                    .keyboardType(.decimalPad)
                    .font(AppTheme.plexMono(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 67)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(entry.distance.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 67, height: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: entry.distance.isEmpty)
            }

            // Incline field
            VStack(spacing: 3) {
                TextField("%", text: field(\.incline))
                    .keyboardType(.decimalPad)
                    .font(AppTheme.plexMono(16))
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(AppTheme.border.opacity(0.5))
                    .frame(width: 56, height: 1.5)
            }

            // Log button (enabled when duration is non-empty)
            Button(action: onLog) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.duration.isEmpty ? AppTheme.surfaceElevated : AppTheme.accent)
                        .frame(width: 31, height: 31)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(entry.duration.isEmpty
                                         ? AppTheme.textSecondary
                                         : AppTheme.background)
                }
                .shadow(color: AppTheme.accent.opacity(entry.duration.isEmpty ? 0 : 0.3), radius: 2, x: 1, y: 2)
            }
            .disabled(entry.duration.isEmpty)
            .accessibilityLabel("Log set")

            // Delete pending
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.body)
            }
            .accessibilityLabel("Remove set")
            .accessibilityHint("Removes this pending set from the exercise")
        }
    }
}
