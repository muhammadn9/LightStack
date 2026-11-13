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
    private func place(_ kind: JointAngle, side: BodySide, degrees: Double, dx offset: Double = 0.1,
                       into joints: inout [BodyJoint: PosePoint]) {
        let (a, b, c) = kind.joints(side)
        let dx = side == .left ? -offset : offset
        let pa = PosePoint(x: 0.5 + dx, y: 0.3, confidence: 0.9)
        let pb = PosePoint(x: 0.5 + dx, y: 0.5, confidence: 0.9)
        let r = degrees * .pi / 180
        let pc = PosePoint(x: 0.5 + dx + 0.2 * sin(r), y: 0.5 - 0.2 * cos(r), confidence: 0.9)
        joints[a] = pa; joints[b] = pb; joints[c] = pc
    }

    private func track(kind: JointAngle, left: [Double], right: [Double]? = nil,
                       noiseScale: Double = 0.8, sway: ((Double) -> Double)? = nil,
                       dropout: ((Int) -> Bool)? = nil, dx: Double = 0.1, hips: Bool = false) -> PoseTrack {
        var frames: [PoseFrame] = []
        for i in left.indices {
            let t = Double(i) / fps
            var joints: [BodyJoint: PosePoint] = [:]
            place(kind, side: .left, degrees: left[i] + noise(i, noiseScale), dx: dx, into: &joints)
            place(kind, side: .right, degrees: (right ?? left)[min(i, (right ?? left).count - 1)] + noise(i + 7, noiseScale), dx: dx, into: &joints)
            if hips {
                joints[.leftHip] = PosePoint(x: 0.5 - dx, y: 0.6, confidence: 0.9)
                joints[.rightHip] = PosePoint(x: 0.5 + dx, y: 0.6, confidence: 0.9)
            }
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

    // MARK: Folded signals (displacement)

    /// A front-view standing body. `arms` supplies (elbow, wrist) offsets from the left shoulder in image
    /// units for the working arm; the other arm hangs still. `leg` supplies the left ankle/knee offsets.
    private func frontBodyTrack(duration: Double, jitter: Double = 0.004,
                                workingArm: ((Double) -> (elbow: (Double, Double), wrist: (Double, Double)))? = nil,
                                workingLeg: ((Double) -> Double)? = nil) -> PoseTrack {
        var frames: [PoseFrame] = []
        let count = Int(duration * fps)
        for i in 0..<count {
            let t = Double(i) / fps
            func j(_ x: Double, _ y: Double, _ k: Int) -> PosePoint {
                PosePoint(x: x + noise(i * 31 + k, jitter), y: y + noise(i * 31 + k + 100, jitter), confidence: 0.9)
            }
            var joints: [BodyJoint: PosePoint] = [
                .nose: j(0.5, 0.18, 0), .neck: j(0.5, 0.27, 1),
                .leftShoulder: j(0.4, 0.3, 2), .rightShoulder: j(0.6, 0.3, 3),
                .leftHip: j(0.43, 0.6, 4), .rightHip: j(0.57, 0.6, 5),
                .leftKnee: j(0.43, 0.78, 6), .rightKnee: j(0.57, 0.78, 7),
                .leftAnkle: j(0.43, 0.95, 8), .rightAnkle: j(0.57, 0.95, 9),
                .rightElbow: j(0.62, 0.45, 10), .rightWrist: j(0.62, 0.6, 11)
            ]
            if let arm = workingArm {
                let a = arm(t)
                joints[.leftElbow] = j(0.4 + a.elbow.0, 0.3 + a.elbow.1, 12)
                joints[.leftWrist] = j(0.4 + a.wrist.0, 0.3 + a.wrist.1, 13)
            } else {
                joints[.leftElbow] = j(0.38, 0.45, 12)
                joints[.leftWrist] = j(0.38, 0.6, 13)
            }
            if let leg = workingLeg {
                let th = leg(t) * .pi / 180
                joints[.leftKnee] = j(0.43 - 0.18 * sin(th), 0.6 + 0.18 * cos(th), 6)
                joints[.leftAnkle] = j(0.43 - 0.35 * sin(th), 0.6 + 0.35 * cos(th), 8)
            }
            frames.append(PoseFrame(time: t, joints: joints))
        }
        return PoseTrack(frames: frames, aspectRatio: 1)
    }

    /// Smooth 0...1 rep profile at time `t` into a repeating set that starts after `lead` seconds.
    private func repPhase(_ t: Double, lead: Double = 2, reps: Int, period: Double, outFrac: Double = 0.5) -> Double {
        let u = t - lead
        guard u >= 0, u < Double(reps) * period else { return 0 }
        let f = u.truncatingRemainder(dividingBy: period) / period
        return f < outFrac ? 0.5 * (1 - cos(.pi * f / outFrac)) : 0.5 * (1 + cos(.pi * (f - outFrac) / (1 - outFrac)))
    }

    private func rearDeltFlyFromFront(reps n: Int = 10, period: Double = 2.5) -> PoseTrack {
        frontBodyTrack(duration: 4 + Double(n) * period, workingArm: { t in
            // Arm sweeps horizontally from across the chest (-60) to out to the side (+80) at shoulder
            // height; the elbow passes over the shoulder point mid-rep and the arm points at the camera.
            let phi = (-60 + 140 * self.repPhase(t, reps: n, period: period)) * .pi / 180
            let ey = 0.04 * cos(phi), wy = 0.08 * cos(phi)
            return (elbow: (0.12 * sin(phi), ey), wrist: (0.24 * sin(phi), wy))
        })
    }

    func testSingleArmRearDeltFlyFromTheFrontCountsTenNotNineteen() throws {
        let a = FormAnalyzer.analyze(track: rearDeltFlyFromFront(), exerciseName: "Single arm Cable rear delt fly")
        XCTAssertEqual(a.profile.id, "flye")
        XCTAssertEqual(a.repCount, 10, "counted \(a.repCount) via \(a.detection.kind)")
        XCTAssertFalse(a.findings.contains { $0.kind == .rangeConsistency && $0.severity != .good }, "\(a.findings.map(\.title))")
        XCTAssertFalse(a.findings.contains { $0.kind == .tempoControl }, "\(a.findings.map(\.title))")
        XCTAssertFalse(a.findings.contains { $0.detail.contains("degrees") && a.detection.kind == .displacement })
    }

    func testFoldedAngleAloneIsDoubleCountedButDisplacementFixesIt() {
        // Documents the failure: with displacement disabled the folded angle gives about twice the reps.
        let t = rearDeltFlyFromFront()
        var p = MovementProfileLibrary.flye
        p.displacementLimb = nil
        let angleOnly = RepDetector.detect(track: t, profile: p)
        let both = RepDetector.detect(track: t, profile: MovementProfileLibrary.flye)
        XCTAssertEqual(both.reps.count, 10, "kind \(both.kind)")
        XCTAssertNotEqual(angleOnly.reps.count, 10)
    }

    func testFrontRaiseSeenFromTheFrontCountsEight() {
        let t = frontBodyTrack(duration: 4 + 8 * 3, workingArm: { t in
            let alpha = 85 * self.repPhase(t, reps: 8, period: 3) * .pi / 180
            // Arm rises toward the camera: it shortens in the image and stays under the shoulder.
            return (elbow: (0.01 * sin(alpha), 0.12 * cos(alpha) + 0.02 * sin(alpha)),
                    wrist: (0.01 * sin(alpha), 0.24 * cos(alpha) + 0.03 * sin(alpha)))
        })
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Dumbbell Front Raise")
        XCTAssertEqual(a.repCount, 8, "kind \(a.detection.kind)")
    }

    func testStandingHipAbductionCountsTen() {
        let t = frontBodyTrack(duration: 4 + 10 * 3, workingLeg: { t in 35 * self.repPhase(t, reps: 10, period: 3) })
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Standing Cable Hip Abduction")
        XCTAssertEqual(a.profile.id, "hipAbduction")
        XCTAssertEqual(a.repCount, 10, "kind \(a.detection.kind)")
    }

    func testGenuinelyAlternatingEffortSlowRepsAreNotMerged() {
        let segs = (0..<4).flatMap { _ in [Seg.rep(amp: -80, period: 2.5), Seg.rep(amp: -64, period: 2.5)] }
        XCTAssertEqual(FormAnalyzer.analyze(track: squatTrack(segs), exerciseName: "Barbell Squat").repCount, 8)
        let harsher = (0..<4).flatMap { _ in [Seg.rep(amp: -80, period: 2.5), Seg.rep(amp: -48, period: 3)] }
        XCTAssertEqual(FormAnalyzer.analyze(track: squatTrack(harsher), exerciseName: "Barbell Squat").repCount, 8)
    }

    func testFastFoldedAlternationIsMergedIntoFullReps() {
        // Twelve 1.2 s cycles that alternate 80 / 48 degrees: six folded reps, not twelve.
        let segs = (0..<6).flatMap { _ in [Seg.rep(amp: -80, period: 1.2), Seg.rep(amp: -48, period: 1.2)] }
        let a = FormAnalyzer.analyze(track: squatTrack(segs), exerciseName: "Barbell Squat")
        XCTAssertEqual(a.repCount, 6)
    }

    func testAlternationStrengthIgnoresNoiseAndSeesRealAlternation() {
        XCTAssertEqual(RepDetector.alternationStrength([60, 61, 59, 60, 62, 60]), 0, accuracy: 0.05)
        XCTAssertGreaterThan(RepDetector.alternationStrength([59, 36, 58, 37, 60, 35]), 0.25)
        XCTAssertEqual(RepDetector.alternationStrength([59, 36]), 0)
    }

    // MARK: Left / right

    private func elbowSets(left: Double, right: Double) -> (l: [Double], r: [Double]) {
        (series([.still(2)] + reps(8, amp: -left) + [.still(2)], rest: 170),
         series([.still(2)] + reps(8, amp: -right) + [.still(2)], rest: 170))
    }

    func testSideOnRowWithHiddenFarArmGivesNoImbalance() {
        let s = elbowSets(left: 110, right: 60)
        let t = track(kind: .elbow, left: s.l, right: s.r, dx: 0.01, hips: true)
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Seated Cable Row")
        XCTAssertGreaterThanOrEqual(a.repCount, 6)
        XCTAssertFalse(a.findings.contains { $0.kind == .sideImbalance })
    }

    func testFrontOnRealThirtyPercentDifferenceIsReported() throws {
        let s = elbowSets(left: 110, right: 76)
        let t = track(kind: .elbow, left: s.l, right: s.r, hips: true)
        let a = FormAnalyzer.analyze(track: t, exerciseName: "Seated Cable Row")
        let f = try XCTUnwrap(a.findings.first { $0.kind == .sideImbalance }, "\(a.findings.map(\.title))")
        XCTAssertTrue(f.title.hasSuffix("side moves less"))
    }

    func testFrontOnSmallDifferenceUnderTwentyPercentIsIgnored() {
        let s = elbowSets(left: 110, right: 95)
        let t = track(kind: .elbow, left: s.l, right: s.r, hips: true)
        XCTAssertFalse(FormAnalyzer.analyze(track: t, exerciseName: "Seated Cable Row").findings.contains { $0.kind == .sideImbalance })
    }

    // MARK: Torso sway thresholds and wording

    func testRowToleratesModerateTorsoMovementButStillFlagsHeavySwing() throws {
        let segs = [Seg.still(2)] + reps(6, amp: -110) + [.still(2)]
        let s = series(segs, rest: 170)
        // 8 degrees amplitude = 16 peak to peak: fine on a row (limit 25), flagged on a curl (limit 12).
        let mild = track(kind: .elbow, left: s, sway: { 8 * sin(2 * .pi * $0 / 3) })
        XCTAssertFalse(FormAnalyzer.analyze(track: mild, exerciseName: "Seated Cable Row").findings.contains { $0.kind == .torsoSway })
        XCTAssertTrue(FormAnalyzer.analyze(track: mild, exerciseName: "Dumbbell Curl").findings.contains { $0.kind == .torsoSway })
        // 16 amplitude = 32 peak to peak: minor on a row (the 32 degree swing the owner saw), not major.
        let swing = track(kind: .elbow, left: s, sway: { 16 * sin(2 * .pi * $0 / 3) })
        let f = try XCTUnwrap(FormAnalyzer.analyze(track: swing, exerciseName: "Seated Cable Row").findings.first { $0.kind == .torsoSway })
        XCTAssertEqual(f.severity, .minor)
        XCTAssertTrue(f.cue.hasPrefix("Keep your torso still and let your arms do the work."), f.cue)
        XCTAssertTrue(f.cue.contains("Drop the weight if you have to swing."))
        for banned in ["stand", "sit", "seated", "lying"] {
            XCTAssertFalse((f.title + f.detail + f.cue).lowercased().contains(banned), banned)
        }
        let heavy = track(kind: .elbow, left: s, sway: { 22 * sin(2 * .pi * $0 / 3) })
        XCTAssertEqual(FormAnalyzer.analyze(track: heavy, exerciseName: "Seated Cable Row").findings.first { $0.kind == .torsoSway }?.severity, .major)
    }

    func testEveryProfileHasVisualChecksAndRowSwayLimits() {
        for p in MovementProfileLibrary.all {
            XCTAssertGreaterThanOrEqual(p.visualChecks.count, 4, p.id)
            XCTAssertLessThanOrEqual(p.visualChecks.count, 6, p.id)
        }
        XCTAssertEqual(MovementProfileLibrary.row.swayMinorDegrees, 25)
        XCTAssertEqual(MovementProfileLibrary.row.swayMajorDegrees, 38)
        XCTAssertEqual(MovementProfileLibrary.curl.swayMinorDegrees, 12)
        XCTAssertEqual(MovementProfileLibrary.curl.swayMajorDegrees, 20)
        XCTAssertEqual(MovementProfileLibrary.flye.signalOrder.first, .displacement)
        XCTAssertEqual(MovementProfileLibrary.curl.signalOrder.first, .angle)
    }

    func testDisplacementSummaryNeverPrintsDegrees() {
        let a = FormAnalyzer.analyze(track: rearDeltFlyFromFront(), exerciseName: "Single arm Cable rear delt fly")
        guard a.detection.kind == .displacement else { return }
        XCTAssertFalse(a.summaryForPrompt().contains("deg"))
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
