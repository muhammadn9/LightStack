import SwiftUI
import simd

/// Pre-recording form guide: shows an animated 3D ideal-form skeleton
/// with equipment, quick form tips, and a "Start Recording" action.
struct ExerciseFormDemoView: View {

    let exerciseName: String
    /// Called when the user taps "Start Recording". nil = shown standalone (no camera chain).
    var onStartRecording: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showEndPhoto = false
    @State private var photosPaused = false

    private var frames: [[String: simd_float3]] { IdealFormData.keyframes(for: exerciseName) }
    private var tips: [String] { IdealFormData.tips(for: exerciseName) }
    private var equipment: EquipmentType { EquipmentType.equipment(for: exerciseName) }
    @State private var guide: ExerciseGuide?
    @State private var startImage: UIImage?
    @State private var endImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            skeletonSection
                            if let guide {
                                howToSection(guide)
                            }
                            tipsSection
                        }
                        .padding(.bottom, 8)
                    }
                    if onStartRecording != nil {
                        actionButtons
                    }
                }
            }
            .task(id: exerciseName) { await loadGuide() }
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

    /// Resolves the guide and decodes its photos once, off the main actor.
    private func loadGuide() async {
        let name = exerciseName
        let loaded = await Task.detached(priority: .userInitiated) { () -> (ExerciseGuide, UIImage?, UIImage?)? in
            guard let guide = ExerciseGuideLibrary.shared.guide(for: name) else { return nil }
            let start = guide.imageFiles.first.flatMap { ExerciseGuideLibrary.image(named: $0) }
            let end = guide.imageFiles.dropFirst().first.flatMap { ExerciseGuideLibrary.image(named: $0) }
            return (guide, start, end)
        }.value
        guard !Task.isCancelled else { return }
        guide = loaded?.0
        startImage = loaded?.1
        endImage = loaded?.2
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

    private func howToSection(_ guide: ExerciseGuide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How To")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("howToHeader")

            photoArea(guide)

            ForEach(Array(guide.instructions.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(AppTheme.plexMono(12, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 20)
                    Text(step)
                        .font(AppTheme.caveat(15))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("howToStep.\(index)")
            }

            Text("Photos: free-exercise-db (public domain)")
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func photoArea(_ guide: ExerciseGuide) -> some View {
        let start = startImage
        let end = endImage
        if start != nil || end != nil {
            let showingEnd = showEndPhoto && end != nil
            ZStack(alignment: .topLeading) {
                if let start {
                    Image(uiImage: start)
                        .resizable()
                        .scaledToFit()
                        .opacity(showingEnd ? 0 : 1)
                        .accessibilityLabel("Start position photo for \(exerciseName)")
                        .accessibilityHidden(showingEnd)
                }
                if let end {
                    Image(uiImage: end)
                        .resizable()
                        .scaledToFit()
                        .opacity(showingEnd ? 1 : 0)
                        .accessibilityLabel("End position photo for \(exerciseName)")
                        .accessibilityHidden(!showingEnd)
                }
                Text(showingEnd ? "End" : "Start")
                    .font(AppTheme.plexMono(11, weight: .bold))
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                    .padding(8)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .contentShape(Rectangle())
            .onTapGesture {
                if reduceMotion || end == nil {
                    withAnimation(.easeInOut(duration: 0.3)) { showEndPhoto.toggle() }
                } else {
                    photosPaused.toggle()
                }
            }
            .accessibilityIdentifier("howToPhotos")
            .accessibilityHint(reduceMotion ? "Double tap to switch between start and end photos"
                                            : "Double tap to pause or resume")
            .task(id: autoplayKey(hasEnd: end != nil)) {
                guard !reduceMotion, !photosPaused, end != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if Task.isCancelled { break }
                    withAnimation(.easeInOut(duration: 0.4)) { showEndPhoto.toggle() }
                }
            }
        }
    }

    /// Restarts the autoplay loop when pausing or reduce-motion changes.
    private func autoplayKey(hasEnd: Bool) -> String {
        "\(reduceMotion)-\(photosPaused)-\(hasEnd)"
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(AppTheme.onAccent)
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
