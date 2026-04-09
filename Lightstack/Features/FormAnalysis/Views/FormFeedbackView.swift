import SwiftUI

/// Post-set results sheet showing rep-by-rep quality breakdown and AI coaching text.
struct FormFeedbackView: View {

    let result: FormAnalysisResult
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summaryHeader
                    repBreakdownSection
                    if let aiText = result.aiCoachText {
                        aiCoachSection(aiText)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Form Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            statPill(icon: "figure.strengthtraining.traditional",
                     value: "\(result.repCount)",
                     label: "Reps")
            statPill(icon: "checkmark.seal.fill",
                     value: "\(result.goodRepCount)/\(result.repCount)",
                     label: "Good Form")
            statPill(icon: "chart.line.uptrend.xyaxis",
                     value: avgROM,
                     label: "Avg ROM")
        }
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var avgROM: String {
        guard !result.repQualities.isEmpty else { return "—" }
        let avg = result.repQualities.map { $0.romPercent }.reduce(0, +) / Double(result.repQualities.count)
        return "\(Int(avg))%"
    }

    // MARK: - Rep Breakdown

    private var repBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rep Breakdown")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            if result.repQualities.isEmpty {
                Text("No reps detected. Ensure your full body is visible to the camera and try again.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(result.repQualities, id: \.repNumber) { rep in
                    repRow(rep)
                }
            }
        }
        .cardStyle()
    }

    private func repRow(_ rep: RepQuality) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(rep.isGood ? AppTheme.success.opacity(0.2) : AppTheme.warning.opacity(0.2))
                    .frame(width: 34, height: 34)
                Text("\(rep.repNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(rep.isGood ? AppTheme.success : AppTheme.warning)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 14) {
                    Label("\(Int(rep.romPercent))% ROM", systemImage: "arrow.up.and.down")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Label(String(format: "%.1fs", rep.durationSeconds), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if !rep.flags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(rep.flags, id: \.self) { flag in
                            Text(flag)
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.warning)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.warning.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: rep.isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(rep.isGood ? AppTheme.success : AppTheme.warning)
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - AI Coach Section

    private func aiCoachSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Coach's Form Notes")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
