import SwiftUI

/// One bar per rep: height is the range of motion, colour says clean or flagged. Tap to replay the rep.
struct FormRepStrip: View {

    let reps: [RepSummary]
    let onSelect: (Int) -> Void

    private let barAreaHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormSectionHeader(title: "Reps", subtitle: "Bar height is how far each rep went. Tap one to replay it.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(reps) { rep in bar(rep) }
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 16) {
                legend(color: AppTheme.accent, text: "Clean")
                legend(color: AppTheme.warning, text: "Flagged")
            }
        }
        .formCard()
    }

    private func bar(_ rep: RepSummary) -> some View {
        let fraction = min(max(rep.rangePercent / 100, 0.08), 1)
        return Button { onSelect(rep.rep.number) } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(rep.isClean ? AppTheme.accent : AppTheme.warning)
                    .frame(width: 30, height: barAreaHeight * fraction)
                    .frame(height: barAreaHeight, alignment: .bottom)
                Text("\(rep.rep.number)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(minWidth: 36, minHeight: AppTheme.minTouchSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rep \(rep.rep.number), \(Int(rep.rangePercent.rounded())) percent of best range, "
                            + (rep.isClean ? "clean" : "flagged"))
        .accessibilityHint("Replays this rep")
        .accessibilityIdentifier("formResults.rep.\(rep.rep.number)")
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityHidden(true)
    }
}
