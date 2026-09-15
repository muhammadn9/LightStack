import SwiftUI
import AVFoundation

/// Full-screen camera view with skeleton overlay and form capture controls.
/// Presented as a fullScreenCover from ActiveWorkoutView.
struct FormCaptureView: View {

    @ObservedObject var viewModel: FormAnalysisViewModel
    @Environment(\.dismiss) var dismiss

    let exerciseName: String
    let onComplete: (FormAnalysisResult) -> Void

    @State private var captureStartTime = Date()
    @State private var countdown = 3
    @State private var countdownStarted = false

    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: viewModel.poseService.captureSession)
                .ignoresSafeArea()

            SkeletonOverlayView(pose: viewModel.latestPose)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding()

            if viewModel.permissionDenied {
                permissionDeniedOverlay
            } else if lowDetectionVisible {
                lowDetectionTip
            }

            if countdown > 0 {
                countdownOverlay
            }
        }
        .onAppear {
            guard !countdownStarted else { return }
            countdownStarted = true
            viewModel.reset()
            viewModel.startCamera(exerciseName: exerciseName)
        }
        .onReceive(countdownTimer) { _ in
            guard countdown > 0 else { return }
            countdown -= 1
            if countdown == 0 {
                captureStartTime = Date()
                viewModel.beginCollecting()
            }
        }
        .onChange(of: captureIsDone) { _, done in
            if done, case .done(let result) = viewModel.captureState {
                onComplete(result)
                dismiss()
            }
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button(action: {
                viewModel.reset()
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            }
            Spacer()
            Text(exerciseName)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
            Spacer()
            Button(action: { viewModel.flipCamera() }) {
                Image(systemName: "camera.rotate")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            }
        }
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.green)
                Text("Reps: \(viewModel.repCount)")
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(.black.opacity(0.6))
            .clipShape(Capsule())

            Button(action: {
                viewModel.stopCaptureAndAnalyze()
            }) {
                HStack(spacing: 10) {
                    if captureIsAnalyzing {
                        ProgressView().tint(.white)
                        Text("Analyzing…")
                    } else {
                        Image(systemName: "stop.circle.fill")
                        Text("Done — Analyze Form")
                    }
                }
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.successActionGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(captureIsAnalyzing)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private var permissionDeniedOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.slash")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                Text("Camera Access Required")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Enable camera access in Settings to use form analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(.white)
                .clipShape(Capsule())
            }
            .padding(32)
        }
    }

    private var countdownOverlay: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.55))
                .frame(width: 160, height: 160)
            Text("\(countdown)")
                .font(AppTheme.plexMono(96, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 8)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: countdown)
    }

    // MARK: - Low Detection Guidance

    private var lowDetectionVisible: Bool {
        guard Date().timeIntervalSince(captureStartTime) > 3.0 else { return false }
        let detectedCount = viewModel.latestPose.map { pose in
            pose.confidences.values.filter { $0 > 0.15 }.count
        } ?? 0
        return detectedCount < 6
    }

    private var lowDetectionTip: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
            Text("Body Not Detected")
                .font(.headline.bold())
                .foregroundStyle(.white)
            Text("Ensure your full body is visible. For lying exercises (e.g. bench press), position the camera further away and to the side.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 30)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.4), value: lowDetectionVisible)
    }

    // MARK: - Helpers

    private var captureIsDone: Bool {
        if case .done = viewModel.captureState { return true }
        return false
    }

    private var captureIsAnalyzing: Bool {
        if case .analyzing = viewModel.captureState { return true }
        return false
    }
}
