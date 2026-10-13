import XCTest
@testable import Lightstack

final class ExerciseGuideLibraryTests: XCTestCase {

    private let library = ExerciseGuideLibrary(bundle: .main)

    func testEveryMappedCatalogExerciseHasInstructionsAndImages() {
        let mapped = ExerciseCatalog.exercises.compactMap { library.guide(for: $0.name) }
        XCTAssertFalse(mapped.isEmpty, "No guides loaded from the app bundle")
        for guide in mapped {
            XCTAssertGreaterThanOrEqual(guide.instructions.count, 1, guide.catalogName)
            XCTAssertEqual(guide.imageFiles.count, 2, guide.catalogName)
            XCTAssertNotNil(guide.imageFiles.first.flatMap { ExerciseGuideLibrary.image(named: $0) }, "Missing start photo for \(guide.catalogName)")
            XCTAssertNotNil(guide.imageFiles.dropFirst().first.flatMap { ExerciseGuideLibrary.image(named: $0) }, "Missing end photo for \(guide.catalogName)")
        }
    }

    func testExactMatchIsCaseInsensitive() {
        XCTAssertEqual(library.guide(for: "barbell bench press")?.catalogName, "Barbell Bench Press")
    }

    func testCustomNameResolvesToCatalogGuide() {
        XCTAssertEqual(library.guide(for: "bench press barbell")?.catalogName, "Barbell Bench Press")
    }

    func testNonsenseNameReturnsNil() {
        XCTAssertNil(library.guide(for: "Zorblax Quantum Flibber"))
        XCTAssertNil(library.guide(for: "   "))
    }

    func testUnmappedCatalogNamesStayBelowThreshold() {
        let unmapped = ExerciseCatalog.exercises.map(\.name).filter { library.guide(for: $0) == nil }
        print("Unmapped catalog exercises (\(unmapped.count)): \(unmapped)")
        XCTAssertLessThanOrEqual(unmapped.count, 2, "Unmapped: \(unmapped)")
    }
}
