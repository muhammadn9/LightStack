import XCTest
@testable import Lightstack

final class FormTrackingExportTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> (exercise: String?, track: PoseTrack) {
        let bundle = Bundle(for: FormTrackingExportTests.self)
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "poses")
        return try PoseFixtureLoader.decode(Data(contentsOf: try XCTUnwrap(url, "Missing fixture \(name)")))
    }

    private func result(from fixture: (exercise: String?, track: PoseTrack)) -> FormSessionResult {
        let name = fixture.exercise ?? "Lateral Raise"
        return FormSessionResult(exerciseName: name, analysis: FormAnalyzer.analyze(track: fixture.track, exerciseName: name),
                                 track: fixture.track, videoURL: nil, cameraPosition: .back)
    }

    func testExportRoundTripsThroughTheFixtureLoader() throws {
        let fixture = try loadFixture("pose_lat")
        let original = result(from: fixture)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try FormTrackingExport.writeFile(for: original, trueReps: 9, directory: dir)
        XCTAssertEqual(url.pathExtension, "json")
        let data = try Data(contentsOf: url)

        // Same shape as a fixture: the loader the engine tests use reads it straight back.
        let loaded = try PoseFixtureLoader.decode(data)
        XCTAssertEqual(loaded.exercise, "Lateral Raise")
        XCTAssertEqual(loaded.track.aspectRatio, original.track.aspectRatio, accuracy: 1e-4)
        XCTAssertEqual(loaded.track.frames.count, original.track.frames.count)
        for (a, b) in zip(loaded.track.frames, original.track.frames) {
            XCTAssertEqual(a.time, b.time, accuracy: 1e-3)
            XCTAssertEqual(Set(a.joints.keys), Set(b.joints.keys))
            for (joint, p) in b.joints {
                let q = try XCTUnwrap(a.joints[joint])
                XCTAssertEqual(q.x, p.x, accuracy: 1e-4)
                XCTAssertEqual(q.y, p.y, accuracy: 1e-4)
                XCTAssertEqual(q.confidence, p.confidence, accuracy: 1e-3)
            }
        }
        // The shared track analyses the same way as the original.
        let again = FormAnalyzer.analyze(track: loaded.track, exerciseName: "Lateral Raise")
        XCTAssertEqual(again.repCount, original.analysis.repCount)
        XCTAssertEqual(again.detection.kind, original.analysis.detection.kind)
    }

    func testExportCarriesTheAnalysisObject() throws {
        let fixture = try loadFixture("pose_lat")
        let original = result(from: fixture)
        let export = FormTrackingExport.make(result: original, trueReps: 8, appVersion: "1.2", appBuild: "74")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: export.jsonData()) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["exercise", "aspectRatio", "note", "frames", "analysis"])
        XCTAssertTrue((root["note"] as? String ?? "").contains("true reps 8"))
        let analysis = try XCTUnwrap(root["analysis"] as? [String: Any])
        XCTAssertEqual(analysis["exercise"] as? String, "Lateral Raise")
        XCTAssertEqual(analysis["profileId"] as? String, original.analysis.profile.id)
        XCTAssertEqual(analysis["signalKind"] as? String, original.analysis.detection.kind.rawValue)
        XCTAssertEqual(analysis["side"] as? String, original.analysis.detection.side?.rawValue)
        XCTAssertEqual(analysis["repCount"] as? Int, original.analysis.repCount)
        XCTAssertEqual(analysis["trueRepCount"] as? Int, 8)
        XCTAssertEqual(analysis["appBuild"] as? String, "74")
        XCTAssertEqual((analysis["reps"] as? [[String: Any]])?.count, original.analysis.detection.reps.count)
        XCTAssertNotNil(analysis["findings"] as? [[String: Any]])
        // A frame is {t, j:{joint:[x,y,c]}}.
        let frames = try XCTUnwrap(root["frames"] as? [[String: Any]])
        let withJoints = try XCTUnwrap(frames.first { !(($0["j"] as? [String: Any]) ?? [:]).isEmpty })
        XCTAssertNotNil(withJoints["t"] as? Double)
        let joint = try XCTUnwrap((withJoints["j"] as? [String: [Double]])?.values.first)
        XCTAssertEqual(joint.count, 3)
    }

    func testTrueRepCountIsOptionalAndNoVideoIsIncluded() throws {
        let original = result(from: try loadFixture("pose_lat"))
        let export = FormTrackingExport.make(result: original, trueReps: nil, appVersion: "1", appBuild: "1")
        let text = try XCTUnwrap(String(data: export.jsonData(), encoding: .utf8))
        XCTAssertFalse(text.contains("trueRepCount"))
        XCTAssertFalse(text.lowercased().contains("video"))
    }
}
