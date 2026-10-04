import SwiftUI

/// Edit-mode form for a past workout. Pure UI over a `WorkoutEditDraft` binding.
struct WorkoutEditForm: View {
    @Binding var draft: WorkoutEditDraft
    let errors: [WorkoutEditDraft.DraftFieldError]
    let onAddExercise: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.sectionSpacing) {
            detailsCard
            ForEach($draft.exercises) { $exercise in
                exerciseCard($exercise)
            }
            Button(action: onAddExercise) {
                Label("Add Exercise", systemImage: "plus")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(AppTheme.accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .stroke(AppTheme.accent.opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Workout Name")
            TextField("Workout name", text: $draft.name)
                .padding(14)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .foregroundStyle(AppTheme.textPrimary)

            DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            sectionLabel("My Notes")
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
                .padding(14)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .cardStyle()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.playfairItalic(16, weight: .bold))
            .foregroundStyle(AppTheme.textPrimary)
    }

    // MARK: - Exercise

    private func exerciseCard(_ exercise: Binding<WorkoutEditDraft.DraftExercise>) -> some View {
        let ex = exercise.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            if let label = draft.supersetLabel(for: ex.id) {
                Label(label, systemImage: "link")
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.accentSecondary)
            }
            HStack(spacing: 8) {
                Text(ex.name)
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    draft.removeExercise(ex.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(AppTheme.warning)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Remove \(ex.name)")
            }

            ForEach(exercise.sets) { $set in
                let number = (ex.sets.firstIndex { $0.id == set.id } ?? 0) + 1
                setRow(number: number, exerciseId: ex.id, exerciseName: ex.name, set: $set)
            }

            Button {
                draft.addSet(to: ex.id)
            } label: {
                Label("Add Set", systemImage: "plus.circle")
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Add set to \(ex.name)")
        }
        .cardStyle()
    }

    private func setRow(number: Int, exerciseId: UUID, exerciseName: String,
                        set: Binding<WorkoutEditDraft.DraftSet>) -> some View {
        let setId = set.wrappedValue.id
        let exIndex = draft.exercises.firstIndex { $0.id == exerciseId } ?? 0
        let idPrefix = "editSet.\(exIndex).\(number - 1)"
        return HStack(alignment: .bottom, spacing: 10) {
            Text("\(number)")
                .font(AppTheme.plexMono(12))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityHidden(true)
            field("lbs", label: "Weight", text: set.weight, keyboard: .decimalPad, id: "\(idPrefix).weight",
                  hasError: hasError(exerciseId, setId, .weight))
            field("reps", label: "Reps", text: set.reps, keyboard: .numberPad, id: "\(idPrefix).reps",
                  hasError: hasError(exerciseId, setId, .reps))
            field("RIR", label: "RIR", text: set.rir, keyboard: .numberPad, id: "\(idPrefix).rir",
                  hasError: hasError(exerciseId, setId, .rir))
            Button {
                draft.removeSet(exerciseId: exerciseId, setId: setId)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(AppTheme.warning)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Delete set \(number) of \(exerciseName)")
        }
    }

    private func field(_ placeholder: String, label: String, text: Binding<String>,
                       keyboard: UIKeyboardType, id: String, hasError: Bool) -> some View {
        VStack(spacing: 3) {
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(AppTheme.plexMono(16, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(hasError ? AppTheme.warning : AppTheme.textPrimary)
                .accessibilityIdentifier(id)
                .accessibilityLabel(hasError ? "\(label), invalid" : label)
            Rectangle()
                .fill(hasError ? AppTheme.warning : AppTheme.accent.opacity(0.7))
                .frame(height: 1.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func hasError(_ exerciseId: UUID, _ setId: UUID, _ field: WorkoutEditDraft.Field) -> Bool {
        errors.contains(.init(exerciseId: exerciseId, setId: setId, field: field))
    }
}
