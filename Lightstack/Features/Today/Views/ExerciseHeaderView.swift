import SwiftUI

/// Active-workout page header: title, subtitle, optional coach notes, superset
/// actions, then a single controls row (navigation left, tools right).
/// A page holds one exercise, or 2-4 members of a superset.
struct ExerciseHeaderView: View {
    let members: [Exercise]
    /// Number of pages (a superset counts once).
    let totalCount: Int
    let canLinkWithNext: Bool
    let onAdd: () -> Void
    let onFormDemo: () -> Void
    let onRecordForm: () -> Void
    let onLinkWithNext: () -> Void
    let onUnlink: () -> Void
    /// Long-press "Remove" on a member's name. The caller confirms before removing.
    let onRemove: (Exercise) -> Void
    /// Opens the reorder sheet. The button only shows with two or more pages.
    var onReorder: (() -> Void)? = nil

    private var isSuperset: Bool { members.count > 1 }

    private var subtitle: String {
        if isSuperset {
            let groups = members.map(\.muscleGroup).reduce(into: [String]()) { acc, g in
                if !acc.contains(g) { acc.append(g) }
            }
            return "Superset · " + groups.joined(separator: ", ")
        }
        guard let exercise = members.first else { return "" }
        if let target = exercise.targetSets {
            return "\(exercise.muscleGroup) · \(target) sets"
        }
        return exercise.muscleGroup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(members) { member in
                            nameText(member)
                        }
                    }
                    .accessibilityElement(children: .contain)

                    Text(subtitle)
                        .font(AppTheme.caveat(17))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(isSuperset ? 2 : 1)
                        .minimumScaleFactor(0.8)
                }
                controlsRow
            }

            ForEach(members) { member in
                if let message = member.coachNoteParts.message {
                    CoachNoteRow(message: message, title: isSuperset ? "Coach note · \(member.name)" : "Coach note")
                        .id(member.id) // collapse state resets per exercise
                }
            }

            supersetRow
        }
    }

    /// The long-press menu attaches to the name text only, so scrolling and taps
    /// elsewhere on the header can never trigger a removal.
    private func nameText(_ member: Exercise) -> some View {
        Text(member.name)
            .font(AppTheme.playfair(isSuperset ? 21 : 25, weight: .bold))
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .contextMenu {
                Button(role: .destructive) {
                    onRemove(member)
                } label: {
                    Label("Remove Exercise", systemImage: "trash")
                }
            }
    }

    private var supersetRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { supersetButtons }
            VStack(alignment: .leading, spacing: 8) { supersetButtons }
        }
    }

    @ViewBuilder
    private var supersetButtons: some View {
        Button(action: onLinkWithNext) {
            Label("Superset with next", systemImage: "link")
        }
        .buttonStyle(SupersetChipStyle())
        .accessibilityIdentifier("supersetWithNextButton")
        .disabled(!canLinkWithNext)
        .opacity(canLinkWithNext ? 1 : 0.4)
        .accessibilityHint(canLinkWithNext
                           ? "Alternates sets between this and the next exercise"
                           : "Unavailable: no next exercise, or a superset can have at most 4 exercises")
        if isSuperset {
            Button(action: onUnlink) {
                Label("Unlink", systemImage: "scissors")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(SupersetChipStyle())
            .accessibilityIdentifier("unlinkButton")
            .accessibilityHint("Splits the superset back into separate exercises")
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 6) {
            // Secondary actions share one menu: a button each pushed the row wider
            // than narrow phones, spilling the whole workout page off both edges.
            if showsMoreMenu {
                Menu {
                    if let onReorder, totalCount > 1 {
                        Button(action: onReorder) {
                            Label("Reorder exercises", systemImage: "arrow.up.arrow.down")
                        }
                        .accessibilityIdentifier("reorderExercisesButton")
                    }
                    if FeatureFlags.formAnalysisEnabled {
                        Button(action: onFormDemo) { Label("Form guide", systemImage: "figure.stand") }
                        Button(action: onRecordForm) { Label("Record form", systemImage: "camera.fill") }
                    }
                } label: {
                    iconLabel("ellipsis")
                }
                .accessibilityLabel("More actions")
                .accessibilityIdentifier("moreActionsButton")
            }
            iconButton("plus", label: "Add exercise", action: onAdd)
                .accessibilityIdentifier("addExerciseButton")
        }
    }

    private var showsMoreMenu: Bool {
        FeatureFlags.formAnalysisEnabled || (onReorder != nil && totalCount > 1)
    }

    private func iconLabel(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: AppTheme.minTouchSize, height: AppTheme.minTouchSize)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            iconLabel(systemName)
        }
        .accessibilityLabel(label)
    }
}

private struct SupersetChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.caveat(16, weight: .bold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: AppTheme.minTouchSize)
            .background(AppTheme.surfaceElevated.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }
}

/// Collapsible coach note: 2-line preview, tap to expand.
private struct CoachNoteRow: View {
    let message: String
    var title: String = "Coach note"
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
                    Text(title)
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
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded. \(message)" : "Collapsed. \(message)")
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
    }
}
