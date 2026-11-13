import XCTest
import simd
@testable import Lightstack

/// Biomechanical sanity checks over every authored guide motion (41 samples per rep).
final class GuideMotionTests: XCTestCase {

    private func issues(_ category: GuideMotionValidator.Category) -> [String] {
        ExerciseMotionLibrary.all.flatMap { motion in
            GuideMotionValidator.issues(for: motion).filter { $0.category == category }.map(\.message)
        }
    }

    func testLibraryIsNotEmpty() {
        XCTAssertEqual(ExerciseMotionLibrary.all.count, ExerciseCatalog.exercises.count)
    }

    func testEveryJointIsPresentAndFinite() {
        XCTAssertEqual(issues(.joints), [])
    }

    func testSegmentLengthsNeverChange() {
        XCTAssertEqual(issues(.lengths), [])
    }

    func testMotionsLoopSeamlessly() {
        XCTAssertEqual(issues(.loop), [])
    }

    func testMotionsAreContinuous() {
        XCTAssertEqual(issues(.continuity), [])
    }

    func testNothingGoesBelowTheFloor() {
        XCTAssertEqual(issues(.floor), [])
    }

    func testElbowAndKneeAnglesStayInRange() {
        XCTAssertEqual(issues(.angles), [])
    }

    func testJointsBendTheRightWay() {
        XCTAssertEqual(issues(.bend), [])
    }

    func testBarbellHandsStayOnALevelBarAtConstantWidth() {
        XCTAssertEqual(issues(.bar), [])
        let barMotions = ExerciseMotionLibrary.all.filter(\.traits.bilateralBar)
        XCTAssertGreaterThanOrEqual(barMotions.count, 15)
    }

    func testPlantedFeetStayPut() {
        XCTAssertEqual(issues(.planted), [])
        XCTAssertGreaterThanOrEqual(ExerciseMotionLibrary.all.filter(\.traits.feetPlanted).count, 40)
    }

    func testMotionsActuallyMove() {
        XCTAssertEqual(issues(.movement), [])
    }

    func testLimbsDoNotPassThroughPropsTheTorsoOrEachOther() {
        XCTAssertEqual(issues(.geometry), [])
    }

    func testTemplateSpecificChecks() {
        XCTAssertEqual(issues(.template), [])
        let templates = Set(ExerciseMotionLibrary.all.map(\.traits.template))
        for t: MotionTraits.Template in [.squat, .deadlift, .benchPress, .overheadPress, .curl, .lateralRaise, .pullUp] {
            XCTAssertTrue(templates.contains(t), "no motion uses template \(t)")
        }
    }

    func testBodyDimensionsAddUpToAnAdult() {
        XCTAssertEqual(FigureProportions.totalHeight, 1.75, accuracy: 0.02)
        let pose = ExerciseMotionLibrary.motion(for: "Plank")?.frame(at: 0).pose
        XCTAssertNotNil(pose)
    }

    func testStandingHeadReachesAdultHeight() throws {
        let motion = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "Lateral Raise"))
        let pose = motion.frame(at: 0).pose
        let top = pose.position(.head).y + FigureProportions.headRadius
        XCTAssertEqual(top, 1.75, accuracy: 0.10)
    }

    func testDebugDescriptionListsKeyAngles() throws {
        let motion = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "Barbell Squat"))
        let text = GuideMotionDebug.describe(motion)
        XCTAssertTrue(text.contains("Barbell Squat"))
        XCTAssertTrue(text.contains("kneeL="))
    }
}
