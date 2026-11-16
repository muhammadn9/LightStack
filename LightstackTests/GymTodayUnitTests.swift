import XCTest
@testable import Lightstack

/// Today redesign: weekly muscle sets, one A to Z exercise order, split chips, picker groups, review text.
final class GymTodayUnitTests: XCTestCase {

    // MARK: - Weekly muscle sets

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }

    /// Wednesday 11 Nov 2026 12:00 UTC; the week runs Monday 9 to Sunday 15.
    private var now: Date { Date(timeIntervalSince1970: 1_794_398_400) }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now) ?? now }

    private func exercise(_ name: String, _ group: String, sets: Int, cardio: Bool = false) -> WeeklyLoggedExercise {
        WeeklyLoggedExercise(name: name, muscleGroup: group, isCardio: cardio, setCount: sets)
    }

    func testSetsAreGroupedAndWorkedGroupsComeFirst() {
        let summary = WeeklyMuscleSummary.compute(workouts: [
            WeeklyLoggedWorkout(date: day(-1), exercises: [
                exercise("Bench Press", "Chest", sets: 4), exercise("Barbell Curl", "Biceps", sets: 3),
                exercise("Skull Crusher", "Triceps", sets: 3)]),
            WeeklyLoggedWorkout(date: day(0), exercises: [
                exercise("Lat Pulldown", "Back", sets: 5), exercise("Leg Press", "Legs", sets: 2)])
        ], now: now, calendar: calendar)
        XCTAssertEqual(summary.workouts, 2)
        XCTAssertEqual(summary.totalSets, 17)
        XCTAssertEqual(summary.headline, "2 workouts · 17 sets")
        let byGroup = Dictionary(uniqueKeysWithValues: summary.entries.map { ($0.group, $0.sets) })
        XCTAssertEqual(byGroup[.chest], 4)
        XCTAssertEqual(byGroup[.arms], 6, "Biceps and triceps share the Arms group")
        XCTAssertEqual(byGroup[.back], 5)
        XCTAssertEqual(byGroup[.legs], 2)
        XCTAssertEqual(byGroup[.shoulders], 0)
        XCTAssertEqual(byGroup[.core], 0)
        // Worked groups first (most sets first), then the "not yet" ones in display order.
        XCTAssertEqual(summary.entries.map(\.group), [.arms, .back, .chest, .legs, .shoulders, .core])
    }

    func testOnlyThisWeekCountsAndEmptyWorkoutsAreSkipped() {
        let summary = WeeklyMuscleSummary.compute(workouts: [
            WeeklyLoggedWorkout(date: day(-4), exercises: [exercise("Bench Press", "Chest", sets: 9)]),  // last week
            WeeklyLoggedWorkout(date: day(0), exercises: [exercise("Bench Press", "Chest", sets: 0)]),   // nothing logged
            WeeklyLoggedWorkout(date: day(0), exercises: [exercise("Rowing Machine", "Cardio", sets: 1, cardio: true)])
        ], now: now, calendar: calendar)
        XCTAssertEqual(summary.workouts, 1)
        XCTAssertEqual(summary.totalSets, 1)
        XCTAssertEqual(summary.entries.filter { $0.sets > 0 }.count, 0, "Cardio belongs to no muscle group")
    }

    func testEmptyWeek() {
        let summary = WeeklyMuscleSummary.compute(workouts: [], now: now, calendar: calendar)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.headline, "0 workouts · 0 sets")
        XCTAssertEqual(summary.entries.map(\.group), WeeklyMuscleGroup.allCases)
    }

    func testGroupMapping() {
        XCTAssertEqual(WeeklyMuscleGroup.group(forExercise: "Hammer Curl", muscleGroup: "Forearms"), .arms)
        XCTAssertEqual(WeeklyMuscleGroup.group(forExercise: "Face Pull", muscleGroup: "Back"), .shoulders)
        XCTAssertEqual(WeeklyMuscleGroup.group(forExercise: "Romanian Deadlift", muscleGroup: "Hamstrings"), .legs)
        XCTAssertEqual(WeeklyMuscleGroup.group(forExercise: "Plank", muscleGroup: "Core"), .core)
        XCTAssertEqual(WeeklyMuscleGroup.group(forExercise: "Lateral Raise", muscleGroup: "Shoulders"), .shoulders)
    }

    // MARK: - Shared A to Z sort

    func testAZSortIgnoresCaseAndKeepsTiesStable() {
        let sorted = ExerciseSort.azSorted(["lat pulldown", "Barbell Row", "cable row", "Arnold Press", "Cable Row"])
        XCTAssertEqual(sorted, ["Arnold Press", "Barbell Row", "cable row", "Cable Row", "lat pulldown"])
    }

    func testAZSortIsLocaleAware() {
        XCTAssertEqual(ExerciseSort.azSorted(["Zottman Curl", "Écarté", "Dips"]), ["Dips", "Écarté", "Zottman Curl"])
    }

    func testAZSortBySelector() {
        let records = [("b", 1), ("A", 2), ("c", 3)]
        XCTAssertEqual(ExerciseSort.azSorted(records, by: { $0.0 }).map(\.1), [2, 1, 3])
    }

    func testSectionLetter() {
        XCTAssertEqual(ExerciseSort.sectionLetter("barbell row"), "B")
        XCTAssertEqual(ExerciseSort.sectionLetter("21s Curl"), "#")
        XCTAssertEqual(ExerciseSort.sectionLetter("  "), "#")
    }

    func testCatalogFilteredIsAZ() {
        let names = ExerciseCatalog.filtered().map(\.name)
        XCTAssertEqual(names, ExerciseSort.azSorted(names))
    }

    // MARK: - Picker groups

    private let history = [
        HistoryExercise(name: "Rear Delt Fly Machine", muscleGroup: "Shoulders"),
        HistoryExercise(name: "Bench Press", muscleGroup: "Chest"),
        HistoryExercise(name: "Lat Pulldown", muscleGroup: "Back"),
        HistoryExercise(name: "Barbell Curl", muscleGroup: "Arms"),
        HistoryExercise(name: "Skull Crusher", muscleGroup: "Arms"),
        HistoryExercise(name: "Leg Press", muscleGroup: "Legs"),
        HistoryExercise(name: "Cable Row", muscleGroup: "Back")
    ]

    func testRecentIsTheLastFiveInRecencyOrder() {
        let recent = ExerciseCatalogPicker.recentRows(history: history, search: "", muscleGroup: "All", classification: "All")
        XCTAssertEqual(recent.map(\.name), ["Rear Delt Fly Machine", "Bench Press", "Lat Pulldown", "Barbell Curl", "Skull Crusher"])
    }

    func testAllRowsAreAZAndIncludeHistoryOnlyLifts() {
        let all = ExerciseCatalogPicker.allRows(history: history, search: "", muscleGroup: "All", classification: "All")
        let names = all.map(\.name)
        XCTAssertEqual(names, ExerciseSort.azSorted(names))
        XCTAssertTrue(names.contains("Rear Delt Fly Machine"), "A lift only in the log still shows")
        XCTAssertTrue(names.contains("Barbell Bench Press"), "Catalog lifts show")
        XCTAssertEqual(names.filter { $0 == "Barbell Curl" }.count, 1, "A lift in both lists shows once")
    }

    func testSearchAndEquipmentFilterNarrowBothGroups() {
        let searched = ExerciseCatalogPicker.recentRows(history: history, search: "curl", muscleGroup: "All", classification: "All")
        XCTAssertEqual(searched.map(\.name), ["Barbell Curl"])
        let equipment = ExerciseCatalogPicker.recentRows(history: history, search: "", muscleGroup: "All", classification: "Barbell")
        XCTAssertTrue(equipment.isEmpty, "History carries no equipment type, so an equipment filter hides it")
    }

    // MARK: - Split chips

    func testChipsAreSplitDaysThenHistoryNamesWithoutCaseDuplicates() {
        let chips = WorkoutSetupViewModel.chips(
            splitDays: ["Push", "Pull", "Legs"], historyNames: ["push", "Arm Day", "  ", "legs", "Core Day", "arm day"])
        XCTAssertEqual(chips, ["Push", "Pull", "Legs", "Arm Day", "Core Day"])
    }

    // MARK: - Setup settings

    private func makeSetupViewModel(_ defaults: UserDefaults) -> WorkoutSetupViewModel {
        let stack = OutboxTestStack()
        let profiles = ProfileRepository(localStorage: stack.storage, supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        return WorkoutSetupViewModel(profileRepository: profiles, validationService: ValidationService(), defaults: defaults)
    }

    func testEnergyAndTimeAreRemembered() throws {
        let suite = "GymTodayUnitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = makeSetupViewModel(defaults)
        XCTAssertEqual(first.energySummary, "4 of 5")
        XCTAssertEqual(first.timeSummary, "45 min")
        first.energyLevel = WorkoutSetupViewModel.energyLevel(forDots: 2)
        first.timeAvailable = 60
        let second = makeSetupViewModel(defaults)
        XCTAssertEqual(second.energySummary, "2 of 5")
        XCTAssertEqual(second.timeSummary, "60 min")
    }

    func testNotesSummary() throws {
        let suite = "GymTodayUnitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = makeSetupViewModel(defaults)
        vm.focus = .hypertrophy
        XCTAssertEqual(vm.notesSummary, "None")
        vm.additionalNotes = "Shoulder feels tight"
        vm.constraints = "no barbell"
        XCTAssertEqual(vm.notesSummary, "Shoulder feels tight · Constraints")
    }

    // MARK: - Review text

    func testMissReasonIsNotPrintedTwice() {
        let reason = "Missed by 12 reps: too heavy right now, drop and rebuild."
        let notes = "Top set 135x8 vs 185x8 planned, short by 12 reps. \(reason) Next: 165x8@2."
        let shown = CoachSessionReviewView.displayNotes(notes, missReason: reason)
        XCTAssertFalse(shown.contains(reason))
        XCTAssertEqual(shown, "Top set 135x8 vs 185x8 planned, short by 12 reps. Next: 165x8@2.")
        XCTAssertEqual(CoachSessionReviewView.displayNotes(reason, missReason: reason), "")
        XCTAssertEqual(CoachSessionReviewView.displayNotes("Solid.", missReason: nil), "Solid.")
    }
}
