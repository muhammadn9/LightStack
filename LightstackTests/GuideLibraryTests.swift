import XCTest
import simd
@testable import Lightstack

final class GuideLibraryTests: XCTestCase {

    private func props(_ motion: ExerciseGuideMotion) -> [GuideProp] {
        (0..<5).flatMap { motion.frame(at: Float($0) / 4).props }
    }

    func testEveryCatalogExerciseHasItsOwnMotion() throws {
        var ids = Set<String>()
        for exercise in ExerciseCatalog.exercises {
            let motion = try XCTUnwrap(ExerciseMotionLibrary.motion(for: exercise.name), exercise.name)
            XCTAssertEqual(motion.exerciseName, exercise.name)
            XCTAssertTrue(ids.insert(motion.id).inserted, "duplicate id \(motion.id)")
        }
        XCTAssertEqual(ids.count, ExerciseCatalog.exercises.count)
    }

    func testIdsAreUniqueAndNamesMatchTheCatalog() {
        let all = ExerciseMotionLibrary.all
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map(\.exerciseName)), Set(ExerciseCatalog.exercises.map(\.name)))
    }

    func testFreeTypedNamesFindTheRightMovement() throws {
        let press = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "smith machine flat chest press"))
        XCTAssertEqual(MovementProfileLibrary.profile(for: press.exerciseName).id, "horizontalPress")

        let triceps = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "ez bar over head cable tricep press"))
        XCTAssertEqual(triceps.exerciseName, "Cable Overhead Extension")

        let curl = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "db curls"))
        XCTAssertEqual(curl.exerciseName, "Dumbbell Curl")

        let raise = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "lat raises"))
        XCTAssertEqual(raise.exerciseName, "Lateral Raise")

        XCTAssertEqual(ExerciseMotionLibrary.motion(for: "stair climber")?.exerciseName, "Stairmaster")
        XCTAssertEqual(ExerciseMotionLibrary.motion(for: "incline bench press")?.exerciseName, "Incline Barbell Press")
        XCTAssertEqual(ExerciseMotionLibrary.motion(for: "BARBELL SQUAT")?.exerciseName, "Barbell Squat")
        XCTAssertNil(ExerciseMotionLibrary.motion(for: "xyzzy"))
        XCTAssertNil(ExerciseMotionLibrary.motion(for: "   "))
    }

    func testEveryMotionHasUsefulText() {
        for motion in ExerciseMotionLibrary.all {
            XCTAssertGreaterThanOrEqual(motion.setupSteps.count, 2, motion.exerciseName)
            XCTAssertLessThanOrEqual(motion.setupSteps.count, 4, motion.exerciseName)
            XCTAssertGreaterThanOrEqual(motion.cues.count, 2, motion.exerciseName)
            XCTAssertLessThanOrEqual(motion.cues.count, 4, motion.exerciseName)
            XCTAssertGreaterThanOrEqual(motion.commonMistakes.count, 1, motion.exerciseName)
            XCTAssertLessThanOrEqual(motion.commonMistakes.count, 3, motion.exerciseName)
            XCTAssertGreaterThanOrEqual(motion.primaryMuscles.count, 1, motion.exerciseName)
            XCTAssertGreaterThanOrEqual(motion.phases.count, 2, motion.exerciseName)
            XCTAssertEqual(motion.phases.first?.progress, 0, motion.exerciseName)
            for line in motion.setupSteps + motion.cues + motion.commonMistakes {
                XCTAssertLessThanOrEqual(line.split(separator: " ").count, 16, "\(motion.exerciseName): \(line)")
                XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), "\(motion.exerciseName): dash in text")
                XCTAssertFalse(line.isEmpty)
            }
            XCTAssertGreaterThan(motion.repDuration, 0.5, motion.exerciseName)
            XCTAssertGreaterThan(motion.focusHeight, 0.2, motion.exerciseName)
            for p in motion.phases { XCTAssertTrue((0...1).contains(p.progress), motion.exerciseName) }
        }
    }

    func testPropsMatchTheEquipment() throws {
        for exercise in ExerciseCatalog.exercises {
            let motion = try XCTUnwrap(ExerciseMotionLibrary.motion(for: exercise.name))
            let all = props(motion)
            switch exercise.classification {
            case "Barbell":
                XCTAssertTrue(all.contains { if case .barbell = $0 { return true }; if case .ezBar = $0 { return true }; return false },
                              "\(exercise.name) needs a bar")
            case "Dumbbell":
                XCTAssertTrue(all.contains { if case .dumbbell = $0 { return true }; return false }, "\(exercise.name) needs dumbbells")
            case "Cable":
                XCTAssertTrue(all.contains { if case .cable = $0 { return true }; return false }, "\(exercise.name) needs a cable")
            default:
                break
            }
        }
    }

    func testBenchExercisesDrawPads() {
        let benchNames = ["Barbell Bench Press", "Incline Barbell Press", "Decline Bench Press", "Close-Grip Bench Press",
                          "Dumbbell Bench Press", "Incline Dumbbell Press", "Dumbbell Flye", "Skull Crusher", "Preacher Curl",
                          "Concentration Curl", "Incline Dumbbell Curl", "Dumbbell Row", "Bulgarian Split Squat", "Hip Thrust",
                          "Dumbbell Shoulder Press", "Arnold Press", "Machine Chest Press", "Machine Shoulder Press",
                          "Leg Press", "Leg Extension", "Leg Curl", "Lat Pulldown", "Seated Cable Row", "Seated Calf Raise"]
        for name in benchNames {
            guard let motion = ExerciseMotionLibrary.motion(for: name) else { XCTFail(name); continue }
            XCTAssertTrue(motion.traits.onBench, "\(name) should be flagged as performed on a bench or seat")
        }
        for motion in ExerciseMotionLibrary.all where motion.traits.onBench {
            let hasPad = props(motion).contains { if case let .box(_, _, _, kind) = $0 { return kind == .pad }; return false }
            XCTAssertTrue(hasPad, "\(motion.exerciseName) is on a bench but draws no pad")
        }
    }

    func testTypicalPhaseLabelsAndMusclesAreSane() throws {
        let squat = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "Barbell Squat"))
        XCTAssertTrue(squat.primaryMuscles.contains(.quads))
        let row = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "Barbell Row"))
        XCTAssertTrue(row.primaryMuscles.contains(.lats))
        let calf = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "Standing Calf Raise"))
        XCTAssertEqual(calf.primaryMuscles, [.calves])
    }

    func testFramesAreDeterministicAndClamped() throws {
        let motion = try XCTUnwrap(ExerciseMotionLibrary.motion(for: "Deadlift"))
        XCTAssertEqual(motion.frame(at: 0.3), motion.frame(at: 0.3))
        XCTAssertEqual(motion.frame(at: -1), motion.frame(at: 0))
        XCTAssertEqual(motion.frame(at: 2), motion.frame(at: 1))
    }
}
