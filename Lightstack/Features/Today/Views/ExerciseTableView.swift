import SwiftUI

/// Exercise card showing name, targets, logged sets, and one editable input row
/// per pending set so the user can see and fill all sets at once.
struct ExerciseTableView: View {
    let exercise: Exercise
    let loggedSets: [WorkoutSet]
    @Binding var pendingSets: [PendingSetInput]
    let restTimeRemaining: String?
    let onLogSet: (Int) -> Void     // index into pendingSets
    let onDeletePendingSet: ((Int) -> Void)?
    let onDeleteSet: ((WorkoutSet) -> Void)?
    let onAddSet: (() -> Void)?
    var onWatchForm: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if hasTargetInfo { targetInfoRow }
            loggedSetsList
            pendingSetInputRows
            addSetButton
            if let restTime = restTimeRemaining {
                restTimerBanner(restTime)
            }
        }
        .glowingCard()
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(exercise.muscleGroup)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accentSecondary)
            }
            Spacer()
            if let watchForm = onWatchForm {
                Button(action: watchForm) {
                    Label("Watch Form", systemImage: "camera.fill")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accentSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.accentSecondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if let target = exercise.targetSets {
                Text("\(loggedSets.count)/\(target) sets")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
            } else {
                Text("\(loggedSets.count) sets")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    // MARK: - Target Info (rest seconds only — weight/reps/rir shown in set rows)

    private var hasTargetInfo: Bool {
        (exercise.restSeconds ?? 0) > 0
    }

    private var targetInfoRow: some View {
        HStack(spacing: 12) {
            if let rest = exercise.restSeconds, rest > 0 {
                targetBadge("Rest", value: "\(rest)s")
            }
        }
    }

    private func targetBadge(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.accent.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Logged Sets

    private var loggedSetsList: some View {
        ForEach(Array(loggedSets.enumerated()), id: \.element.id) { index, workoutSet in
            HStack(spacing: 8) {
                Text("Set \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 40, alignment: .leading)
                SetRowView(workoutSet: workoutSet)
                Spacer()
                if let onDelete = onDeleteSet {
                    Button(action: { onDelete(workoutSet) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(AppTheme.warning.opacity(0.7))
                            .font(.body)
                    }
                }
            }
        }
    }

    // MARK: - Pending Set Input Rows

    private var pendingSetColumnHeaders: some View {
        HStack(spacing: 8) {
            Text("")
                .frame(width: 40)
            Text("Lbs")
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 70)
            Text("Reps")
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 60)
            Text("RIR")
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 50)
        }
    }

    @ViewBuilder
    private var pendingSetInputRows: some View {
        if !pendingSets.isEmpty {
            pendingSetColumnHeaders
        }
        ForEach(Array(pendingSets.enumerated()), id: \.element.id) { index, _ in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Set \(loggedSets.count + index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 40, alignment: .leading)

                    inputField("lbs", text: $pendingSets[index].weight, width: 70, keyboard: .decimalPad)
                    inputField("reps", text: $pendingSets[index].reps, width: 60, keyboard: .numberPad)
                    inputField("RIR", text: $pendingSets[index].rir, width: 50, keyboard: .numberPad)

                    Button(action: { onLogSet(index) }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                pendingSets[index].reps.isEmpty
                                    ? AppTheme.textSecondary
                                    : AppTheme.accent
                            )
                            .shadow(color: AppTheme.accent.opacity(0.3), radius: 4)
                    }
                    .disabled(pendingSets[index].reps.isEmpty)

                    if let onDelete = onDeletePendingSet {
                        Button(action: { onDelete(index) }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.warning.opacity(0.7))
                                .font(.body)
                        }
                    }
                }

                // Optional per-set note
                TextField("Note (optional)", text: $pendingSets[index].note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.leading, 48)
            }
        }
    }

    // MARK: - Add Set Button

    private var addSetButton: some View {
        Button(action: { onAddSet?() }) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                Text("Add Set")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rest Timer Banner

    private func restTimerBanner(_ time: String) -> some View {
        HStack {
            Image(systemName: "timer")
                .foregroundStyle(AppTheme.warning)
            Text("Rest: \(time)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.warning)
            Spacer()
        }
        .padding(10)
        .background(AppTheme.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Input Field

    private func inputField(_ placeholder: String, text: Binding<String>, width: CGFloat, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .font(.subheadline)
            .padding(10)
            .frame(width: width)
            .background(AppTheme.surfaceElevated)
            .foregroundStyle(AppTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
