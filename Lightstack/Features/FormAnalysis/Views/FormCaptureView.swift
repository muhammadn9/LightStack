import SwiftUI
import AVFoundation

/// Full-screen recording flow: set the phone up, count down, record, hand the result back.
/// Presented as a fullScreenCover from ActiveWorkoutView. Text is large because the phone is propped
/// a few metres away.
struct FormCaptureView: View {

    @ObservedObject var viewModel: FormAnalysisViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let exerciseName: String
    let onComplete: (FormSessionResult) -> Void

    @State private var completed = false
    @State private var idleTimerWasDisabled = false

    var body: some View {
        ZStack {
            background
            SkeletonOverlayView(frame: viewModel.latestFrame,
                                aspectRatio: viewModel.aspectRatio,
                                highlighted: viewModel.highlightedJoints)
                .ignoresSafeArea()

            phaseContent

            if viewModel.permissionDenied { permissionDeniedOverlay }
            if viewModel.phase == .analyzing { analyzingOverlay }
        }
        .onAppear {
            idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.prepare(exerciseName: exerciseName)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled
            if !completed { viewModel.cancel() }
        }
        .onChange(of: viewModel.phase) { _, phase in
            guard phase == .done, !completed, let result = viewModel.result else { return }
            completed = true
            onComplete(result)
            dismiss()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { viewModel.handleInterruption() }
        }
    }

    // MARK: Layers

    @ViewBuilder private var background: some View {
        if let session = viewModel.source.previewSession {
            CameraPreviewView(session: session, source: viewModel.source)
                .ignoresSafeArea()
        } else {
            Color(white: 0.08).ignoresSafeArea()   // stands in for the camera when there is none
        }
    }

    @ViewBuilder private var phaseContent: some View {
        switch viewModel.phase {
        case .setup, .failed:
            setupLayer
        case .countdown(let remaining):
            countdownLayer(remaining)
        case .recording:
            recordingLayer
        case .analyzing, .done:
            Color.clear
        }
    }

    // MARK: Setup

    private var setupLayer: some View {
        VStack(spacing: 16) {
            topBar
            Spacer()
            if let notice = viewModel.notice { noticeCard(notice) }
            statusCard
            startButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    private var topBar: some View {
        HStack {
            circleButton(systemName: "xmark", label: "Close", id: "formCapture.close") {
                viewModel.cancel()
                completed = true   // already cleaned up
                dismiss()
            }
            Spacer()
            Text(exerciseName)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55))
                .clipShape(Capsule())
            Spacer()
            circleButton(systemName: "camera.rotate", label: "Flip camera", id: "formCapture.flip") {
                viewModel.flipCamera()
            }
        }
    }

    private func circleButton(systemName: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: AppTheme.minTouchSize, height: AppTheme.minTouchSize)
                .background(.black.opacity(0.55))
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var statusCard: some View {
        let status = viewModel.setupStatus
        let ready = status.isReady
        let tracked = viewModel.profile.isTracked
        let tint = ready ? AppTheme.accent : AppTheme.warning
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : (tracked ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                .font(.title)
                .foregroundStyle(tint)
            Text(status.message)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(tint.opacity(0.8), lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("formCapture.setupStatus")
    }

    private func noticeCard(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.warning.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var startButton: some View {
        let ready = viewModel.setupStatus.isReady || !viewModel.profile.isTracked
        return Button {
            viewModel.startCountdown()
        } label: {
            Text(ready ? "Start" : "Start anyway")
                .font(.title.bold())
                .foregroundStyle(AppTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(ready ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.warning))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .accessibilityIdentifier("formCapture.start")
    }

    // MARK: Countdown

    private func countdownLayer(_ remaining: Int) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Get ready")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("\(remaining)")
                    .font(.system(size: 220, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Text("Tap anywhere to cancel")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .shadow(color: .black.opacity(0.6), radius: 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.cancelCountdown() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starting in \(remaining). Tap to cancel.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("formCapture.countdown")
    }

    // MARK: Recording

    private var recordingLayer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle().fill(Color.red).frame(width: 18, height: 18)
                Text(Self.clock(viewModel.elapsed))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.black.opacity(0.6))
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording, \(Int(viewModel.elapsed)) seconds")

            Spacer()

            if viewModel.profile.isTracked {
                VStack(spacing: 0) {
                    Text("\(viewModel.liveRepCount)")
                        .font(.system(size: 190, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("formCapture.repCount")
                    Text("REPS")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
                .frame(maxWidth: 320)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 28))
            } else {
                Text("Recording")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            Spacer()

            Button {
                viewModel.finish()
            } label: {
                Text("Done")
                    .font(.title.bold())
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(AppTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .accessibilityIdentifier("formCapture.done")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: Overlays

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Analyzing your set…")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
        }
        .accessibilityIdentifier("formCapture.analyzing")
    }

    private var permissionDeniedOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.slash")
                    .scaledSymbol(size: 52)
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
                Button("Close") {
                    viewModel.cancel()
                    completed = true
                    dismiss()
                }
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityIdentifier("formCapture.permissionClose")
            }
            .padding(32)
        }
    }
}
