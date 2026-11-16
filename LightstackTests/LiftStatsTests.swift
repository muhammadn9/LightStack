import XCTest
@testable import Lightstack

final class LiftStatsTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    private var now: Date { day(2026, 11, 15) }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date()
    }

    private func entry(_ name: String, _ date: Date, _ sets: [(Double, Int, Int?)], group: String = "Chest",
                       perArm: Bool = false, workout: String = "Push", id: UUID = UUID()) -> LiftEntry {
        LiftEntry(workoutId: id, date: date, workoutName: workout, exerciseName: name, muscleGroup: group,
                  isPerArm: perArm, sets: sets.map { HistorySet($0.0, $0.1, rir: $0.2) })
    }

    private func summaries(_ entries: [LiftEntry]) -> [LiftSummary] {
        LiftStats.summaries(entries, now: now, calendar: calendar)
    }

    func testSessionsAndSeriesAreOldestFirstAndUseTheSharedFormula() {
        let result = summaries([
            entry("Bench Press", day(2026, 11, 10), [(135, 8, 2)]),
            entry("Bench Press", day(2026, 10, 1), [(100, 10, 2)])
        ])
        XCTAssertEqual(result.count, 1)
        let lift = result[0]
        XCTAssertEqual(lift.sessionCount, 2)
        XCTAssertEqual(lift.sessions.map(\.e1rm), [OneRepMax.estimate(weight: 100, reps: 10),
                                                  OneRepMax.estimate(weight: 135, reps: 8)])
        XCTAssertEqual(lift.currentE1RM, OneRepMax.estimate(weight: 135, reps: 8))
        XCTAssertEqual(lift.recentSessions.first?.date, day(2026, 11, 10))
        XCTAssertEqual(lift.firstDate, day(2026, 10, 1))
        XCTAssertEqual(lift.lastDate, day(2026, 11, 10))
    }

    func testChangeUpDownEvenAndNew() {
        let old = day(2026, 10, 1)      // before the 30-day cutoff (Oct 16)
        let recent = day(2026, 11, 10)
        let up = summaries([entry("A", old, [(100, 10, 2)]), entry("A", recent, [(135, 8, 2)])])[0]
        let expectedUp = OneRepMax.estimate(weight: 135, reps: 8) - OneRepMax.estimate(weight: 100, reps: 10)
        XCTAssertEqual(up.change, .delta(expectedUp))
        XCTAssertGreaterThan(expectedUp, 0)

        let down = summaries([entry("B", old, [(135, 8, 2)]), entry("B", recent, [(100, 10, 2)])])[0]
        if case .delta(let lbs) = down.change { XCTAssertLessThan(lbs, 0) } else { XCTFail("Expected a drop") }

        let even = summaries([entry("C", old, [(100, 10, 2)]), entry("C", recent, [(100, 10, 2)])])[0]
        XCTAssertEqual(even.change, .even)

        let new = summaries([entry("D", day(2026, 11, 1), [(100, 10, 2)]), entry("D", recent, [(110, 10, 2)])])[0]
        XCTAssertEqual(new.change, .new)
        let single = summaries([entry("E", recent, [(100, 10, 2)])])[0]
        XCTAssertEqual(single.change, .new)
    }

    func testBestSetHeaviestAndVolume() {
        let first = UUID(), second = UUID()
        let lift = summaries([
            entry("Bench Press", day(2026, 10, 26), [(145, 5, 1), (130, 8, 2)], id: first),
            entry("Bench Press", day(2026, 11, 14), [(135, 8, 2), (135, 8, 1)], id: second)
        ])[0]
        // 135 x 8 -> 171; 145 x 5 -> 169.2; 130 x 8 -> 164.7
        XCTAssertEqual(lift.bestSet.weightLbs, 135)
        XCTAssertEqual(lift.bestSet.reps, 8)
        XCTAssertEqual(lift.bestSet.workoutId, second)
        XCTAssertEqual(lift.heaviest.weightLbs, 145)
        XCTAssertEqual(lift.heaviest.date, day(2026, 10, 26))
        let newest = lift.recentSessions[0]
        XCTAssertEqual(newest.topWeightLbs, 135)
        XCTAssertEqual(newest.volumeLbs, 135 * 8 * 2)
    }

    func testWarmupsAreShownButDoNotCount() {
        let lift = summaries([entry("Bench Press", day(2026, 11, 14), [(95, 8, 5), (135, 8, 2), (135, 8, 1)])])[0]
        let session = lift.sessions[0]
        XCTAssertEqual(session.sets.map(\.isWarmup), [true, false, false])
        XCTAssertEqual(session.sets.count, 3)
        XCTAssertEqual(session.volumeLbs, 135 * 8 * 2)
        XCTAssertEqual(session.topWeightLbs, 135)
    }

    func testAllWarmupFlaggedSessionCountsEverything() {
        let lift = summaries([entry("Curl", day(2026, 11, 14), [(20, 12, 5), (20, 12, 5)], group: "Biceps")])[0]
        XCTAssertEqual(lift.sessions[0].sets.map(\.isWarmup), [false, false])
    }

    func testAToZCaseInsensitiveOrder() {
        let names = ["squat", "Bench Press", "deadlift", "Curl", "Arnold Press"]
        let result = summaries(names.map { entry($0, day(2026, 11, 1), [(100, 5, 2)]) })
        XCTAssertEqual(result.map(\.name), ["Arnold Press", "Bench Press", "Curl", "deadlift", "squat"])
    }

    func testCardioIsExcluded() {
        let result = summaries([
            entry("Treadmill", day(2026, 11, 1), [(0, 20, nil)], group: "Cardio"),
            entry("Rower", day(2026, 11, 1), [(10, 20, nil)], group: "cardio"),
            entry("Squat", day(2026, 11, 1), [(200, 5, 2)], group: "Legs")
        ])
        XCTAssertEqual(result.map(\.name), ["Squat"])
    }

    func testPerArmLiftKeepsFlagAndDoublesVolume() {
        let lift = summaries([entry("Dumbbell Curl", day(2026, 11, 14), [(30, 10, 2)], group: "Biceps", perArm: true)])[0]
        XCTAssertTrue(lift.isPerArm)
        XCTAssertEqual(lift.currentE1RM, OneRepMax.estimate(weight: 30, reps: 10))
        XCTAssertEqual(lift.sessions[0].volumeLbs, 30 * 10 * 2)
    }

    func testSpellingVariantsShareOneLiftNamedByTheLatest() {
        let result = summaries([
            entry("hammer curls", day(2026, 10, 1), [(25, 10, 2)], group: "Biceps"),
            entry("Hammer Curl", day(2026, 11, 10), [(30, 10, 2)], group: "Biceps")
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Hammer Curl")
        XCTAssertEqual(result[0].sessionCount, 2)
    }

    func testLiftAppearingTwiceInOneWorkoutIsOneSession() {
        let id = UUID()
        let lift = summaries([
            entry("Bench Press", day(2026, 11, 10), [(135, 8, 2)], id: id),
            entry("Barbell Bench Press", day(2026, 11, 10), [(145, 5, 1)], id: id)
        ])
        // Different keys ("barbell bench press" vs "bench press") stay separate lifts.
        XCTAssertEqual(lift.count, 2)
        let same = summaries([
            entry("Bench Press", day(2026, 11, 10), [(135, 8, 2)], id: id),
            entry("bench  press", day(2026, 11, 10), [(145, 5, 1)], id: id)
        ])
        XCTAssertEqual(same.count, 1)
        XCTAssertEqual(same[0].sessionCount, 1)
        XCTAssertEqual(same[0].sessions[0].sets.count, 2)
    }

    func testSetsWithoutWeightOrRepsAreIgnored() {
        let result = summaries([
            entry("Pull Up", day(2026, 11, 10), [(0, 10, 2)], group: "Back"),
            entry("Row", day(2026, 11, 10), [(0, 10, 2), (100, 10, 2)], group: "Back")
        ])
        XCTAssertEqual(result.map(\.name), ["Row"])
        XCTAssertEqual(result[0].sessions[0].sets.count, 1)
    }

    func testEmptyHistory() {
        XCTAssertTrue(summaries([]).isEmpty)
    }

    func testFormatting() {
        XCTAssertEqual(LiftFormat.weight(171, unit: .lb), "171 lb")
        XCTAssertEqual(LiftFormat.weight(220.46, unit: .kg, perArm: true), "100 kg / arm")
        XCTAssertEqual(LiftFormat.change(.delta(15), unit: .lb), "+15 lb")
        XCTAssertEqual(LiftFormat.change(.delta(-10), unit: .lb), "\u{2212}10 lb")
        XCTAssertEqual(LiftFormat.change(.delta(0.2), unit: .lb), "Even")
        XCTAssertEqual(LiftFormat.change(.new, unit: .lb), "New")
        XCTAssertEqual(LiftFormat.setText(weightLbs: 135, reps: 8, unit: .lb), "135 \u{00D7} 8")
    }
}
