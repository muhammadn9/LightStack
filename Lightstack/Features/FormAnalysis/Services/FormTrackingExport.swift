import Foundation

/// The shareable "tracking data" file for a set that looked wrong. Same shape as the real-clip fixtures in
/// `LightstackTests/Fixtures/poses` (exercise, aspectRatio, note, frames[{t, j{joint:[x,y,c]}}]) plus an
/// `analysis` object, so a shared file can be dropped straight into that folder. No video, no AI call.
struct FormTrackingExport: Encodable {

    struct Frame: Encodable {
        let t: Double
        let j: [String: [Double]]
    }

    struct Rep: Encodable {
        let number: Int
        let start: Double
        let peak: Double
        let end: Double
        let amplitude: Double
    }

    struct Finding: Encodable {
        let id: String
        let kind: String
        let severity: String
        let title: String
        let detail: String
        let reps: [Int]
    }

    struct Analysis: Encodable {
        let exercise: String
        let profileId: String
        let signalKind: String
        let angle: String
        let side: String?
        let trackingStatus: String
        let trackingQuality: Double
        let reps: [Rep]
        let repCount: Int
        let trueRepCount: Int?
        let findings: [Finding]
        let score: Int?
        let camera: String
        let appVersion: String
        let appBuild: String
    }

    let exercise: String
    let aspectRatio: Double
    let note: String
    let frames: [Frame]
    let analysis: Analysis

    // MARK: Building

    private static func r(_ x: Double, _ places: Double) -> Double {
        let f = pow(10, places)
        return (x * f).rounded() / f
    }

    static func make(result: FormSessionResult, trueReps: Int?, appVersion: String, appBuild: String) -> FormTrackingExport {
        let analysis = result.analysis
        let frames = result.track.frames.map { frame -> Frame in
            var joints: [String: [Double]] = [:]
            for (joint, p) in frame.joints {
                joints[joint.rawValue] = [r(p.x, 4), r(p.y, 4), r(p.confidence, 3)]
            }
            return Frame(t: r(frame.time, 3), j: joints)
        }
        var note = "Shared from Lightstack: \(analysis.exerciseName). Counted \(analysis.repCount)"
        note += trueReps.map { " reps, true reps \($0)." } ?? " reps."
        let detection = analysis.detection
        let body = Analysis(
            exercise: analysis.exerciseName,
            profileId: analysis.profile.id,
            signalKind: detection.kind.rawValue,
            angle: detection.angle.rawValue,
            side: detection.side?.rawValue,
            trackingStatus: detection.status.rawValue,
            trackingQuality: r(detection.trackingQuality, 3),
            reps: detection.reps.map {
                Rep(number: $0.number, start: r($0.start, 3), peak: r($0.peak, 3), end: r($0.end, 3),
                    amplitude: r($0.amplitudeDegrees, 1))
            },
            repCount: analysis.repCount,
            trueRepCount: trueReps,
            findings: analysis.findings.map {
                Finding(id: $0.id, kind: $0.kind.rawValue, severity: $0.severity.rawValue,
                        title: $0.title, detail: $0.detail, reps: $0.reps)
            },
            score: analysis.score,
            camera: result.cameraPosition == .front ? "front" : "back",
            appVersion: appVersion,
            appBuild: appBuild)
        return FormTrackingExport(exercise: analysis.exerciseName, aspectRatio: r(result.track.aspectRatio, 4),
                                  note: note, frames: frames, analysis: body)
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Writes the JSON to a temporary file named after the exercise and returns its URL.
    static func writeFile(for result: FormSessionResult, trueReps: Int?,
                          bundle: Bundle = .main, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let info = bundle.infoDictionary
        let export = make(result: result, trueReps: trueReps,
                          appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
                          appBuild: info?["CFBundleVersion"] as? String ?? "?")
        let slug = result.exerciseName.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let url = directory.appendingPathComponent("lightstack-tracking-\(slug).json")
        try export.jsonData().write(to: url, options: .atomic)
        return url
    }
}
