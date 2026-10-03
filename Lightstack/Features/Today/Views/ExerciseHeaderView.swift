import SwiftUI

/// Active-workout exercise header: full-width title, subtitle, optional coach
/// note, then a single controls row (navigation left, tools right).
struct ExerciseHeaderView: View {
    let exercise: Exercise
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onAdd: () -> Void
    let onFormDemo: () -> Void
    let onRecordForm: () -> Void

    private var subtitle: String {
        if let target = exercise.targetSets {
            return "\(exercise.muscleGroup) · \(target) sets"
        }
        return exercise.muscleGroup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name)
                .font(AppTheme.playfair(25, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(AppTheme.caveat(17))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let message = exercise.coachNoteParts.message {
                CoachNoteRow(message: message)
                    .id(exercise.id) // collapse state resets per exercise
            }

            controlsRow
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 6) {
            iconButton("chevron.left", label: "Previous exercise", action: onPrevious)
                .disabled(currentIndex <= 0)
                .opacity(currentIndex <= 0 ? 0.35 : 1)
            Text("\(currentIndex + 1) of \(totalCount)")
                .font(AppTheme.plexMono(14))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 52)
            iconButton("chevron.right", label: "Next exercise", action: onNext)
                .disabled(currentIndex >= totalCount - 1)
                .opacity(currentIndex >= totalCount - 1 ? 0.35 : 1)
            Spacer(minLength: 8)
            if FeatureFlags.formAnalysisEnabled {
                iconButton("figure.stand", label: "Form guide", action: onFormDemo)
                iconButton("camera.fill", label: "Record form", action: onRecordForm)
            }
            iconButton("plus", label: "Add exercise", action: onAdd)
        }
    }

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: AppTheme.minTouchSize, height: AppTheme.minTouchSize)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }
}

/// Collapsible coach note: 2-line preview, tap to expand.
private struct CoachNoteRow: View {
    let message: String
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppMotion.cardExpand) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("Coach note")
                        .font(AppTheme.caveat(17))
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: AppTheme.minTouchSize)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coach note")
        .accessibilityValue(isExpanded ? "Expanded. \(message)" : "Collapsed. \(message)")
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
    }
}
