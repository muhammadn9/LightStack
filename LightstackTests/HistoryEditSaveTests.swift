import XCTest
@testable import Lightstack

final class HistoryEditSaveTests: XCTestCase {
    func testUnionDeduplicatesAndPreservesOrder() {
        let result = HistoryViewModel.exerciseNamesToRecalculate(
            old: ["Bench Press", "Squat"], new: ["Squat", "Row"])
        XCTAssertEqual(result, ["Bench Press", "Squat", "Row"])
    }

    func testUnionIncludesRemovedAndAddedNames() {
        let result = HistoryViewModel.exerciseNamesToRecalculate(old: ["A"], new: ["B"])
        XCTAssertEqual(Set(result), ["A", "B"])
    }

    func testUnionOfEmptyIsEmpty() {
        XCTAssertTrue(HistoryViewModel.exerciseNamesToRecalculate(old: [], new: []).isEmpty)
    }
}
