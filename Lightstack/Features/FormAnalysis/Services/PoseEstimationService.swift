import AVFoundation
import Vision
import Combine
import simd

/// Manages the camera capture pipeline and runs VNDetectHumanBodyPoseRequest on each frame.
/// Publishes BodyPose values via `$latestPose` and (iOS 17+) BodyPose3D via `$latestPose3D`.
final class PoseEstimationService: NSObject, ObservableObject {

    // MARK: - Published

    @Published private(set) var latestPose: BodyPose?
    @Published private(set) var latestPose3D: BodyPose3D?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var permissionDenied: Bool = false

    // MARK: - Camera Session (exposed for preview layer)

    let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.lightstack.pose", qos: .userInteractive)
    private lazy var bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    private var isConfigured = false

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
        if !isConfigured {
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
            isConfigured = true
        }

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

        // .leftMirrored corrects front camera landscape buffers to portrait-space coordinates
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .leftMirrored,
            options: [:]
        )

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

        if #available(iOS 17.0, *) {
            collectPose3D(handler: handler)
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

    @available(iOS 17.0, *)
    private func collectPose3D(handler: VNImageRequestHandler) {
        let request = VNDetectHumanBodyPose3DRequest()
        try? handler.perform([request])
        guard let observation = request.results?.first else { return }
        let pose3D = buildBodyPose3D(from: observation)
        DispatchQueue.main.async { [weak self] in
            self?.latestPose3D = pose3D
        }
    }

    @available(iOS 17.0, *)
    private func buildBodyPose3D(from observation: VNHumanBodyPose3DObservation) -> BodyPose3D {
        let mapping: [(String, VNHumanBodyPose3DObservation.JointName)] = [
            ("neck",          .neck1),
            ("leftShoulder",  .leftShoulder),
            ("rightShoulder", .rightShoulder),
            ("leftElbow",     .leftForearm),
            ("rightElbow",    .rightForearm),
            ("leftWrist",     .leftHand),
            ("rightWrist",    .rightHand),
            ("leftHip",       .leftUpLeg),
            ("rightHip",      .rightUpLeg),
            ("leftKnee",      .leftLeg),
            ("rightKnee",     .rightLeg),
            ("leftAnkle",     .leftFoot),
            ("rightAnkle",    .rightFoot),
        ]

        var joints: [String: simd_float3] = [:]
        for (name, jointName) in mapping {
            if let point = try? observation.recognizedPoint(jointName) {
                let col3 = point.position.columns.3
                joints[name] = simd_float3(col3.x, col3.y, col3.z)
            }
        }

        return BodyPose3D(timestamp: CACurrentMediaTime(), joints: joints)
    }
}
