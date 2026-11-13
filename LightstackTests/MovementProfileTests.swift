import XCTest
@testable import Lightstack

final class MovementProfileTests: XCTestCase {

    func testLateralRaiseNameVariantsShareProfile() {
        let a = MovementProfileLibrary.profile(for: "Lateral Raise")
        XCTAssertEqual(a.primary, .shoulder)
        XCTAssertEqual(MovementProfileLibrary.profile(for: "Dumbbell Lateral Raises"), a)
        XCTAssertEqual(MovementProfileLibrary.profile(for: "dumbbell lateral raises"), a)
        XCTAssertEqual(a.id, "lateralRaise")
    }

    func testExplicitNameTable() {
        let table: [(String, String, JointAngle)] = [
            ("Barbell Bench Press", "horizontalPress", .elbow),
            ("Smith Machine Bench Press", "horizontalPress", .elbow),
            ("smith machine flat chest press", "horizontalPress", .elbow),
            ("Incline Dumbbell Press", "horizontalPress", .elbow),
            ("Barbell Squat", "squat", .knee),
            ("Squat", "squat", .knee),
            ("Bulgarian Split Squat", "lunge", .knee),
            ("Walking Lunge", "lunge", .knee),
            ("Romanian Deadlift", "hinge", .hip),
            ("Deadlift", "hinge", .hip),
            ("Hip Thrust", "hipThrust", .hip),
            ("Leg Press", "legPress", .knee),
            ("Leg Extension", "legExtension", .knee),
            ("Leg Curl", "legCurl", .knee),
            ("Lateral Raise", "lateralRaise", .shoulder),
            ("Front Raise", "lateralRaise", .shoulder),
            ("Bicep Curl", "curl", .elbow),
            ("db curls", "curl", .elbow),
            ("Hammer Curl", "curl", .elbow),
            ("Pull-Up", "verticalPull", .elbow),
            ("Lat Pulldown", "verticalPull", .elbow),
            ("Face Pull", "row", .elbow),
            ("Barbell Row", "row", .elbow),
            ("Cable Flye", "flye", .shoulder),
            ("Pec Deck", "flye", .shoulder),
            ("Rear Delt Fly", "flye", .shoulder),
            ("Crunch", "crunch", .hip),
            ("Overhead Press", "overheadPress", .elbow),
            ("Push-Up", "dipPushUp", .elbow),
            ("Overhead Tricep Extension", "tricepsExtension", .elbow),
            ("ez bar over head cable tricep press", "tricepsExtension", .elbow),
            ("Shrug", "untracked", .elbow),
            ("Calf Raise", "untracked", .elbow),
            ("Plank", "untracked", .elbow),
        ]
        for (name, id, angle) in table {
            let p = MovementProfileLibrary.profile(for: name)
            XCTAssertEqual(p.id, id, "\(name)")
            if id != "untracked" { XCTAssertEqual(p.primary, angle, "\(name)") }
        }
    }

    func testEveryCatalogExerciseHasAProfile() {
        let untrackedNames: Set<String> = ["Shrugs", "Standing Calf Raise", "Seated Calf Raise", "Plank", "Russian Twist",
                                           "Woodchopper", "Treadmill Run", "Rowing Machine", "Stairmaster", "Cycling",
                                           "Jump Rope", "Battle Ropes", "Elliptical"]
        for ex in ExerciseCatalog.exercises {
            let p = MovementProfileLibrary.profile(for: ex.name)
            XCTAssertNotEqual(p.id, "generic", ex.name)
            if untrackedNames.contains(ex.name) {
                XCTAssertEqual(p.id, "untracked", ex.name)
                XCTAssertTrue(p.checks.isEmpty)
            } else {
                XCTAssertNotEqual(p.id, "untracked", ex.name)
            }
        }
    }

    func testUnknownNameIsGenericAndNeverNil() {
        XCTAssertEqual(MovementProfileLibrary.profile(for: "Zxqv Thing").id, "generic")
        XCTAssertEqual(MovementProfileLibrary.profile(for: "").id, "generic")
    }

    func testProfileSanity() {
        XCTAssertTrue((12...20).contains(MovementProfileLibrary.all.count))
        var ids = Set<String>()
        for p in MovementProfileLibrary.all {
            XCTAssertTrue(ids.insert(p.id).inserted, "duplicate id \(p.id)")
            guard p.isTracked else { continue }
            XCTAssertGreaterThanOrEqual(p.minAmplitudeDegrees, 18, p.id)
            let ratio = p.minAmplitudeDegrees / p.fullRangeDegrees
            XCTAssertTrue((0.28...0.42).contains(ratio), "\(p.id) ratio \(ratio)")
            XCTAssertFalse(p.checks.isEmpty, p.id)
            XCTAssertFalse(p.cameraTip.isEmpty, p.id)
            XCTAssertTrue((2...3).contains(p.cues.count), p.id)
            for s in [p.cameraTip, p.displayName] + p.cues { XCTAssertFalse(s.contains("—"), p.id) }
        }
        let sway: Set<String> = ["curl", "lateralRaise", "tricepsExtension", "row", "overheadPress"]
        for p in MovementProfileLibrary.all {
            XCTAssertEqual(p.checks.contains(.torsoSway), sway.contains(p.id), p.id)
        }
    }

    func testJointAngleTriples() {
        XCTAssertEqual(JointAngle.elbow.joints(.left).1, .leftElbow)
        XCTAssertEqual(JointAngle.knee.joints(.right).2, .rightAnkle)
        XCTAssertEqual(JointAngle.shoulder.joints(.left).0, .leftHip)
        XCTAssertEqual(JointAngle.hip.joints(.right).1, .rightHip)
    }
}
