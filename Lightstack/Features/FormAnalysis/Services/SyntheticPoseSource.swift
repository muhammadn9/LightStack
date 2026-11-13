#if DEBUG
import AVFoundation
import Combine

/// Stand-in for the camera in UI tests (the simulator has none): a standing figure that holds still for
/// 2 s, then does a lateral raise every 2 s, forever.
@MainActor
final class SyntheticPoseSource: PoseSource {

    /// The exercise the synthetic figure performs; used to pick the movement profile in UI tests.
    nonisolated static let syntheticExerciseName = "Lateral Raise"
    nonisolated static let frameRate = 15.0
    nonisolated static let aspect = 9.0 / 16.0

    private let frames = PassthroughSubject<PoseFrame?, Never>()
    private let denied = CurrentValueSubject<Bool, Never>(false)
    private var timer: Timer?
    private var clockStart = Date()
    private var recordingStart: Date?

    var framePublisher: AnyPublisher<PoseFrame?, Never> { frames.eraseToAnyPublisher() }
    var aspectRatio: Double { Self.aspect }
    var previewSession: AVCaptureSession? { nil }
    var permissionDenied: Bool { false }
    var permissionDeniedPublisher: AnyPublisher<Bool, Never> { denied.eraseToAnyPublisher() }
    var interruptionPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var cameraPosition: AVCaptureDevice.Position { .back }

    func start() {
        stop()
        clockStart = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Self.frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func flipCamera() {}

    func startRecording() { recordingStart = Date() }

    func stopRecording() async -> URL? {
        recordingStart = nil
        return nil
    }

    private func tick() {
        let now = Date()
        let time = now.timeIntervalSince(recordingStart ?? clockStart)
        frames.send(Self.frame(at: time))
    }

    // MARK: Figure

    /// Shoulder angle (degrees between torso and upper arm): 15 at rest, 80 at the top of a raise.
    nonisolated static func shoulderAngle(at time: TimeInterval) -> Double {
        let rest = 15.0, top = 80.0, period = 2.0, stillFor = 2.0
        guard time > stillFor else { return rest }
        let phase = (time - stillFor) / period * 2 * .pi
        return rest + (top - rest) * (0.5 - 0.5 * cos(phase))
    }

    /// The figure at `time` seconds: front-on, arms swinging out sideways.
    nonisolated static func frame(at time: TimeInterval) -> PoseFrame {
        let theta = shoulderAngle(at: time) * .pi / 180
        let confidence = 0.95
        var joints: [BodyJoint: PosePoint] = [
            .nose: PosePoint(x: 0.5, y: 0.24, confidence: confidence),
            .neck: PosePoint(x: 0.5, y: 0.30, confidence: confidence)
        ]
        let upperArm = 0.11, forearm = 0.09
        for (sign, side) in [(1.0, BodySide.left), (-1.0, BodySide.right)] {
            let sx = 0.5 + sign * 0.10
            let sy = 0.32
            // Offsets are in height units, so x is divided by the aspect ratio to stay geometrically true.
            let dx = sign * sin(theta) / aspect, dy = cos(theta)
            let elbow = (x: sx + dx * upperArm, y: sy + dy * upperArm)
            let wrist = (x: elbow.x + dx * forearm, y: elbow.y + dy * forearm)
            let l = side == .left
            joints[l ? .leftShoulder : .rightShoulder] = PosePoint(x: sx, y: sy, confidence: confidence)
            joints[l ? .leftElbow : .rightElbow] = PosePoint(x: elbow.x, y: elbow.y, confidence: confidence)
            joints[l ? .leftWrist : .rightWrist] = PosePoint(x: wrist.x, y: wrist.y, confidence: confidence)
            joints[l ? .leftHip : .rightHip] = PosePoint(x: sx, y: 0.58, confidence: confidence)
            joints[l ? .leftKnee : .rightKnee] = PosePoint(x: sx, y: 0.74, confidence: confidence)
            joints[l ? .leftAnkle : .rightAnkle] = PosePoint(x: sx, y: 0.90, confidence: confidence)
        }
        return PoseFrame(time: time, joints: joints)
    }
}
#endif
