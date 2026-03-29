import SwiftUI

/// Exercise card showing name, targets, logged sets, and inline input row.
struct ExerciseTableView: View {
    let exercise: Exercise
    let loggedSets: [WorkoutSet]
    @Binding var editingWeight: String
    @Binding var editingReps: String
    @Binding var editingRir: String
    let onLogSet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            targetInfoRow
            loggedSetsList
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
            Text("\(loggedSets.count)/\(exercise.targetSets ?? 0) sets")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accent)
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
            SetRowView(workoutSet: workoutSet)
                .opacity(index.isMultiple(of: 2) ? 1.0 : 0.9)
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
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
