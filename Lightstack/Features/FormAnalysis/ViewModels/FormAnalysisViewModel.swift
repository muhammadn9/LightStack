import Foundation
import Combine

/// Orchestrates the form capture flow: start → collect poses → stop → analyze → AI feedback.
@MainActor
final class FormAnalysisViewModel: ObservableObject {

    // MARK: - Capture State

    enum CaptureState {
        case idle
        case capturing
        case analyzing
        case done(FormAnalysisResult)
        case failed(String)
    }

    @Published var captureState: CaptureState = .idle
    @Published var repCount: Int = 0
    @Published var latestPose: BodyPose?

    // MARK: - Services

    let poseService: PoseEstimationService
    private let repCounter: RepCounterService
    private let feedbackService: FormFeedbackService

    private var collectedPoses: [BodyPose] = []
    private var collectedPoses3D: [BodyPose3D] = []
    private var pose3DFrameCount = 0
    private var exerciseName: String = ""
    private var cancellables = Set<AnyCancellable>()

    init(
        poseService: PoseEstimationService,
        repCounter: RepCounterService,
        feedbackService: FormFeedbackService
    ) {
        self.poseService = poseService
        self.repCounter = repCounter
        self.feedbackService = feedbackService

        poseService.$latestPose
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pose in
                guard let self else { return }
                self.latestPose = pose
                if let pose, case .capturing = self.captureState {
                    self.collectedPoses.append(pose)
                    if self.collectedPoses.count % 30 == 0 {
                        self.updateLiveRepCount()
                    }
                }
            }
            .store(in: &cancellables)

        poseService.$latestPose3D
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pose3D in
                guard let self, let pose3D, case .capturing = self.captureState else { return }
                self.pose3DFrameCount += 1
                // Subsample to every 3rd frame (~10fps instead of 30fps)
                if self.pose3DFrameCount % 3 == 0 {
                    self.collectedPoses3D.append(pose3D)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func startCapture(exerciseName: String) {
        self.exerciseName = exerciseName
        collectedPoses = []
        collectedPoses3D = []
        pose3DFrameCount = 0
        repCount = 0
        captureState = .capturing
        poseService.requestPermissionAndStart()
    }

    func stopCaptureAndAnalyze() {
        poseService.stop()
        captureState = .analyzing

        let poses = collectedPoses
        let name = exerciseName

        let poses3D = collectedPoses3D

        Task {
            var result = repCounter.analyze(poses: poses, exerciseName: name)
            result.poses3D = poses3D

            await withCheckedContinuation { continuation in
                feedbackService.generateFeedback(for: result) { aiResult in
                    if case .success(let updated) = aiResult {
                        result = updated
                    }
                    continuation.resume()
                }
            }

            captureState = .done(result)
        }
    }

    func reset() {
        poseService.stop()
        collectedPoses = []
        collectedPoses3D = []
        pose3DFrameCount = 0
        repCount = 0
        captureState = .idle
    }

    // MARK: - Private

    private func updateLiveRepCount() {
        let interim = repCounter.analyze(poses: collectedPoses, exerciseName: exerciseName)
        repCount = interim.repCount
    }
}
