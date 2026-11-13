import AVFoundation
import Vision
import UIKit

/// All AVFoundation work for `CameraPoseSource`. Everything except the callbacks runs on one serial
/// session queue (configuration, start/stop, flipping, frame handling, recording). Vision runs on a
/// second queue so a slow pose request can never make the recording miss a frame.
final class CaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    // Callbacks, set once before `start()`; always invoked on the main thread.
    var onFrame: (@Sendable (PoseFrame) -> Void)?
    var onAspect: (@Sendable (Double) -> Void)?
    var onPosition: (@Sendable (AVCaptureDevice.Position) -> Void)?
    var onPermissionDenied: (@Sendable () -> Void)?
    var onInterrupted: (@Sendable () -> Void)?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.lightstack.form.session")
    private let visionQueue = DispatchQueue(label: "com.lightstack.form.vision", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()

    // Session-queue confined.
    private var position: AVCaptureDevice.Position
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []
    private var captureAngle: CGFloat?
    private var rotationFrozen = false
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastAspect = 0.0
    private var visionBusy = false
    private var notificationTokens: [NSObjectProtocol] = []

    // Recording, session-queue confined.
    private var recordingRequested = false
    private var recordStart: CMTime?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var writerURL: URL?
    private var writerSize = CGSize.zero
    private var lastPTS = CMTime.invalid

    // Vision-queue confined.
    private var previousCenter: PersonSelector.Center?
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    init(position: AVCaptureDevice.Position) {
        self.position = position
        super.init()
        let center = NotificationCenter.default
        let interrupted: (Notification) -> Void = { [weak self] _ in self?.notifyMain { $0.onInterrupted?() } }
        notificationTokens = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil, using: interrupted),
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil, using: interrupted)
        ]
    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Lifecycle

    func start() {
        queue.async { [self] in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                startAuthorized()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    self.queue.async {
                        if granted { self.startAuthorized() } else { self.notifyMain { $0.onPermissionDenied?() } }
                    }
                }
            default:
                notifyMain { $0.onPermissionDenied?() }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?) {
        queue.async { [self] in
            previewLayer = layer
            if configured { rebuildCoordinator() }
        }
    }

    private func startAuthorized() {
        if !configured {
            guard configure() else { return }
            applyConnectionSettings()
            rebuildCoordinator()
            notifyMain { [position] in $0.onPosition?(position) }
        }
        if !session.isRunning { session.startRunning() }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        let inputAdded = addInput(for: position)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        let outputAdded = session.canAddOutput(output)
        if outputAdded { session.addOutput(output) }
        session.commitConfiguration()
        configured = inputAdded && outputAdded
        return configured
    }

    /// Adds the camera for `target` (falling back to any camera). Caller owns begin/commitConfiguration.
    private func addInput(for target: AVCaptureDevice.Position) -> Bool {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: target)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) else {
            return false
        }
        session.addInput(newInput)
        input = newInput
        position = device.position == .unspecified ? target : device.position
        return true
    }

    // MARK: Flip

    func flip() {
        queue.async { [self] in
            let target: AVCaptureDevice.Position = position == .front ? .back : .front
            guard configured else {
                position = target
                notifyMain { $0.onPosition?(target) }
                return
            }
            session.beginConfiguration()
            let old = input
            if let old { session.removeInput(old) }
            if !addInput(for: target), let old, session.canAddInput(old) {
                session.addInput(old)
                input = old
            }
            session.commitConfiguration()
            applyConnectionSettings()
            rebuildCoordinator()
            visionQueue.async { self.previousCenter = nil }
            notifyMain { [position] in $0.onPosition?(position) }
        }
    }

    // MARK: Orientation (follows gravity, not the UI)

    /// Rotation coordinator for the current camera. Its capture angle makes buffers upright with respect
    /// to gravity however the phone is propped; its preview angle does the same for the preview layer.
    private func rebuildCoordinator() {
        observations.removeAll()
        coordinator = nil
        guard let device = input?.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        self.coordinator = coordinator
        observations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                self?.queue.async { self?.captureAngleChanged(angle) }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                self?.queue.async { self?.previewAngleChanged(angle) }
            }
        ]
    }

    private func captureAngleChanged(_ angle: CGFloat) {
        captureAngle = angle
        guard !rotationFrozen else { return }
        applyConnectionSettings()
    }

    private func previewAngleChanged(_ angle: CGFloat) {
        guard !rotationFrozen else { return }
        let layer = previewLayer
        DispatchQueue.main.async {
            guard let connection = layer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    /// Mirroring and rotation on the data output connection, so analysed frames, the recording and the
    /// preview all agree and Vision can always be told the image is `.up`.
    private func applyConnectionSettings() {
        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
        if let angle = captureAngle, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        let aspect = Double(width) / Double(height)
        if aspect != lastAspect {
            lastAspect = aspect
            notifyMain { $0.onAspect?(aspect) }
        }

        // Recording comes first and never waits for Vision.
        var time = pts.seconds
        if recordingRequested {
            if recordStart == nil {
                recordStart = pts
                startWriter(width: width, height: height, at: pts)
            }
            if let start = recordStart {
                time = (pts - start).seconds
                appendToWriter(sampleBuffer, width: width, height: height, pts: pts)
            }
        }

        guard !visionBusy else { return }
        visionBusy = true
        let frameTime = time
        visionQueue.async { [self] in
            let frame = detectPose(in: pixelBuffer, time: frameTime)
            notifyMain { $0.onFrame?(frame) }
            queue.async { self.visionBusy = false }
        }
    }

    private func detectPose(in pixelBuffer: CVPixelBuffer, time: TimeInterval) -> PoseFrame {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        var joints: [BodyJoint: PosePoint] = [:]
        do {
            try handler.perform([poseRequest])
            let candidates = (poseRequest.results ?? []).map(Self.joints(from:))
            if let selection = PersonSelector.select(candidates: candidates, previousCenter: previousCenter) {
                joints = candidates[selection.index]
                previousCenter = selection.center
            }
        } catch {
            joints = [:]
        }
        return PoseFrame(time: time, joints: joints)
    }

    private static let jointNames: [(VNHumanBodyPoseObservation.JointName, BodyJoint)] = [
        (.nose, .nose), (.neck, .neck),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
    ]

    /// Vision's points are normalized with a bottom-left origin; the engine wants top-left.
    private static func joints(from observation: VNHumanBodyPoseObservation) -> [BodyJoint: PosePoint] {
        guard let points = try? observation.recognizedPoints(.all) else { return [:] }
        var result: [BodyJoint: PosePoint] = [:]
        for (name, joint) in jointNames {
            guard let p = points[name], p.confidence > 0 else { continue }
            result[joint] = PosePoint(x: Double(p.location.x), y: 1 - Double(p.location.y), confidence: Double(p.confidence))
        }
        return result
    }

    // MARK: Recording

    func startRecording() {
        queue.async { [self] in
            discardWriter()
            recordStart = nil
            recordingRequested = true
            rotationFrozen = true
        }
    }

    func stopRecording() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                recordingRequested = false
                recordStart = nil
                rotationFrozen = false
                let finishing = writer, finishingInput = writerInput, url = writerURL, lastFramePTS = lastPTS
                writer = nil
                writerInput = nil
                writerURL = nil

                // Let the phone's orientation catch up now that recording is over.
                if let coordinator {
                    captureAngleChanged(coordinator.videoRotationAngleForHorizonLevelCapture)
                    previewAngleChanged(coordinator.videoRotationAngleForHorizonLevelPreview)
                }

                guard let finishing, finishing.status == .writing else {
                    if let url { try? FileManager.default.removeItem(at: url) }
                    continuation.resume(returning: nil)
                    return
                }
                finishingInput?.markAsFinished()
                if lastFramePTS.isValid { finishing.endSession(atSourceTime: lastFramePTS) }
                finishing.finishWriting {
                    if finishing.status == .completed {
                        continuation.resume(returning: url)
                    } else {
                        if let url { try? FileManager.default.removeItem(at: url) }
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    private func startWriter(width: Int, height: Int, at pts: CMTime) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("form-\(UUID().uuidString).mp4")
        do {
            let newWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let newInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            newInput.expectsMediaDataInRealTime = true
            guard newWriter.canAdd(newInput) else { return }
            newWriter.add(newInput)
            guard newWriter.startWriting() else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            // The movie's timeline starts at the first recorded buffer, so pose times line up with it.
            newWriter.startSession(atSourceTime: pts)
            writer = newWriter
            writerInput = newInput
            writerURL = url
            writerSize = CGSize(width: width, height: height)
            lastPTS = pts
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func appendToWriter(_ sampleBuffer: CMSampleBuffer, width: Int, height: Int, pts: CMTime) {
        guard let writer, let writerInput, writer.status == .writing,
              Int(writerSize.width) == width, Int(writerSize.height) == height,
              writerInput.isReadyForMoreMediaData else { return }
        if writerInput.append(sampleBuffer) { lastPTS = pts }
    }

    private func discardWriter() {
        writer?.cancelWriting()
        if let writerURL { try? FileManager.default.removeItem(at: writerURL) }
        writer = nil
        writerInput = nil
        writerURL = nil
    }

    // MARK: Helpers

    private func notifyMain(_ work: @escaping @Sendable (CaptureEngine) -> Void) {
        DispatchQueue.main.async { work(self) }
    }
}
