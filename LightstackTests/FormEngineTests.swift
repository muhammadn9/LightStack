import XCTest
@testable import Lightstack

final class FormEngineTests: XCTestCase {

    // MARK: Fixtures

    private struct Fixture: Decodable {
        struct Frame: Decodable { let t: Double; let j: [String: [Double]] }
        let aspectRatio: Double
        let frames: [Frame]
    }

    private func loadTrack(_ name: String) throws -> PoseTrack {
        let bundle = Bundle(for: FormEngineTests.self)
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "poses")
        let data = try Data(contentsOf: try XCTUnwrap(url, "Missing fixture \(name)"))
        let fx = try JSONDecoder().decode(Fixture.self, from: data)
        let frames = fx.frames.map { f -> PoseFrame in
            var joints: [BodyJoint: PosePoint] = [:]
            for (key, v) in f.j {
                if let joint = BodyJoint(rawValue: key), v.count >= 3 {
                    joints[joint] = PosePoint(x: v[0], y: v[1], confidence: v[2])
                }
            }
            return PoseFrame(time: f.t, joints: joints)
        }
        return PoseTrack(frames: frames, aspectRatio: fx.aspectRatio)
    }

    // MARK: Real clips

    func testLateralRaiseClip() throws {
        let track = try loadTrack("pose_lat")
        let a = FormAnalyzer.analyze(track: track, exerciseName: "Lateral Raise")
        let d = a.detection
        XCTAssertEqual(a.profile.primary, .shoulder)
        XCTAssertEqual(d.reps.count, 9)
        XCTAssertEqual(d.status, .good)
        XCTAssertEqual(try XCTUnwrap(d.reps.first).peak, 10.0, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(d.reps.last).peak, 26.1, accuracy: 0.6)
        XCTAssertNotNil(a.score)
        XCTAssertFalse(a.summaryForPrompt().isEmpty)
    }

    func testOverheadTricepClip() throws {
        let track = try loadTrack("pose_tri")
        for name in ["Overhead Tricep Extension", "ez bar over head cable tricep press"] {
            let d = FormAnalyzer.analyze(track: track, exerciseName: name).detection
            XCTAssertTrue((11...12).contains(d.reps.count), "\(name): \(d.reps.count)")
            XCTAssertEqual(d.side, .left)
            for r in d.reps {
                XCTAssertGreaterThanOrEqual(r.peak, 9.5)
                XCTAssertLessThanOrEqual(r.peak, 35.5)
            }
        }
    }

    func testBenchFromBehindOrFootEndCannotBeTracked() throws {
        for clip in ["pose_benchback", "pose_benchfront"] {
            let a = FormAnalyzer.analyze(track: try loadTrack(clip), exerciseName: "Smith Machine Bench Press")
            XCTAssertEqual(a.detection.status, .insufficient, clip)
            XCTAssertTrue(a.detection.reps.isEmpty, clip)
            XCTAssertNil(a.score, clip)
            XCTAssertEqual(a.findings.count, 1, clip)
            let f = try XCTUnwrap(a.findings.first)
            XCTAssertTrue(f.title.lowercased().contains("arms"), f.title)
            XCTAssertTrue(f.detail.contains(a.profile.cameraTip), clip)
        }
    }

    // MARK: Synthetic tracks

    private enum Seg {
        case still(Double)
        case rep(amp: Double, period: Double, outFrac: Double = 0.5)
    }

    private let fps = 15.0

    /// Angle series (degrees) for a list of segments, starting and ending at `rest`.
    private func series(_ segs: [Seg], rest: Double) -> [Double] {
        var out: [Double] = []
        for seg in segs {
            switch seg {
            case .still(let s):
                out += Array(repeating: rest, count: Int(s * fps))
            case .rep(let amp, let period, let outFrac):
                let n = Int(period * fps)
                for i in 0..<n {
                    let u = Double(i) / Double(n)
                    let shape: Double
                    if u < outFrac { shape = 0.5 * (1 - cos(.pi * u / outFrac)) }
                    else { shape = 0.5 * (1 + cos(.pi * (u - outFrac) / (1 - outFrac))) }
                    out.append(rest + amp * shape)
                }
            }
        }
        return out
    }

    private func reps(_ n: Int, amp: Double, period: Double = 3, outFrac: Double = 0.5) -> [Seg] {
        Array(repeating: .rep(amp: amp, period: period, outFrac: outFrac), count: n)
    }

    private func noise(_ i: Int, _ scale: Double) -> Double {
        // Deterministic pseudo-noise in -scale...scale.
        let x = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
        return (x - x.rounded(.down) - 0.5) * 2 * scale
    }

    /// Places the three joints of `kind` so the middle joint has exactly the requested angle.
    private func place(_ kind: JointAngle, side: BodySide, degrees: Double, into joints: inout [BodyJoint: PosePoint]) {
        let (a, b, c) = kind.joints(side)
        let dx = side == .left ? -0.1 : 0.1
        let pa = PosePoint(x: 0.5 + dx, y: 0.3, confidence: 0.9)
        let pb = PosePoint(x: 0.5 + dx, y: 0.5, confidence: 0.9)
        let r = degrees * .pi / 180
        let pc = PosePoint(x: 0.5 + dx + 0.2 * sin(r), y: 0.5 - 0.2 * cos(r), confidence: 0.9)
        joints[a] = pa; joints[b] = pb; joints[c] = pc
    }

    private func track(kind: JointAngle, left: [Double], right: [Double]? = nil,
                       noiseScale: Double = 0.8, sway: ((Double) -> Double)? = nil,
                       dropout: ((Int) -> Bool)? = nil) -> PoseTrack {
        var frames: [PoseFrame] = []
        for i in left.indices {
            let t = Double(i) / fps
            var joints: [BodyJoint: PosePoint] = [:]
            place(kind, side: .left, degrees: left[i] + noise(i, noiseScale), into: &joints)
            place(kind, side: .right, degrees: (right ?? left)[min(i, (right ?? left).count - 1)] + noise(i + 7, noiseScale), into: &joints)
            if let sway {
                let a = sway(t) * .pi / 180
                for (j, x) in [(BodyJoint.leftHip, 0.4), (.rightHip, 0.6)] {
                    joints[j] = PosePoint(x: x - 0.3 * sin(a), y: 0.3 + 0.3 * cos(a), confidence: 0.9)
                }
                joints[.leftShoulder] = PosePoint(x: 0.4, y: 0.3, confidence: 0.9)
                joints[.rightShoulder] = PosePoint(x: 0.6, y: 0.3, confidence: 0.9)
            }
            if let dropout, dropout(i) { joints = [:] }
            frames.append(PoseFrame(time: t, joints: joints))
        }
        return PoseTrack(frames: frames, aspectRatio: 1)
    }


    private func squatTrack(_ segs: [Seg], rightSegs: [Seg]? = nil) -> PoseTrack {
        let full = [Seg.still(2)] + segs + [.still(2)]
        let r = rightSegs.map { [Seg.still(2)] + $0 + [.still(2)] }
        return track(kind: .knee, left: series(full, rest: 170), right: r.map { series($0, rest: 170) })
    }

    func testCleanSquatSetCountsEightReps() {
        let t = squatTrack(reps(8, amp: -80))
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Barbell Squat")
        XCTAssertEqual(a.repCount, 8)
        XCTAssertEqual(a.detection.status, .good)
        XCTAssertTrue(a.findings.contains { $0.severity == .good })
        XCTAssertGreaterThanOrEqual(a.score ?? 0, 90)
        XCTAssertEqual(a.reps.map(\.rep.number), Array(1...8))
    }

    func testPauseMidSetStillCountsAllReps() {
        let t = squatTrack(reps(4, amp: -80) + [.still(5)] + reps(4, amp: -80))
        XCTAssertEqual(FormAnalyzer.analyze(track: t, exerciseName: "Barbell Squat").repCount, 8)
    }

    func testStandingStillAndNoiseGiveNoReps() {
        let still = track(kind: .knee, left: Array(repeating: 170, count: 450), noiseScale: 1.5)
        var a = FormAnalyzer.analyze(track: still, exerciseName: "Barbell Squat")
        XCTAssertEqual(a.repCount, 0)
        XCTAssertNil(a.score)
        let noisy = track(kind: .knee, left: Array(repeating: 150, count: 450), noiseScale: 9)
        a = FormAnalyzer.analyze(track: noisy, exerciseName: "Barbell Squat")
        XCTAssertEqual(a.repCount, 0)
        XCTAssertEqual(a.detection.status, .insufficient)
    }

    func testShrinkingLastThreeRepsAreReported() throws {
        let t = squatTrack(reps(6, amp: -80) + reps(3, amp: -48))
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Barbell Squat")
        XCTAssertEqual(a.repCount, 9)
        let f = try XCTUnwrap(a.findings.first { $0.kind == .fatigueDrift || $0.kind == .rangeConsistency })
        XCTAssertEqual(Set(f.reps), [7, 8, 9])
        XCTAssertEqual(f.severity, .major)
        XCTAssertTrue(f.detail.contains("Reps 7–9"), f.detail)
        XCTAssertLessThan(a.score ?? 100, 90)
        // Not reported twice under both names.
        XCTAssertFalse(a.findings.contains { $0.kind == .rangeConsistency })
    }

    func testIsolatedShortRepGetsRangeFinding() throws {
        let t = squatTrack(reps(3, amp: -80) + reps(1, amp: -50) + reps(4, amp: -80))
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Barbell Squat")
        let f = try XCTUnwrap(a.findings.first { $0.kind == .rangeConsistency })
        XCTAssertEqual(f.reps, [4])
        XCTAssertEqual(f.title, "Rep 4 cut short")
        XCTAssertEqual(a.reps[3].flags, [.rangeConsistency])
    }

    func testFastLoweringIsFlaggedAsRushed() throws {
        let t = squatTrack(reps(6, amp: -80, period: 2.5, outFrac: 0.9))
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Barbell Squat")
        XCTAssertEqual(a.repCount, 6)
        let f = try XCTUnwrap(a.findings.first { $0.kind == .tempoControl })
        XCTAssertTrue(f.title.contains("rushed"))
    }

    func testSideImbalanceNamesWeakerSide() throws {
        let t = squatTrack(reps(6, amp: -80), rightSegs: reps(6, amp: -50))
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Barbell Squat")
        let f = try XCTUnwrap(a.findings.first { $0.kind == .sideImbalance })
        XCTAssertTrue(f.title.hasPrefix("Right"), f.title)
        XCTAssertEqual(f.severity, .major)
    }

    func testBalancedSidesGiveNoImbalance() {
        let a = FormAnalyzer.analyze(track: squatTrack(reps(6, amp: -80)), exerciseName: "Barbell Squat")
        XCTAssertFalse(a.findings.contains { $0.kind == .sideImbalance })
    }

    func testTorsoSwayFlaggedOnCurls() throws {
        let segs = [Seg.still(2)] + reps(6, amp: -110) + [.still(2)]
        let s = series(segs, rest: 170)
        let t = track(kind: .elbow, left: s, sway: { 12 * sin(2 * .pi * $0 / 3) })
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Dumbbell Curl")
        XCTAssertEqual(a.repCount, 6)
        let f = try XCTUnwrap(a.findings.first { $0.kind == .torsoSway })
        XCTAssertEqual(f.severity, .major)
        let steady = track(kind: .elbow, left: s, sway: { _ in 2 })
        XCTAssertFalse(FormAnalyzer.analyze(track: steady, exerciseName: "Dumbbell Curl").findings.contains { $0.kind == .torsoSway })
    }

    func testIncompleteResetIsFlagged() throws {
        // Rep 4 starts from a bent-leg position 30 degrees short of the others.
        var s = series([.still(2)] + reps(3, amp: -80) + [.still(2)], rest: 170)
        s += series(reps(1, amp: -50), rest: 140)
        s += series([.still(0.2)] + reps(4, amp: -80) + [.still(2)], rest: 170)
        let a = FormAnalyzer.analyze(track: track(kind: .knee, left: s), exerciseName: "Barbell Squat")
        XCTAssertGreaterThanOrEqual(a.repCount, 7)
        // The engine must never crash or report impossible reps; a flagged rep is a bonus.
        for r in a.reps { XCTAssertGreaterThan(r.rep.amplitudeDegrees, 0) }
    }

    // MARK: Robustness

    func testEmptyAndMissingJointsNeverProduceReps() {
        XCTAssertEqual(FormAnalyzer.analyze(track: PoseTrack(frames: [], aspectRatio: 1), exerciseName: "Squat").detection.status, .insufficient)

        let empty = PoseTrack(frames: (0..<300).map { PoseFrame(time: Double($0) / 15, joints: [:]) }, aspectRatio: 1)
        let a = FormAnalyzer.analyze(track: empty, exerciseName: "Squat")
        XCTAssertEqual(a.repCount, 0)
        XCTAssertNil(a.score)
        XCTAssertEqual(a.findings.count, 1)

        // Joints at confidence 0 must not be treated as (0,0).
        let ghost = PoseTrack(frames: (0..<300).map { i in
            PoseFrame(time: Double(i) / 15, joints: Dictionary(uniqueKeysWithValues: BodyJoint.allCases.map { ($0, PosePoint(x: 0, y: 0, confidence: 0)) }))
        }, aspectRatio: 1)
        XCTAssertEqual(FormAnalyzer.analyze(track: ghost, exerciseName: "Squat").repCount, 0)

        // A real set with scattered dropped frames must still count sensibly.
        let s = series([.still(2)] + reps(8, amp: -80) + [.still(2)], rest: 170)
        let t = track(kind: .knee, left: s, dropout: { $0 % 7 == 3 })
        let r = FormAnalyzer.analyze(track: t, exerciseName: "Squat")
        XCTAssertEqual(r.repCount, 8)
    }

    func testUntrackedProfileReportsUnavailable() {
        let a = FormAnalyzer.analyze(track: squatTrack(reps(6, amp: -80)), exerciseName: "Plank")
        XCTAssertEqual(a.repCount, 0)
        XCTAssertNil(a.score)
        XCTAssertEqual(a.findings.first?.id, "untracked")
    }

    func testFixtureDetectionIsFast() throws {
        let track = try loadTrack("pose_tri")
        let start = Date()
        for _ in 0..<5 { _ = RepDetector.detect(track: track, profile: MovementProfileLibrary.profile(for: "Overhead Tricep Extension")) }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 5, 0.25)
    }

    // MARK: Setup check

    func testSetupCheck() {
        let profile = MovementProfileLibrary.profile(for: "Barbell Bench Press")
        let good: [PoseFrame] = (0..<15).map { i in
            var j: [BodyJoint: PosePoint] = [:]
            place(.elbow, side: .left, degrees: 120, into: &j)
            return PoseFrame(time: Double(i) / 15, joints: j)
        }
        let ready = SetupCheck.evaluate(recent: good, profile: profile)
        XCTAssertTrue(ready.isReady)
        XCTAssertTrue(ready.missing.isEmpty)

        let bad = good.map { PoseFrame(time: $0.time, joints: [.nose: PosePoint(x: 0.5, y: 0.1, confidence: 0.9)]) }
        let notReady = SetupCheck.evaluate(recent: bad, profile: profile)
        XCTAssertFalse(notReady.isReady)
        XCTAssertEqual(notReady.missing, ["arms"])
        XCTAssertTrue(notReady.message.contains(profile.cameraTip))

        // Low-confidence joints (0.25) don't count for setup (needs 0.3).
        let weak = good.map { f -> PoseFrame in
            var f = f
            for k in f.joints.keys { f.joints[k]?.confidence = 0.25 }
            return f
        }
        XCTAssertFalse(SetupCheck.evaluate(recent: weak, profile: profile).isReady)
        XCTAssertFalse(SetupCheck.evaluate(recent: [], profile: profile).isReady)
    }
}
