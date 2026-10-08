import XCTest
@testable import Lightstack

final class ProgressStatsTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return ProgressStats.weekCalendar(c)
    }()

    /// Thursday, Oct 8 2026, noon UTC. The week runs Mon Oct 5 to Sun Oct 11.
    private var now: Date { date(2026, 10, 8) }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date()
    }

    private func set(_ name: String, _ d: Date, _ lbs: Double = 100, _ reps: Int = 5) -> LoggedSet {
        LoggedSet(date: d, exerciseName: name, weightLbs: lbs, reps: reps)
    }

    func testEquipmentUsageCountsCurrentWeekOnly() {
        let sets = [
            set("Barbell Bench Press", date(2026, 10, 5)),
            set("Barbell Bench Press", date(2026, 10, 6)),
            set("Cable Curl", date(2026, 10, 8)),
            set("Barbell Row", date(2026, 10, 4))   // Sunday of the previous week
        ]
        let usage = ProgressStats.equipmentSets(sets, now: now, calendar: calendar)
        XCTAssertEqual(usage[.barbell], 2)
        XCTAssertEqual(usage[.bench], 2)
        XCTAssertEqual(usage[.cable], 1)
        XCTAssertNil(usage[.machine])
        let lastWeek = ProgressStats.equipmentSets(sets, weeksBack: 1, now: now, calendar: calendar)
        XCTAssertEqual(lastWeek[.barbell], 1)
    }

    func testSundayBelongsToTheSameWeek() {
        let usage = ProgressStats.equipmentSets([set("Barbell Curl", date(2026, 10, 11))], now: now, calendar: calendar)
        XCTAssertEqual(usage[.barbell], 1)
    }

    func testTrainedWeekdays() {
        let workouts = [
            LoggedWorkout(id: UUID(), date: date(2026, 10, 5)),
            LoggedWorkout(id: UUID(), date: date(2026, 10, 7)),
            LoggedWorkout(id: UUID(), date: date(2026, 10, 7)),
            LoggedWorkout(id: UUID(), date: date(2026, 10, 3))
        ]
        XCTAssertEqual(ProgressStats.trainedWeekdays(workouts, now: now, calendar: calendar), [0, 2])
    }

    func testWorkoutsPerWeekLastFourWeeks() {
        let workouts = [
            LoggedWorkout(id: UUID(), date: date(2026, 10, 6)),
            LoggedWorkout(id: UUID(), date: date(2026, 10, 7)),
            LoggedWorkout(id: UUID(), date: date(2026, 9, 30)),
            LoggedWorkout(id: UUID(), date: date(2026, 9, 16)),
            LoggedWorkout(id: UUID(), date: date(2026, 8, 1))   // too old
        ]
        XCTAssertEqual(ProgressStats.workoutsPerWeek(workouts, now: now, calendar: calendar), [1, 0, 1, 2])
    }

    func testHeatmapShapeCountsAndFuture() {
        let sets = [
            set("Squat", date(2026, 10, 5)), set("Squat", date(2026, 10, 5)),
            set("Squat", date(2026, 7, 13))   // Monday of the oldest week
        ]
        let grid = ProgressStats.heatmap(sets, now: now, calendar: calendar)
        XCTAssertEqual(grid.count, 13)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid[12][0], 2)
        XCTAssertEqual(grid[0][0], 1)
        XCTAssertEqual(grid[12][3], 0)    // today
        XCTAssertEqual(grid[12][4], -1)   // Friday, still ahead
        XCTAssertEqual(grid[12][6], -1)
        XCTAssertEqual(ProgressStats.heatLevel(-1), -1)
        XCTAssertEqual(ProgressStats.heatLevel(0), 0)
        XCTAssertEqual(ProgressStats.heatLevel(20), 4)
    }

    func testLiftTrendsGroupVariantsAndRank() {
        var sets: [LoggedSet] = []
        for _ in 0..<3 { sets.append(set("Bench Press", date(2026, 10, 6), 135, 5)) }
        sets.append(set("BENCH-PRESS", date(2026, 9, 30), 125, 5))
        sets.append(set("Squat", date(2026, 10, 6), 200, 5))
        sets.append(set("Plank", date(2026, 10, 6), 0, 60))   // no weight: ignored
        let trends = ProgressStats.liftTrends(sets, now: now, calendar: calendar)
        XCTAssertEqual(trends.map(\.setCount), [4, 1])
        XCTAssertEqual(trends.first?.name, "Bench Press")
        XCTAssertEqual(trends.first?.weeklyE1RM.count, 8)
        let expected = 135 * (1 + 5.0 / 30)
        XCTAssertEqual(trends.first?.weeklyE1RM.last ?? nil, expected)
        XCTAssertEqual(trends.first?.weeklyE1RM[6] ?? nil, 125 * (1 + 5.0 / 30))
    }

    func testMonthDeltaAndMonthComparison() {
        let sets = [
            set("Bench Press", date(2026, 9, 10), 150, 5),   // last month
            set("Bench Press", date(2026, 8, 20), 160, 5),   // older, higher
            set("Bench Press", date(2026, 10, 2), 175, 5)
        ]
        guard let lift = ProgressStats.liftTrends(sets, now: now, calendar: calendar).first else {
            return XCTFail("No trend")
        }
        XCTAssertEqual(lift.thisMonth?.weightLbs, 175)
        XCTAssertEqual(lift.lastMonth?.weightLbs, 150)
        // Best before this month is the older 160 x 5.
        let delta = (lift.monthDelta ?? 0)
        XCTAssertEqual(delta, 175 * (1 + 5.0 / 30) - 160 * (1 + 5.0 / 30), accuracy: 0.001)
    }

    func testNoLastMonthMeansNoDelta() {
        let sets = [set("Squat", date(2026, 10, 2), 200, 5)]
        let lift = ProgressStats.liftTrends(sets, now: now, calendar: calendar).first
        XCTAssertNil(lift?.monthDelta)
        XCTAssertNil(lift?.lastMonth)
    }

    func testSnapshotEmpty() {
        let snap = ProgressStats.snapshot(sets: [], workouts: [], streak: 0, now: now, calendar: calendar)
        XCTAssertEqual(snap.totalSetsThisWeek, 0)
        XCTAssertEqual(snap.daysTrainedThisWeek, 0)
        XCTAssertEqual(snap.workoutsPerWeek, [0, 0, 0, 0])
        XCTAssertTrue(snap.lifts.isEmpty)
    }

    // MARK: - Heatmap day summaries

    func testDaySummaryWorkoutDayHasNamesAndSets() {
        let workouts = [LoggedWorkout(id: UUID(), date: date(2026, 10, 6), name: "Push")]
        let sets = [set("Bench", date(2026, 10, 6)), set("Bench", date(2026, 10, 6)), set("Row", date(2026, 10, 6))]
        let result = ProgressStats.daySummaries(sets: sets, workouts: workouts, restDays: [],
                                                now: now, calendar: calendar)
        XCTAssertEqual(result[calendar.startOfDay(for: date(2026, 10, 6))],
                       DaySummary(workoutNames: ["Push"], setCount: 3, isRest: false))
    }

    func testDaySummaryMergesTwoWorkoutsOnOneDay() {
        let workouts = [
            LoggedWorkout(id: UUID(), date: date(2026, 10, 6), name: "Push"),
            LoggedWorkout(id: UUID(), date: date(2026, 10, 6), name: "Core"),
            LoggedWorkout(id: UUID(), date: date(2026, 10, 6), name: "Push")
        ]
        let result = ProgressStats.daySummaries(sets: [], workouts: workouts, restDays: [],
                                                now: now, calendar: calendar)
        XCTAssertEqual(result[calendar.startOfDay(for: date(2026, 10, 6))]?.workoutNames, ["Push", "Core"])
    }

    func testDaySummaryRestDay() {
        let rest = date(2026, 10, 4)
        let result = ProgressStats.daySummaries(sets: [], workouts: [], restDays: [calendar.startOfDay(for: rest)],
                                                now: now, calendar: calendar)
        XCTAssertEqual(result[calendar.startOfDay(for: rest)], DaySummary(workoutNames: [], setCount: 0, isRest: true))
    }

    func testDaySummaryEmptyDayIsAbsent() {
        let workouts = [LoggedWorkout(id: UUID(), date: date(2026, 10, 6), name: "Push")]
        let result = ProgressStats.daySummaries(sets: [], workouts: workouts, restDays: [],
                                                now: now, calendar: calendar)
        XCTAssertNil(result[calendar.startOfDay(for: date(2026, 10, 7))])
        XCTAssertEqual(result.count, 1)
    }

    func testDaySummaryWindowBounds() {
        // Window: Monday Jul 13 through today (Thu Oct 8).
        let inside = date(2026, 7, 13)
        let before = date(2026, 7, 12)
        let future = date(2026, 10, 9)
        let workouts = [inside, before, future].map { LoggedWorkout(id: UUID(), date: $0, name: "X") }
        let sets = [inside, before, future].map { set("Squat", $0) }
        let result = ProgressStats.daySummaries(sets: sets, workouts: workouts,
                                                restDays: [calendar.startOfDay(for: before)],
                                                now: now, calendar: calendar)
        XCTAssertEqual(Set(result.keys), [calendar.startOfDay(for: inside)])
        XCTAssertEqual(ProgressStats.heatmapStart(now: now, calendar: calendar), calendar.startOfDay(for: inside))
    }

    func testSnapshotCarriesSummariesAndWeekStarts() {
        let workouts = [LoggedWorkout(id: UUID(), date: date(2026, 10, 6), name: "Push")]
        let snap = ProgressStats.snapshot(sets: [set("Bench", date(2026, 10, 6))], workouts: workouts,
                                          streak: 1, now: now, calendar: calendar)
        XCTAssertEqual(snap.daySummaries.count, 1)
        XCTAssertEqual(snap.liftWeekStarts.count, 8)
        XCTAssertEqual(snap.liftWeekStarts.last, calendar.startOfDay(for: date(2026, 10, 5)))
    }

    func testHeatmapDetailText() {
        let day = calendar.startOfDay(for: date(2026, 10, 6))
        let text = HeatmapView.detailText(for: day, summary: DaySummary(workoutNames: ["Push"], setCount: 18),
                                          calendar: calendar)
        XCTAssertTrue(text.contains("Push") && text.contains("18 sets") && text.contains("Oct 6"), text)
        XCTAssertTrue(HeatmapView.detailText(for: day, summary: DaySummary(isRest: true), calendar: calendar)
            .hasSuffix("Rest day"))
        XCTAssertTrue(HeatmapView.detailText(for: day, summary: nil, calendar: calendar).hasSuffix("No workout"))
    }
}
