import SwiftUI
import SceneKit

/// Post-set results sheet showing rep-by-rep quality breakdown and AI coaching text.
struct FormFeedbackView: View {

    let result: FormAnalysisResult
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryHeader
                    InkDivider()
                    repBreakdownSection
                    InkDivider()
                    replay3DSection
                    if let aiText = result.aiCoachText {
                        InkDivider()
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
                .font(AppTheme.plexMono(18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
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
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            if result.repQualities.isEmpty {
                Text("No reps detected. Ensure your full body is visible to the camera and try again.")
                    .font(AppTheme.caveat(14))
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

    // MARK: - 3D Replay Section

    private var replay3DSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3D Form Replay")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    Text("Your Form")
                        .font(AppTheme.caveat(12, weight: .bold))
                        .foregroundStyle(AppTheme.accentSecondary)
                    if result.poses3D.isEmpty {
                        unavailableBox("No 3D data\n(iOS 17+ required)")
                    } else {
                        SkeletonSceneView(
                            frames: result.poses3D.map { $0.joints },
                            tintColor: UIColor(.green)
                        )
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                }

                VStack(spacing: 6) {
                    Text("Ideal Form")
                        .font(AppTheme.caveat(12, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    SkeletonSceneView(
                        frames: IdealFormData.keyframes(for: result.exerciseName),
                        tintColor: UIColor(AppTheme.accent),
                        equipmentType: EquipmentType.equipment(for: result.exerciseName)
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
            }
        }
        .cardStyle()
    }

    private func unavailableBox(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - AI Coach Section

    private func aiCoachSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Coach's Form Notes")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            InkDivider()
            Text(text)
                .font(AppTheme.caveat(15))
                .foregroundStyle(AppTheme.textPrimary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .cardStyle()
    }
}
