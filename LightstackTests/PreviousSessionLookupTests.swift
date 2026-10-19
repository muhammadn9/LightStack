import XCTest
@testable import Lightstack

final class PreviousSessionLookupTests: XCTestCase {

    private func cand(_ name: String, daysAgo: Int) -> PreviousSessionLookup.Candidate {
        .init(id: UUID(), name: name, date: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400))
    }

    func testMatchesIgnoringCaseAndPlurals() {
        let older = cand("rear delt fly machine", daysAgo: 9)
        let newer = cand("Rear Delt Fly Machine", daysAgo: 2)
        let other = cand("Bench Press", daysAgo: 1)
        let ids = PreviousSessionLookup.rankedMatches(forName: "REAR DELT FLY MACHINE", among: [older, other, newer])
        XCTAssertEqual(ids, [newer.id, older.id])
    }

    func testExactBeatsMoreRecentNearEquivalent() {
        let exact = cand("Leg Curl", daysAgo: 30)
        let near = cand("Seated hamstring curl", daysAgo: 1)
        let ids = PreviousSessionLookup.rankedMatches(forName: "Leg curl", among: [near, exact])
        XCTAssertEqual(ids, [exact.id, near.id])
    }

    func testNearEquivalentNameIsFoundWhenNoExactMatch() {
        let near = cand("Leg curl machine", daysAgo: 4)
        XCTAssertEqual(PreviousSessionLookup.rankedMatches(forName: "Seated hamstring curl", among: [near]), [near.id])
    }

    func testUnrelatedAndBlankNamesMatchNothing() {
        let bench = cand("Bench Press", daysAgo: 1)
        XCTAssertTrue(PreviousSessionLookup.rankedMatches(forName: "Overhead Press", among: [bench]).isEmpty)
        XCTAssertTrue(PreviousSessionLookup.rankedMatches(forName: "  ", among: [bench]).isEmpty)
    }
}
