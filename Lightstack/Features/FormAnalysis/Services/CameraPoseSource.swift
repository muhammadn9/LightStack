import AVFoundation
import Combine

/// The real camera as a `PoseSource`. A thin main-actor shell around `CaptureEngine`, which owns the
/// session queue and every AVFoundation object.
@MainActor
final class CameraPoseSource: ObservableObject, PoseSource {

    private static let positionKey = "formCapture.cameraPosition"

    private let engine: CaptureEngine
    private let frames = PassthroughSubject<PoseFrame?, Never>()
    private let interruptions = PassthroughSubject<Void, Never>()

    @Published private(set) var permissionDenied = false
    @Published private(set) var cameraPosition: AVCaptureDevice.Position
    private(set) var aspectRatio: Double = 9.0 / 16.0

    var framePublisher: AnyPublisher<PoseFrame?, Never> { frames.eraseToAnyPublisher() }
    var permissionDeniedPublisher: AnyPublisher<Bool, Never> { $permissionDenied.eraseToAnyPublisher() }
    var interruptionPublisher: AnyPublisher<Void, Never> { interruptions.eraseToAnyPublisher() }
    var previewSession: AVCaptureSession? { engine.session }

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.positionKey)
        let position: AVCaptureDevice.Position = saved == AVCaptureDevice.Position.front.rawValue ? .front : .back
        cameraPosition = position
        engine = CaptureEngine(position: position)
        engine.onFrame = { [weak self] frame in
            MainActor.assumeIsolated { self?.frames.send(frame) }
        }
        engine.onAspect = { [weak self] aspect in
            MainActor.assumeIsolated { self?.aspectRatio = aspect }
        }
        engine.onPosition = { [weak self] position in
            MainActor.assumeIsolated {
                self?.cameraPosition = position
                UserDefaults.standard.set(position.rawValue, forKey: Self.positionKey)
            }
        }
        engine.onPermissionDenied = { [weak self] in
            MainActor.assumeIsolated { self?.permissionDenied = true }
        }
        engine.onInterrupted = { [weak self] in
            MainActor.assumeIsolated { self?.interruptions.send() }
        }
    }

    deinit {
        engine.stop()
    }

    func start() {
        permissionDenied = false
        engine.start()
    }

    func stop() { engine.stop() }
    func flipCamera() { engine.flip() }
    func startRecording() { engine.startRecording() }
    func stopRecording() async -> URL? { await engine.stopRecording() }
    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?) { engine.attachPreviewLayer(layer) }
}
