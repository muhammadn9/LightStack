import XCTest
import Combine
@testable import Lightstack

final class ActiveWorkoutViewModelTests: XCTestCase {

    private var viewModel: ActiveWorkoutViewModel!

    override func setUp() {
        super.setUp()
        viewModel = ActiveWorkoutViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - buildSet: nil cases

    func testBuildSetReturnsNilWhenEditingRepsMissing() {
        let id = UUID()
        XCTAssertNil(viewModel.buildSet(exerciseId: id))
    }

    func testBuildSetReturnsNilWhenRepsIsZero() {
        let id = UUID()
        viewModel.editingReps[id] = "0"
        XCTAssertNil(viewModel.buildSet(exerciseId: id))
    }

    func testBuildSetReturnsNilWhenRepsIsNonNumeric() {
        let id = UUID()
        viewModel.editingReps[id] = "abc"
        XCTAssertNil(viewModel.buildSet(exerciseId: id))
    }

    func testBuildSetReturnsNilWhenRepsIsNegative() {
        let id = UUID()
        viewModel.editingReps[id] = "-1"
        XCTAssertNil(viewModel.buildSet(exerciseId: id))
    }

    // MARK: - buildSet: bodyweight logic

    func testBuildSetTreatsEmptyWeightAsBodyweight() {
        let id = UUID()
        viewModel.editingReps[id] = "5"
        viewModel.editingWeight[id] = ""
        let set = viewModel.buildSet(exerciseId: id)
        XCTAssertEqual(set?.weightLbs, 0.0)
    }

    func testBuildSetTreatsUppercaseBWAsBodyweight() {
        let id = UUID()
        viewModel.editingReps[id] = "5"
        viewModel.editingWeight[id] = "BW"
        let set = viewModel.buildSet(exerciseId: id)
        XCTAssertEqual(set?.weightLbs, 0.0)
    }

    func testBuildSetTreatsLowercaseBwAsBodyweight() {
        let id = UUID()
        viewModel.editingReps[id] = "5"
        viewModel.editingWeight[id] = "bw"
        let set = viewModel.buildSet(exerciseId: id)
        XCTAssertEqual(set?.weightLbs, 0.0)
    }

    // MARK: - buildSet: weight validation regression

    func testBuildSetReturnsNilWhenWeightIsZeroRegression() {
        // Regression: weight "0" must return nil (w > 0 fix, not >= 0)
        let id = UUID()
        viewModel.editingReps[id] = "5"
        viewModel.editingWeight[id] = "0"
        XCTAssertNil(viewModel.buildSet(exerciseId: id))
    }

    func testBuildSetReturnsNilForNegativeWeight() {
        let id = UUID()
        viewModel.editingReps[id] = "5"
        viewModel.editingWeight[id] = "-5"
        XCTAssertNil(viewModel.buildSet(exerciseId: id))
    }

    func testBuildSetReturnsNilForNonNumericWeight() {
        let id = UUID()
        viewModel.editingReps[id] = "5"
        viewModel.editingWeight[id] = "heavy"
        XCTAssertNil(viewModel.buildSet(exerciseId: id))
    }

    // MARK: - buildSet: successful build

    func testBuildSetProducesCorrectFieldValues() {
        let id = UUID()
        viewModel.editingReps[id] = "5"
        viewModel.editingWeight[id] = "135.5"
        viewModel.editingRir[id] = "2"
        let set = viewModel.buildSet(exerciseId: id)
        XCTAssertEqual(set?.weightLbs, 135.5)
        XCTAssertEqual(set?.reps, 5)
        XCTAssertEqual(set?.rir, 2)
    }

    func testBuildSetDefaultsRirToTwoWhenMissing() {
        let id = UUID()
        viewModel.editingReps[id] = "8"
        viewModel.editingWeight[id] = "100"
        // editingRir not set
        let set = viewModel.buildSet(exerciseId: id)
        XCTAssertEqual(set?.rir, 2)
    }

    func testBuildSetDefaultsRirToTwoWhenNonNumeric() {
        let id = UUID()
        viewModel.editingReps[id] = "8"
        viewModel.editingWeight[id] = "100"
        viewModel.editingRir[id] = "two"
        let set = viewModel.buildSet(exerciseId: id)
        XCTAssertEqual(set?.rir, 2)
    }

    // MARK: - buildSet: side effects

    func testBuildSetClearsEditingFieldsAfterSuccess() {
        let id = UUID()
        viewModel.editingReps[id] = "5"
        viewModel.editingWeight[id] = "100"
        viewModel.editingRir[id] = "1"
        viewModel.editingNote[id] = "felt good"
        _ = viewModel.buildSet(exerciseId: id)
        XCTAssertEqual(viewModel.editingWeight[id], "")
        XCTAssertEqual(viewModel.editingReps[id], "")
        XCTAssertEqual(viewModel.editingRir[id], "")
        XCTAssertEqual(viewModel.editingNote[id], "")
    }

    func testBuildSetAppendsToLoggedSetsWithCorrectSetNumber() {
        let id = UUID()
        // Pre-populate one existing set
        let existing = WorkoutSet.create(exerciseId: id, setNumber: 1, weightLbs: 80, reps: 8, rir: 3)
        viewModel.loggedSets[id] = [existing]

        viewModel.editingReps[id] = "6"
        viewModel.editingWeight[id] = "85"
        viewModel.editingRir[id] = "2"
        let set = viewModel.buildSet(exerciseId: id)

        XCTAssertEqual(viewModel.loggedSets[id]?.count, 2)
        XCTAssertEqual(set?.setNumber, 2)
    }

    // MARK: - logPendingSet: nil cases

    func testLogPendingSetReturnsNilWhenNoPendingSets() {
        let id = UUID()
        XCTAssertNil(viewModel.logPendingSet(at: 0, exerciseId: id))
    }

    func testLogPendingSetReturnsNilWhenIndexOutOfRange() {
        let id = UUID()
        viewModel.pendingSets[id] = [PendingSetInput(weight: "100", reps: "5", rir: "2")]
        XCTAssertNil(viewModel.logPendingSet(at: 1, exerciseId: id))
    }

    // MARK: - logPendingSet: weight validation regression

    func testLogPendingSetTreatsZeroWeightAsBodyweight() {
        // Repeat-session rules: weight "0" is accepted and logged as bodyweight (0).
        let id = UUID()
        viewModel.pendingSets[id] = [PendingSetInput(weight: "0", reps: "5", rir: "2")]
        XCTAssertEqual(viewModel.logPendingSet(at: 0, exerciseId: id)?.weightLbs, 0)
    }

    // MARK: - logPendingSet: bodyweight logic

    func testLogPendingSetTreatsEmptyWeightAsBodyweight() {
        let id = UUID()
        viewModel.pendingSets[id] = [PendingSetInput(weight: "", reps: "5", rir: "2")]
        let set = viewModel.logPendingSet(at: 0, exerciseId: id)
        XCTAssertEqual(set?.weightLbs, 0.0)
    }

    func testLogPendingSetTreatsBWAsBodyweight() {
        let id = UUID()
        viewModel.pendingSets[id] = [PendingSetInput(weight: "BW", reps: "5", rir: "2")]
        let set = viewModel.logPendingSet(at: 0, exerciseId: id)
        XCTAssertEqual(set?.weightLbs, 0.0)
    }

    func testLogPendingSetReturnsCorrectWeightLbs() {
        let id = UUID()
        viewModel.pendingSets[id] = [PendingSetInput(weight: "100", reps: "5", rir: "2")]
        let set = viewModel.logPendingSet(at: 0, exerciseId: id)
        XCTAssertEqual(set?.weightLbs, 100.0)
    }

    // MARK: - logPendingSet: side effects

    func testLogPendingSetRemovesPendingAndAddsToLogged() {
        let id = UUID()
        viewModel.pendingSets[id] = [
            PendingSetInput(weight: "100", reps: "5", rir: "2"),
            PendingSetInput(weight: "105", reps: "5", rir: "2")
        ]
        _ = viewModel.logPendingSet(at: 0, exerciseId: id)
        XCTAssertEqual(viewModel.pendingSets[id]?.count, 1)
        XCTAssertEqual(viewModel.loggedSets[id]?.count, 1)
    }

    // MARK: - formattedElapsedTime

    func testFormattedElapsedTimeZeroSeconds() {
        viewModel.elapsedSeconds = 0
        XCTAssertEqual(viewModel.formattedElapsedTime, "0:00")
    }

    func testFormattedElapsedTime65Seconds() {
        viewModel.elapsedSeconds = 65
        XCTAssertEqual(viewModel.formattedElapsedTime, "1:05")
    }

    func testFormattedElapsedTime3725Seconds() {
        viewModel.elapsedSeconds = 3725
        XCTAssertEqual(viewModel.formattedElapsedTime, "62:05")
    }

    // MARK: - WorkoutClock isolation

    func testClockTicksDoNotEmitViewModelObjectWillChange() {
        var emissions = 0
        let cancellable = viewModel.objectWillChange.sink { emissions += 1 }
        viewModel.clock.elapsedSeconds = 42
        viewModel.clock.isPaused = true
        XCTAssertEqual(emissions, 0)
        XCTAssertEqual(viewModel.elapsedSeconds, 42)
        XCTAssertTrue(viewModel.isPaused)
        XCTAssertEqual(viewModel.formattedElapsedTime, "0:42")
        cancellable.cancel()
    }

    func testClockEmitsOwnObjectWillChange() {
        var emissions = 0
        let cancellable = viewModel.clock.objectWillChange.sink { emissions += 1 }
        viewModel.clock.elapsedSeconds = 1
        XCTAssertEqual(emissions, 1)
        cancellable.cancel()
    }

    // MARK: - Rest banner helpers

    func testRestTextFormatting() {
        let now = Date()
        XCTAssertEqual(ActiveWorkoutViewModel.restText(target: now.addingTimeInterval(90), now: now), "1:30")
        XCTAssertEqual(ActiveWorkoutViewModel.restText(target: now.addingTimeInterval(45), now: now), "45s")
        XCTAssertEqual(ActiveWorkoutViewModel.restText(target: now.addingTimeInterval(-5), now: now), "0s")
    }

    func testRestProgress() {
        let now = Date()
        XCTAssertEqual(ActiveWorkoutViewModel.restProgress(target: now.addingTimeInterval(60), total: 120, now: now), 0.5, accuracy: 0.001)
        XCTAssertEqual(ActiveWorkoutViewModel.restProgress(target: now.addingTimeInterval(-1), total: 120, now: now), 1)
        XCTAssertEqual(ActiveWorkoutViewModel.restProgress(target: now, total: 0, now: now), 0)
    }

    func testRefreshRestTimersClearsExpired() {
        let id = UUID()
        viewModel.restTimerTargetDates[id] = Date().addingTimeInterval(-10)
        viewModel.restTimerTotalSeconds[id] = 90
        viewModel.activeRestExerciseId = id
        viewModel.refreshRestTimers()
        XCTAssertNil(viewModel.restTimerTargetDates[id])
        XCTAssertNil(viewModel.activeRestExerciseId)
    }

    // MARK: - refreshTargets

    private func exercise(sets: Int, coachNote: String?) -> Exercise {
        Exercise.create(
            workoutId: UUID(),
            name: "Bench Press",
            muscleGroup: "Chest",
            orderIndex: 0,
            targetSets: sets,
            targetReps: "8-10",
            targetRir: "2",
            restSeconds: 90,
            coachNote: coachNote
        )
    }

    /// The bug behind "I accepted the change and nothing happened": inputs were
    /// already filled from the old target, and prefillTargets skips non-empty
    /// fields. A coach modification has to overwrite them.
    func testRefreshTargetsOverwritesAlreadyFilledInputs() {
        var ex = exercise(sets: 3, coachNote: "Target: 135 lbs")
        viewModel.prefillTargets(for: ex)
        XCTAssertEqual(viewModel.editingWeight[ex.id], "135")

        ex.coachNote = "Target: 145 lbs"
        viewModel.refreshTargets(for: ex)

        XCTAssertEqual(viewModel.editingWeight[ex.id], "145")
        XCTAssertEqual(viewModel.pendingSets[ex.id]?.count, 3)
        XCTAssertEqual(viewModel.pendingSets[ex.id]?.allSatisfy { $0.weight == "145" }, true)
    }

    /// Already-logged sets are history — a new target must not resurrect them.
    func testRefreshTargetsLeavesLoggedSetsAlone() {
        var ex = exercise(sets: 3, coachNote: "Target: 135 lbs")
        viewModel.prefillTargets(for: ex)
        viewModel.loggedSets[ex.id] = [
            WorkoutSet.create(exerciseId: ex.id, setNumber: 1, weightLbs: 135, reps: 8, rir: 2)
        ]

        ex.coachNote = "Target: 145 lbs"
        viewModel.refreshTargets(for: ex)

        XCTAssertEqual(viewModel.loggedSets[ex.id]?.count, 1)
        XCTAssertEqual(viewModel.loggedSets[ex.id]?.first?.weightLbs, 135)
        XCTAssertEqual(viewModel.pendingSets[ex.id]?.count, 2)
    }

    /// Dropping the set count must shrink the visible rows, not leave orphans.
    func testRefreshTargetsShrinksPendingSetsWhenTargetDrops() {
        var ex = exercise(sets: 4, coachNote: "Target: 135 lbs")
        viewModel.prefillTargets(for: ex)
        XCTAssertEqual(viewModel.pendingSets[ex.id]?.count, 4)

        ex.targetSets = 2
        viewModel.refreshTargets(for: ex)
        XCTAssertEqual(viewModel.pendingSets[ex.id]?.count, 2)
    }

    // MARK: - Date-based clock

    func testClockCatchesUpAfterBackgroundGap() {
        let vm = ActiveWorkoutViewModel()
        vm.startTimer(from: 10)
        vm.syncElapsed(now: Date().addingTimeInterval(125))
        XCTAssertEqual(vm.elapsedSeconds, 135)
        vm.stopTimer()
    }

    func testPausedClockDoesNotAdvance() {
        let vm = ActiveWorkoutViewModel()
        vm.startTimer(from: 0)
        vm.pauseTimer()
        let paused = vm.elapsedSeconds
        vm.syncElapsed(now: Date().addingTimeInterval(300))
        XCTAssertEqual(vm.elapsedSeconds, paused)
        vm.stopTimer()
    }
}
