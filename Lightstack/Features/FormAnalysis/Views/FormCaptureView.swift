import SwiftUI
import AVFoundation

/// Full-screen camera view with skeleton overlay and form capture controls.
/// Presented as a fullScreenCover from ActiveWorkoutView.
struct FormCaptureView: View {

    @ObservedObject var viewModel: FormAnalysisViewModel
    @Environment(\.dismiss) var dismiss

    let exerciseName: String
    let onComplete: (FormAnalysisResult) -> Void

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

            if viewModel.poseService.permissionDenied {
                permissionDeniedOverlay
            }
        }
        .onAppear {
            viewModel.reset()
            viewModel.startCapture(exerciseName: exerciseName)
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
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.75, blue: 0.2),
                                 Color(red: 0.1, green: 0.5, blue: 0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
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
