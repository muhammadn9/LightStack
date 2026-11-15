import XCTest
@testable import Lightstack

@MainActor
final class FormGuideViewModelTests: XCTestCase {

    private func model(_ name: String = "Barbell Bench Press", playing: Bool = true) -> FormGuideViewModel {
        FormGuideViewModel(exerciseName: name, startsPlaying: playing)
    }

    func testInitialCameraIsMotionDefault() throws {
        let vm = model()
        let motion = try XCTUnwrap(vm.motion)
        XCTAssertEqual(vm.camera, motion.defaultCamera)
        vm.select(camera: .back)
        XCTAssertEqual(vm.camera, .back)
    }

    func testChipIsolateAndRestore() throws {
        let vm = model()
        let motion = try XCTUnwrap(vm.motion)
        let all = FormGuideViewModel.highlightSets(for: motion, isolated: nil)
        XCTAssertEqual(all.primary, Set(motion.primaryMuscles))
        let muscle = try XCTUnwrap(motion.primaryMuscles.first)
        vm.toggleIsolate(muscle)
        XCTAssertEqual(vm.isolatedMuscle, muscle)
        let only = FormGuideViewModel.highlightSets(for: motion, isolated: muscle)
        XCTAssertEqual(only.primary, [muscle])
        XCTAssertTrue(only.secondary.isEmpty)
        XCTAssertEqual(vm.controller?.mannequin.primaryHighlight, [muscle])
        vm.toggleIsolate(muscle)
        XCTAssertNil(vm.isolatedMuscle)
        XCTAssertEqual(vm.controller?.mannequin.primaryHighlight, all.primary)
    }

    func testIsolatingSecondaryMuscleKeepsItSecondary() throws {
        let vm = model()
        let motion = try XCTUnwrap(vm.motion)
        let secondary = try XCTUnwrap(vm.secondaryMuscles.first)
        let sets = FormGuideViewModel.highlightSets(for: motion, isolated: secondary)
        XCTAssertTrue(sets.primary.isEmpty)
        XCTAssertEqual(sets.secondary, [secondary])
    }

    func testPhaseLabelForProgress() {
        let phases = [GuidePhase(progress: 0, label: "Start"), GuidePhase(progress: 0.5, label: "Bottom"),
                      GuidePhase(progress: 0.9, label: "Lockout")]
        XCTAssertEqual(FormGuideViewModel.phaseLabel(for: 0, phases: phases), "Start")
        XCTAssertEqual(FormGuideViewModel.phaseLabel(for: 0.3, phases: phases), "Start")
        XCTAssertEqual(FormGuideViewModel.phaseLabel(for: 0.5, phases: phases), "Bottom")
        XCTAssertEqual(FormGuideViewModel.phaseLabel(for: 0.7, phases: phases), "Bottom")
        XCTAssertEqual(FormGuideViewModel.phaseLabel(for: 1, phases: phases), "Lockout")
        XCTAssertEqual(FormGuideViewModel.phaseLabel(for: 0.5, phases: []), "")
    }

    func testScrubPausesAndSeeks() {
        let vm = model()
        XCTAssertTrue(vm.isPlaying)
        vm.scrub(to: 0.5)
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(vm.controller?.isPlaying, false)
        XCTAssertEqual(vm.progress, 0.5, accuracy: 1e-5)
        XCTAssertEqual(vm.controller?.progress ?? -1, 0.5, accuracy: 1e-5)
        vm.togglePlay()
        XCTAssertTrue(vm.isPlaying)
    }

    func testSpeedToggleAndSuspendResume() {
        let vm = model()
        vm.toggleSpeed()
        XCTAssertEqual(vm.controller?.speed, 0.5)
        vm.toggleSpeed()
        XCTAssertEqual(vm.controller?.speed, 1)
        vm.suspend()
        XCTAssertEqual(vm.controller?.isPlaying, false)
        vm.resume()
        XCTAssertEqual(vm.controller?.isPlaying, true)
        vm.togglePlay()
        vm.suspend(); vm.resume()
        XCTAssertEqual(vm.controller?.isPlaying, false, "A user pause survives suspend/resume")
    }

    func testReduceMotionStartsPaused() {
        let vm = model(playing: false)
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(vm.controller?.isPlaying, false)
    }

    func testNoMotionState() {
        let vm = FormGuideViewModel(exerciseName: "Zorblax Quantum Flibber", startsPlaying: true)
        XCTAssertFalse(vm.hasMotion)
        XCTAssertNil(vm.controller)
        XCTAssertTrue(vm.primaryMuscles.isEmpty)
        XCTAssertEqual(vm.phaseLabel, "")
        vm.togglePlay(); vm.scrub(to: 0.3); vm.toggleIsolate(.chest)
        XCTAssertNil(vm.isolatedMuscle)
    }

    func testEveryMuscleHasHumanReadableName() {
        var seen = Set<String>()
        for muscle in MuscleGroup.allCases {
            let name = muscle.displayName
            XCTAssertFalse(name.isEmpty)
            XCTAssertNotEqual(name, muscle.rawValue, "\(muscle) shows its raw value")
            XCTAssertTrue(seen.insert(name).inserted, "Duplicate name \(name)")
        }
        XCTAssertEqual(MuscleGroup.frontDelts.displayName, "Front delts")
    }
}
