import SwiftUI

/// Exercise card showing name, targets, logged sets, and inline input row.
struct ExerciseTableView: View {
    let exercise: Exercise
    let loggedSets: [WorkoutSet]
    @Binding var editingWeight: String
    @Binding var editingReps: String
    @Binding var editingRir: String
    @Binding var editingNote: String
    let restTimeRemaining: String?
    let onLogSet: () -> Void
    let onDeleteSet: ((WorkoutSet) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            targetInfoRow
            loggedSetsList
            pendingSetRows
            if let restTime = restTimeRemaining {
                restTimerBanner(restTime)
            }
            inputRow
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

    // MARK: - Target Info

    private var targetInfoRow: some View {
        HStack(spacing: 12) {
            if let reps = exercise.targetReps {
                targetBadge("Reps", value: reps)
            }
            if let rir = exercise.targetRir {
                targetBadge("RIR", value: rir)
            }
            if let rest = exercise.restSeconds, rest > 0 {
                targetBadge("Rest", value: "\(rest)s")
            }
            if let note = exercise.coachNote {
                targetBadge("Weight", value: note.replacingOccurrences(of: "Target: ", with: ""))
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

    // MARK: - Pending Set Rows

    @ViewBuilder
    private var pendingSetRows: some View {
        let target = exercise.targetSets ?? 0
        let logged = loggedSets.count
        if target > logged {
            ForEach((logged + 1)...target, id: \.self) { setNumber in
                HStack(spacing: 8) {
                    Text("Set \(setNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.4))
                        .frame(width: 40, alignment: .leading)
                    HStack(spacing: 6) {
                        if let note = exercise.coachNote {
                            Text(note.replacingOccurrences(of: "Target: ", with: ""))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.4))
                        }
                        if let reps = exercise.targetReps {
                            Text("× \(reps)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.4))
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
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

    // MARK: - Input Row

    private var inputRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                inputField("lbs", text: $editingWeight, width: 70, keyboard: .decimalPad)
                inputField("reps", text: $editingReps, width: 60, keyboard: .numberPad)
                inputField("RIR", text: $editingRir, width: 50, keyboard: .numberPad)
                Button(action: onLogSet) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 4)
                }
                .disabled(editingWeight.isEmpty || editingReps.isEmpty)
            }
            TextField("Set note (optional)...", text: $editingNote)
                .font(.caption)
                .padding(8)
                .background(AppTheme.surfaceElevated)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .foregroundStyle(AppTheme.accent)
            }
        }
    }

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
