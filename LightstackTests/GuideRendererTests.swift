import XCTest
import SceneKit
import simd
@testable import Lightstack

final class GuideRendererTests: XCTestCase {

    private func motion(_ name: String) throws -> ExerciseGuideMotion {
        try XCTUnwrap(ExerciseMotionLibrary.all.first { $0.exerciseName == name })
    }

    // MARK: Timeline

    func testTimelineHoldsAtStartAndPeak() {
        let t = GuideTimeline(repDuration: 4, speed: 1, peak: 0.5, hold: 0.35)
        XCTAssertEqual(t.progress(at: 0), 0)
        XCTAssertEqual(t.progress(at: 0.34), 0)
        XCTAssertEqual(t.progress(at: 0.35 + 2.0 + 0.1), 0.5, accuracy: 1e-5)
        XCTAssertEqual(t.progress(at: 0.35 + 2.0 + 0.34), 0.5, accuracy: 1e-5)
        XCTAssertGreaterThan(t.progress(at: 0.35 + 2.0 + 0.36), 0.5)
        XCTAssertEqual(t.cycleDuration, 4.7, accuracy: 1e-9)
    }

    func testTimelineLoopsAndSpeed() {
        let t = GuideTimeline(repDuration: 4, speed: 1, peak: 0.5)
        XCTAssertEqual(t.progress(at: 4.7 + 1.0), t.progress(at: 1.0), accuracy: 1e-5)
        let slow = GuideTimeline(repDuration: 4, speed: 0.5, peak: 0.5)
        XCTAssertEqual(slow.cycleDuration, 8.7, accuracy: 1e-9)
        XCTAssertEqual(slow.progress(at: 0.35 + 2.0), 0.25, accuracy: 1e-5)
    }

    func testTimelineScrubIsInverse() {
        let t = GuideTimeline(repDuration: 4, speed: 1, peak: 0.5)
        for p: Float in [0, 0.1, 0.3, 0.5, 0.7, 0.95] {
            XCTAssertEqual(t.progress(at: t.time(forProgress: p)), p, accuracy: 1e-4)
        }
    }

    func testControllerScrubAndAdvance() throws {
        let c = GuideSceneController(startsPlaying: true)
        c.load(motion: try motion("Barbell Squat"))
        c.setProgress(0.3)
        XCTAssertEqual(c.progress, 0.3, accuracy: 1e-5)
        c.advance(by: 0.1)
        XCTAssertGreaterThan(c.progress, 0.3)
        c.isPlaying = false
        let p = c.progress
        c.advance(by: 1)
        XCTAssertEqual(c.progress, p)
    }

    func testPeakIsNearMiddleForASquat() throws {
        let peak = GuideSceneController.peakProgress(of: try motion("Barbell Squat"))
        XCTAssertEqual(peak, 0.5, accuracy: 0.1)
    }

    // MARK: Camera

    private func projects(_ r: CameraFraming.Result, points: [SIMD3<Float>], aspect: Float) -> Bool {
        let forward = simd_normalize(r.target - r.position)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let ky = tan(CameraFraming.fieldOfView * .pi / 360), kx = ky * aspect
        for p in points {
            let d = p - r.position
            let z = simd_dot(d, forward)
            if z <= 0.1 { return false }
            if abs(simd_dot(d, right)) / z > kx || abs(simd_dot(d, up)) / z > ky { return false }
        }
        return true
    }

    func testFramingContainsStandingLyingAndSeatedMotions() throws {
        for name in ["Barbell Squat", "Barbell Bench Press", "Leg Extension"] {
            let m = try motion(name)
            let points = CameraFraming.samplePoints(of: m)
            for preset in GuideCameraPreset.allCases {
                for aspect: Float in [1, 0.75, 1.4] {
                    let r = CameraFraming.frame(points: points, preset: preset, focusHeight: m.focusHeight, aspect: aspect)
                    XCTAssertTrue(projects(r, points: points, aspect: aspect), "\(name) \(preset) aspect \(aspect)")
                    XCTAssertGreaterThan(r.position.y, 0)
                }
            }
        }
    }

    // MARK: Props

    func testPropNodeCountsAndReuse() {
        let id = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        let props: [GuideProp] = [
            .barbell(center: SIMD3(0, 1, 0), axis: SIMD3(1, 0, 0), length: 2.2, plateRadius: 0.225),
            .ezBar(center: SIMD3(0, 1, 0), axis: SIMD3(1, 0, 0)),
            .dumbbell(center: SIMD3(0.3, 1, 0), axis: SIMD3(1, 0, 0)),
            .kettlebell(center: SIMD3(0, 0.2, 0)),
            .cable(from: SIMD3(0, 2, 0), to: SIMD3(0, 1, 0.3)),
            .handle(center: SIMD3(0, 1, 0.3), axis: SIMD3(1, 0, 0), length: 0.3),
            .box(center: SIMD3(0, 0.4, 0), size: SIMD3(0.3, 0.1, 1), rotation: id, kind: .pad),
            .box(center: SIMD3(0, 0.4, 0), size: SIMD3(0.3, 0.1, 1), rotation: id, kind: .frame),
            .box(center: SIMD3(0, 0.4, 0), size: SIMD3(0.3, 0.8, 0.3), rotation: id, kind: .weightStack),
            .box(center: SIMD3(0, 0.1, 0), size: SIMD3(0.8, 0.1, 0.8), rotation: id, kind: .platform),
            .cylinder(from: SIMD3(0, 0, 0), to: SIMD3(0, 1, 0), radius: 0.03, kind: .frame),
            .mat(center: SIMD3(0, 0.01, 0), size: SIMD2(0.9, 2))
        ]
        let r = GuidePropRenderer()
        for (i, p) in props.enumerated() {
            r.update([p])
            XCTAssertEqual(r.propNodeCount, 1, "prop \(i)")
            XCTAssertGreaterThan(r.rootNode.childNodes[0].childNodes.count, 0, "prop \(i) has geometry")
        }
        r.update(props)
        XCTAssertEqual(r.propNodeCount, props.count)
        let builds = r.rebuildCount
        var moved = props
        moved[0] = .barbell(center: SIMD3(0, 1.5, 0), axis: SIMD3(1, 0, 0), length: 2.2, plateRadius: 0.225)
        r.update(moved)
        XCTAssertEqual(r.rebuildCount, builds, "same structure reuses nodes")
        r.update(Array(props.dropLast()))
        XCTAssertEqual(r.rebuildCount, builds + 1)
        XCTAssertEqual(r.propNodeCount, props.count - 1)
    }

    func testBarbellWithoutPlatesHasFewerParts() {
        let a = GuidePropRenderer(), b = GuidePropRenderer()
        a.update([.barbell(center: .zero, axis: SIMD3(1, 0, 0), length: 2.2, plateRadius: 0.2)])
        b.update([.barbell(center: .zero, axis: SIMD3(1, 0, 0), length: 2.2, plateRadius: 0)])
        XCTAssertGreaterThan(a.rootNode.childNodes[0].childNodes.count, b.rootNode.childNodes[0].childNodes.count)
    }

    // MARK: Mannequin

    func testSegmentsFollowThePoseJoints() throws {
        let kinds: [(MannequinNode.SegmentKind, GuideJoint, GuideJoint)] = [
            (.leftThigh, .leftHip, .leftKnee), (.leftShin, .leftKnee, .leftAnkle), (.rightThigh, .rightHip, .rightKnee),
            (.leftUpperArm, .leftShoulder, .leftElbow), (.rightForearm, .rightElbow, .rightWrist),
            (.leftHand, .leftWrist, .leftHand), (.lowerTorso, .pelvis, .spineMid), (.upperTorso, .spineMid, .chest),
            (.leftFoot, .leftAnkle, .leftToe), (.rightFoot, .rightAnkle, .rightToe)
        ]
        for name in ["Barbell Squat", "Barbell Bench Press", "Pull-Up", "Plank"] {
            let m = try motion(name)
            let mannequin = MannequinNode()
            for p: Float in [0, 0.3, 0.5, 0.8] {
                let pose = m.frame(at: p).pose
                mannequin.apply(pose)
                for (kind, a, b) in kinds {
                    let e = try XCTUnwrap(mannequin.endpoints(of: kind))
                    XCTAssertLessThan(simd_length(e.start - pose.position(a)), 0.001, "\(name) \(kind) start")
                    XCTAssertLessThan(simd_length(e.end - pose.position(b)), 0.001, "\(name) \(kind) end")
                }
            }
        }
    }

    func testHighlightColoursMuscles() {
        let mannequin = MannequinNode()
        mannequin.setHighlight(primary: [.chest], secondary: [.triceps, .chest], animated: false)
        let palette = mannequin.palette
        func rgb(_ c: UIColor?) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c?.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b]
        }
        XCTAssertEqual(rgb(mannequin.muscleColor(.chest)), rgb(palette.primary))
        XCTAssertEqual(rgb(mannequin.muscleColor(.triceps)), rgb(palette.secondary))
        XCTAssertEqual(rgb(mannequin.muscleColor(.quads)), rgb(palette.muscle))
        XCTAssertNotEqual(rgb(palette.primary), rgb(palette.secondary))
        for group in MuscleGroup.allCases {
            XCTAssertGreaterThanOrEqual(mannequin.muscleShapeCounts[group] ?? 0, 2, "\(group) needs both sides")
        }
    }
}
