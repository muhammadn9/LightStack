import AVFoundation
import Vision
import Combine

/// Manages the camera capture pipeline and runs VNDetectHumanBodyPoseRequest on each frame.
/// Publishes BodyPose values via `$latestPose`.
final class PoseEstimationService: NSObject, ObservableObject {

    // MARK: - Published

    @Published private(set) var latestPose: BodyPose?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var permissionDenied: Bool = false

    // MARK: - Camera Session (exposed for preview layer)

    let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.lightstack.pose", qos: .userInteractive)
    private lazy var bodyPoseRequest = VNDetectHumanBodyPoseRequest()

    // MARK: - Public API

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureAndStart() }
                    else { self?.permissionDenied = true }
                }
            }
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    // MARK: - Setup

    private func configureAndStart() {
        guard !captureSession.isRunning else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()

        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PoseEstimationService: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([bodyPoseRequest])
        } catch {
            return
        }

        guard let observation = bodyPoseRequest.results?.first else { return }
        let pose = buildBodyPose(from: observation)

        DispatchQueue.main.async { [weak self] in
            self?.latestPose = pose
        }
    }

    private func buildBodyPose(from observation: VNHumanBodyPoseObservation) -> BodyPose {
        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle,
            .neck, .nose
        ]

        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        var confidences: [VNHumanBodyPoseObservation.JointName: Float] = [:]

        for name in jointNames {
            if let point = try? observation.recognizedPoint(name) {
                joints[name] = CGPoint(x: point.x, y: point.y)
                confidences[name] = point.confidence
            }
        }

        return BodyPose(
            timestamp: CACurrentMediaTime(),
            joints: joints,
            confidences: confidences
        )
    }
}
