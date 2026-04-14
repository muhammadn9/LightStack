import SwiftUI
import simd

/// Pre-recording form guide: shows an animated 3D ideal-form skeleton
/// with equipment, quick form tips, and a "Start Recording" action.
struct ExerciseFormDemoView: View {

    let exerciseName: String
    /// Called when the user taps "Start Recording". nil = shown standalone (no camera chain).
    var onStartRecording: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var frames: [[String: simd_float3]] { IdealFormData.keyframes(for: exerciseName) }
    private var tips: [String] { IdealFormData.tips(for: exerciseName) }
    private var equipment: EquipmentType { EquipmentType.equipment(for: exerciseName) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    skeletonSection
                    tipsSection
                    if onStartRecording != nil {
                        actionButtons
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Sections

    private var skeletonSection: some View {
        ZStack(alignment: .bottomLeading) {
            SkeletonSceneView(
                frames: frames,
                tintColor: UIColor(AppTheme.accent),
                equipmentType: equipment,
                fps: 4
            )
            .frame(maxWidth: .infinity)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ideal Form")
                    .font(AppTheme.caveat(11))
                    .foregroundStyle(AppTheme.textSecondary)
                Text("Drag to rotate • Pinch to zoom")
                    .font(AppTheme.caveat(10))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Form Cues")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(AppTheme.plexMono(12, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 20)
                    Text(tip)
                        .font(AppTheme.caveat(15))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardStyle()
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: {
                dismiss()
                onStartRecording?()
            }) {
                Label("Start Recording", systemImage: "camera.fill")
                    .font(AppTheme.caveat(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }

            Button("Skip Demo") {
                dismiss()
                onStartRecording?()
            }
            .font(AppTheme.caveat(14))
            .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}
