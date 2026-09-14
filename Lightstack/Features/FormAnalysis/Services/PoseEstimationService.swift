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
    private(set) var currentCameraPosition: AVCaptureDevice.Position = .back

    @available(iOS 17.0, *)
    private lazy var bodyPose3DRequest = VNDetectHumanBodyPose3DRequest()

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
            captureSession.sessionPreset = .high

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
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

    func flipCamera() {
        let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

        captureSession.beginConfiguration()
        // Remove existing input
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
            currentCameraPosition = newPosition
        }
        captureSession.commitConfiguration()
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

        let orientation: CGImagePropertyOrientation = (currentCameraPosition == .front) ? .leftMirrored : .right
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        // Batch 2D and 3D requests in a single perform() call to avoid double-perform failures
        var requests: [VNRequest] = [bodyPoseRequest]
        if #available(iOS 17.0, *) {
            requests.append(bodyPose3DRequest)
        }

        do {
            try handler.perform(requests)
        } catch {
            return
        }

        // Process 2D result
        if let observation = bodyPoseRequest.results?.first {
            let pose = buildBodyPose(from: observation)
            DispatchQueue.main.async { [weak self] in
                self?.latestPose = pose
            }
        }

        // Process 3D result
        if #available(iOS 17.0, *) {
            if let obs3D = bodyPose3DRequest.results?.first {
                let pose3D = buildBodyPose3D(from: obs3D)
                DispatchQueue.main.async { [weak self] in
                    self?.latestPose3D = pose3D
                }
            }
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
    private func buildBodyPose3D(from observation: VNHumanBodyPose3DObservation) -> BodyPose3D {
        let mapping: [(String, VNHumanBodyPose3DObservation.JointName)] = [
            ("neck",          .centerShoulder),
            ("leftShoulder",  .leftShoulder),
            ("rightShoulder", .rightShoulder),
            ("leftElbow",     .leftElbow),
            ("rightElbow",    .rightElbow),
            ("leftWrist",     .leftWrist),
            ("rightWrist",    .rightWrist),
            ("leftHip",       .leftHip),
            ("rightHip",      .rightHip),
            ("leftKnee",      .leftKnee),
            ("rightKnee",     .rightKnee),
            ("leftAnkle",     .leftAnkle),
            ("rightAnkle",    .rightAnkle),
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
