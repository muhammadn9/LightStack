import AVFoundation
import Combine

/// A producer of pose frames: the real camera, or a synthetic figure in UI tests.
///
/// Frames are published on the main thread. A frame with no joints means "no person this frame";
/// `PoseFrame.time` is seconds since recording start while recording, otherwise a monotonic clock.
@MainActor
protocol PoseSource: AnyObject {
    var framePublisher: AnyPublisher<PoseFrame?, Never> { get }
    /// Width / height of the upright frames.
    var aspectRatio: Double { get }
    /// nil for the synthetic source.
    var previewSession: AVCaptureSession? { get }
    var permissionDenied: Bool { get }
    var permissionDeniedPublisher: AnyPublisher<Bool, Never> { get }
    /// Fires when capture is interrupted (phone call, app backgrounded, ...).
    var interruptionPublisher: AnyPublisher<Void, Never> { get }
    var cameraPosition: AVCaptureDevice.Position { get }

    func start()
    func stop()
    func flipCamera()
    /// Frame times restart at 0 from the next frame.
    func startRecording()
    /// Finishes the movie file and returns it (temp directory), or nil if there is none.
    func stopRecording() async -> URL?
    /// Lets the source keep the preview layer's rotation in step with gravity.
    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?)
}

extension PoseSource {
    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?) {}
}

/// Picks the person being filmed when several are in frame. Pure, so it can be unit tested.
enum PersonSelector {
    struct Center: Equatable {
        var x: Double
        var y: Double
    }

    struct Selection: Equatable {
        let index: Int
        let center: Center
    }

    static let minJoints = 4
    static let minConfidence = 0.2
    /// A candidate near the previous person wins only if its box is at least this share of the largest.
    static let dominanceRatio = 0.5

    /// Bounding box of the confident joints, or nil with fewer than `minJoints` of them.
    static func box(of joints: [BodyJoint: PosePoint]) -> (area: Double, center: Center)? {
        let pts = joints.values.filter { $0.confidence >= minConfidence }
        guard pts.count >= minJoints else { return nil }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return ((maxX - minX) * (maxY - minY), Center(x: (minX + maxX) / 2, y: (minY + maxY) / 2))
    }

    /// Index (into `candidates`) of the person to follow, or nil when nobody qualifies.
    static func select(candidates: [[BodyJoint: PosePoint]], previousCenter: Center?) -> Selection? {
        let boxes: [(index: Int, area: Double, center: Center)] = candidates.enumerated().compactMap { i, joints in
            guard let b = box(of: joints) else { return nil }
            return (i, b.area, b.center)
        }
        guard let largest = boxes.max(by: { $0.area < $1.area }) else { return nil }
        guard let previous = previousCenter else { return Selection(index: largest.index, center: largest.center) }

        let contenders = boxes.filter { $0.area >= largest.area * dominanceRatio }
        let nearest = contenders.min { a, b in
            distanceSquared(a.center, previous) < distanceSquared(b.center, previous)
        } ?? largest
        return Selection(index: nearest.index, center: nearest.center)
    }

    private static func distanceSquared(_ a: Center, _ b: Center) -> Double {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }
}
