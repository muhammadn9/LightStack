import SwiftUI

/// Pre-set guide: animated 3D demo with camera, speed and scrubber controls, muscles worked,
/// set-up / perform / avoid steps, written instructions and reference photos.
struct FormGuideView: View {

    let exerciseName: String
    /// Called after the sheet closes when the user taps "Record my form". nil hides the button.
    var onStartRecording: (() -> Void)?

    @StateObject private var model: FormGuideViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("formGuide.hintShown") private var hintShown = false
    @State private var hintVisible = false
    @State private var showAllSteps = false
    @State private var enlargedPhoto: GuidePhoto?

    init(exerciseName: String, onStartRecording: (() -> Void)? = nil) {
        self.exerciseName = exerciseName
        self.onStartRecording = onStartRecording
        _model = StateObject(wrappedValue: FormGuideViewModel(exerciseName: exerciseName))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if let controller = model.controller {
                        stage(controller, height: min(max(geo.size.height * 0.46, 310), geo.size.height * 0.6))
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if model.hasMotion { musclesCard } else { noDemoNote }
                            content
                            Text("Photos: free-exercise-db (public domain)")
                                .font(AppTheme.caveat(11))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                    if onStartRecording != nil { recordBar }
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("formGuide.close")
                }
            }
        }
        .task(id: exerciseName) { await model.loadGuide() }
        .onAppear { model.resume(); showHintOnce() }
        .onDisappear { model.suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.resume() } else { model.suspend() }
        }
        .fullScreenCover(item: $enlargedPhoto) { photo in
            PhotoViewer(photo: photo)
        }
    }

    // MARK: - Stage

    private func stage(_ controller: GuideSceneController, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            cameraPills
            GuideSceneView(controller: controller, isDark: colorScheme == .dark, onInteraction: dismissHint)
                .overlay(alignment: .bottom) {
                    if hintVisible {
                        Text("Drag to rotate · Pinch to zoom")
                            .font(AppTheme.caveat(12, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 6)
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("3D demonstration of \(exerciseName)")
                .accessibilityHint("Drag to rotate, pinch to zoom, double tap to reset the view")
            transport
        }
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.border, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formGuide.stage")
    }

    private var cameraPills: some View {
        HStack(spacing: 6) {
            ForEach(GuideCameraPreset.allCases, id: \.self) { preset in
                let selected = model.camera == preset
                Button { model.select(camera: preset) } label: {
                    Text(preset.displayName)
                        .font(AppTheme.plexMono(12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? AppTheme.onAccent : AppTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .frame(maxWidth: .infinity)
                        .background(selected ? AppTheme.accent : AppTheme.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.accessibilityName) view")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("formGuide.camera.\(preset.rawValue)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var transport: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.phaseLabel)
                    .font(AppTheme.playfair(17, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("formGuide.phase")
                Spacer()
                Button { model.toggleSpeed() } label: {
                    Text(model.speed == 1 ? "1×" : "0.5×")
                        .font(AppTheme.plexMono(13, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(AppTheme.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed")
                .accessibilityValue(model.speed == 1 ? "Normal" : "Half speed")
                .accessibilityIdentifier("formGuide.speed")
            }
            HStack(spacing: 10) {
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("formGuide.playPause")
                scrubber
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var scrubber: some View {
        let phases = model.motion?.phases ?? []
        return ZStack(alignment: .bottom) {
            Slider(value: Binding(get: { Double(model.progress) },
                                  set: { model.scrub(to: Float($0)) }), in: 0...1)
                .tint(AppTheme.accent)
                .accessibilityLabel("Rep position")
                .accessibilityValue(model.phaseLabel)
                .accessibilityIdentifier("formGuide.scrubber")
            GeometryReader { geo in
                ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                    Capsule()
                        .fill(AppTheme.textSecondary.opacity(0.7))
                        .frame(width: 2, height: 6)
                        .position(x: 14 + CGFloat(phase.progress) * max(geo.size.width - 28, 1),
                                  y: geo.size.height - 3)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 38)
    }

    // MARK: - Muscles

    private var musclesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Muscles worked")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                legendDot(primaryColor, "Primary")
                legendDot(secondaryColor, "Secondary")
            }
            FlowLayout(spacing: 8) {
                ForEach(model.primaryMuscles, id: \.self) { chip($0, color: primaryColor, role: "Primary") }
                ForEach(model.secondaryMuscles, id: \.self) { chip($0, color: secondaryColor, role: "Secondary") }
            }
            Text("Tap a muscle to isolate it on the figure.")
                .font(AppTheme.caveat(12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var palette: MannequinPalette { .make(dark: colorScheme == .dark) }
    private var primaryColor: Color { Color(uiColor: palette.primary) }
    private var secondaryColor: Color { Color(uiColor: palette.secondary) }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(AppTheme.caveat(11)).foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityHidden(true)
    }

    private func chip(_ muscle: MuscleGroup, color: Color, role: String) -> some View {
        let selected = model.isolatedMuscle == muscle
        return Button { model.toggleIsolate(muscle) } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(muscle.displayName)
                    .font(AppTheme.plexMono(13, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? color.opacity(0.28) : AppTheme.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(selected ? color : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(muscle.displayName), \(role.lowercased())")
        .accessibilityHint(selected ? "Shows all muscles again" : "Shows only this muscle on the figure")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("formGuide.muscle.\(muscle.rawValue)")
    }

    private var noDemoNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "cube.transparent")
                .foregroundStyle(AppTheme.textSecondary)
            Text("No 3D demo for this exercise yet")
                .font(AppTheme.caveat(15))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("formGuide.noDemo")
    }

    // MARK: - Content cards

    @ViewBuilder private var content: some View {
        if let motion = model.motion {
            stepsCard("Set up", icon: "checklist", steps: motion.setupSteps, tint: AppTheme.accent, id: "formGuide.setup")
            stepsCard("Perform", icon: "figure.strengthtraining.traditional", steps: motion.cues,
                      tint: AppTheme.accent, id: "formGuide.perform")
            stepsCard("Avoid", icon: "exclamationmark.triangle.fill", steps: motion.commonMistakes,
                      tint: AppTheme.warning, id: "formGuide.avoid")
        }
        if let guide = model.guide {
            instructionsCard(guide)
            photosCard
        }
    }

    private func stepsCard(_ title: String, icon: String, steps: [String], tint: Color, id: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                numberedRow(index + 1, step, tint: tint)
                    .accessibilityIdentifier("\(id).\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    private func numberedRow(_ number: Int, _ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(AppTheme.plexMono(12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(AppTheme.caveat(15))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func instructionsCard(_ guide: ExerciseGuide) -> some View {
        let collapsible = guide.instructions.count > 4
        let shown = collapsible && !showAllSteps ? Array(guide.instructions.prefix(4)) : guide.instructions
        return VStack(alignment: .leading, spacing: 12) {
            Label("Step by step", systemImage: "list.number")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("howToHeader")
            ForEach(Array(shown.enumerated()), id: \.offset) { index, step in
                numberedRow(index + 1, step, tint: AppTheme.accent)
                    .accessibilityIdentifier("howToStep.\(index)")
            }
            if collapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showAllSteps.toggle() }
                } label: {
                    Text(showAllSteps ? "Show fewer" : "Show all \(guide.instructions.count) steps")
                        .font(AppTheme.plexMono(13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("formGuide.showAllSteps")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Photos

    @ViewBuilder private var photosCard: some View {
        if model.startImage != nil || model.endImage != nil {
            VStack(alignment: .leading, spacing: 12) {
                Label("Reference photos", systemImage: "photo.on.rectangle")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    photoTile("Start", model.startImage)
                    photoTile("End", model.endImage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("howToPhotos")
        }
    }

    @ViewBuilder private func photoTile(_ label: String, _ image: UIImage?) -> some View {
        if let image {
            Button { enlargedPhoto = GuidePhoto(label: "\(label) position", image: image) } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        Text(label)
                            .font(AppTheme.plexMono(11, weight: .bold))
                            .foregroundStyle(AppTheme.onAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.accent, in: Capsule())
                            .padding(6)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label) position photo of \(exerciseName)")
            .accessibilityHint("Double tap to enlarge")
            .accessibilityIdentifier("formGuide.photo.\(label.lowercased())")
        }
    }

    // MARK: - Record bar

    private var recordBar: some View {
        Button {
            dismiss()
            onStartRecording?()
        } label: {
            Label("Record my form", systemImage: "camera.fill")
                .font(AppTheme.caveat(16, weight: .bold))
                .foregroundStyle(AppTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.background.shadow(.drop(color: .black.opacity(0.12), radius: 6, y: -2)))
        .accessibilityLabel("Record my form")
        .accessibilityIdentifier("formGuide.record")
    }

    // MARK: - Hint

    private func showHintOnce() {
        guard model.hasMotion, !hintShown, !hintVisible else { return }
        withAnimation { hintVisible = true }
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            dismissHint()
        }
    }

    private func dismissHint() {
        guard hintVisible else { return }
        withAnimation(.easeOut(duration: 0.4)) { hintVisible = false }
        hintShown = true
    }
}

// MARK: - Photo viewer

struct GuidePhoto: Identifiable {
    let id = UUID()
    let label: String
    let image: UIImage
}

/// Full-screen photo with pinch zoom.
private struct PhotoViewer: View {
    let photo: GuidePhoto
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnificationGesture()
                    .onChanged { scale = min(max(lastScale * $0, 1), 5) }
                    .onEnded { _ in lastScale = scale })
                .onTapGesture(count: 2) { withAnimation { scale = 1; lastScale = 1 } }
                .accessibilityLabel(photo.label)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(16)
            }
            .accessibilityLabel("Close photo")
            .accessibilityIdentifier("formGuide.photoClose")
        }
    }
}
