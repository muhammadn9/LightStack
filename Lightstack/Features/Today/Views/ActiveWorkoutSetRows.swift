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
                Text("✓ RIR \(workoutSet.rir)")
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.success)
            }

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.body)
            }
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

    var body: some View {
        HStack(spacing: 9) {
            SetNumberCircle(number: setNumber, isLogged: false)

            // Weight field
            VStack(spacing: 3) {
                TextField("lbs", text: $pendingSets[index].weight)
                    .keyboardType(.decimalPad)
                    .font(AppTheme.plexMono(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 78)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(pendingSets[index].weight.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 78, height: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: pendingSets[index].weight.isEmpty)
            }

            Text("×")
                .font(AppTheme.caveat(18))
                .foregroundStyle(AppTheme.border)

            // Reps field
            VStack(spacing: 3) {
                TextField("reps", text: $pendingSets[index].reps)
                    .keyboardType(.numberPad)
                    .font(AppTheme.plexMono(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 67)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(pendingSets[index].reps.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 67, height: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: pendingSets[index].reps.isEmpty)
            }

            // RIR field
            VStack(spacing: 3) {
                TextField("RIR", text: $pendingSets[index].rir)
                    .keyboardType(.numberPad)
                    .font(AppTheme.plexMono(16))
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(AppTheme.border.opacity(0.5))
                    .frame(width: 56, height: 1.5)
            }

            // Log button
            Button(action: onLog) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(pendingSets[index].reps.isEmpty ? AppTheme.surfaceElevated : AppTheme.accent)
                        .frame(width: 31, height: 31)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(pendingSets[index].reps.isEmpty
                                         ? AppTheme.textSecondary
                                         : AppTheme.background)
                }
                .shadow(color: AppTheme.accent.opacity(pendingSets[index].reps.isEmpty ? 0 : 0.3), radius: 2, x: 1, y: 2)
            }
            .disabled(pendingSets[index].reps.isEmpty)

            // Delete pending
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.body)
            }
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

    var body: some View {
        HStack(spacing: 9) {
            SetNumberCircle(number: setNumber, isLogged: false)

            // Time field
            VStack(spacing: 3) {
                TextField("mm:ss", text: $pendingSets[index].duration)
                    .keyboardType(.numbersAndPunctuation)
                    .font(AppTheme.plexMono(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 78)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(pendingSets[index].duration.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 78, height: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: pendingSets[index].duration.isEmpty)
            }

            Text("·")
                .font(AppTheme.caveat(18))
                .foregroundStyle(AppTheme.border)

            // Distance field
            VStack(spacing: 3) {
                TextField("mi", text: $pendingSets[index].distance)
                    .keyboardType(.decimalPad)
                    .font(AppTheme.plexMono(16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 67)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(pendingSets[index].distance.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 67, height: 1.5)
                    .animation(.easeInOut(duration: 0.2), value: pendingSets[index].distance.isEmpty)
            }

            // Incline field
            VStack(spacing: 3) {
                TextField("%", text: $pendingSets[index].incline)
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
                        .fill(pendingSets[index].duration.isEmpty ? AppTheme.surfaceElevated : AppTheme.accent)
                        .frame(width: 31, height: 31)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(pendingSets[index].duration.isEmpty
                                         ? AppTheme.textSecondary
                                         : AppTheme.background)
                }
                .shadow(color: AppTheme.accent.opacity(pendingSets[index].duration.isEmpty ? 0 : 0.3), radius: 2, x: 1, y: 2)
            }
            .disabled(pendingSets[index].duration.isEmpty)

            // Delete pending
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.body)
            }
        }
    }
}
