import XCTest
import SwiftUI
@testable import Lightstack

/// Tests the size -> semantic TextStyle mapping that gives AppTheme's font
/// helpers Dynamic Type support.
final class AppThemeTypographyTests: XCTestCase {

    func testSmallSizesMapToCaption2() {
        XCTAssertEqual(AppTheme.textStyle(for: 7),  .caption2)
        XCTAssertEqual(AppTheme.textStyle(for: 8),  .caption2)
        XCTAssertEqual(AppTheme.textStyle(for: 9),  .caption2)
        XCTAssertEqual(AppTheme.textStyle(for: 11), .caption2)
    }

    func testMidSizesMapToExpectedStyles() {
        XCTAssertEqual(AppTheme.textStyle(for: 12), .caption)
        XCTAssertEqual(AppTheme.textStyle(for: 13), .footnote)
        XCTAssertEqual(AppTheme.textStyle(for: 14), .subheadline)
        XCTAssertEqual(AppTheme.textStyle(for: 15), .callout)
        XCTAssertEqual(AppTheme.textStyle(for: 16), .callout)
        XCTAssertEqual(AppTheme.textStyle(for: 17), .body)
    }

    func testLargeSizesMapToTitleStyles() {
        XCTAssertEqual(AppTheme.textStyle(for: 18), .title3)
        XCTAssertEqual(AppTheme.textStyle(for: 20), .title3)
        XCTAssertEqual(AppTheme.textStyle(for: 21), .title2)
        XCTAssertEqual(AppTheme.textStyle(for: 26), .title2)
        XCTAssertEqual(AppTheme.textStyle(for: 27), .title)
        XCTAssertEqual(AppTheme.textStyle(for: 40), .title)
    }

    func testMappingIsMonotonic() {
        // A larger input size must never map to a smaller text style.
        let order: [Font.TextStyle] = [
            .caption2, .caption, .footnote, .subheadline,
            .callout, .body, .title3, .title2, .title
        ]
        var lastIndex = 0
        for size in stride(from: CGFloat(6), through: 40, by: 1) {
            guard let index = order.firstIndex(of: AppTheme.textStyle(for: size)) else {
                return XCTFail("size \(size) mapped outside the expected ladder")
            }
            XCTAssertGreaterThanOrEqual(index, lastIndex, "size \(size) went backwards")
            lastIndex = index
        }
    }
}
