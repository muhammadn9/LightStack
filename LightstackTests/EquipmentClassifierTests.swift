import XCTest
@testable import Lightstack

final class EquipmentClassifierTests: XCTestCase {

    private func kinds(_ name: String) -> Set<EquipmentKind> {
        EquipmentClassifier.kinds(forName: name)
    }

    func testMachines() {
        XCTAssertEqual(kinds("Seated Leg extension machine"), [.machine])
        XCTAssertEqual(kinds("Smith machine chest press"), [.machine])
        XCTAssertEqual(kinds("Single arm pec fly machine"), [.machine])
        XCTAssertEqual(kinds("Hip Adductor Machine"), [.machine])
        XCTAssertEqual(kinds("Hip Abductor"), [.machine])
        XCTAssertEqual(kinds("Leg Press"), [.machine])
        XCTAssertEqual(kinds("Lying Leg Curl"), [.machine, .bench])
        XCTAssertEqual(kinds("Pec Deck"), [.machine])
    }

    func testCables() {
        XCTAssertEqual(kinds("Cable lat pull down machine"), [.cable])
        XCTAssertEqual(kinds("Cable ez bar tricep pushdown"), [.cable])
        XCTAssertEqual(kinds("Lat Pulldown"), [.cable])
        XCTAssertEqual(kinds("Tricep Pushdown"), [.cable])
        XCTAssertEqual(kinds("Face Pull"), [.cable])
    }

    func testDumbbells() {
        XCTAssertEqual(kinds("Alternating DB hammer curls"), [.dumbbells])
        XCTAssertEqual(kinds("Dumbbell Row"), [.dumbbells])
        XCTAssertEqual(kinds("Incline DB Press"), [.dumbbells, .bench])
    }

    func testBarbellsAndBench() {
        XCTAssertEqual(kinds("Barbell Bench Press"), [.barbell, .bench])
        XCTAssertEqual(kinds("BB Row"), [.barbell])
        XCTAssertEqual(kinds("EZ Bar Curl"), [.barbell])
        XCTAssertEqual(kinds("Barbell Curl"), [.barbell])
        XCTAssertEqual(kinds("Bench Press"), [.barbell, .bench])
        XCTAssertEqual(kinds("Deadlift"), [.barbell])
    }

    func testSmithInclineCountsBench() {
        XCTAssertEqual(kinds("Incline Smith Machine Press"), [.machine, .bench])
    }

    func testBodyweightAndKettlebell() {
        XCTAssertEqual(kinds("Pull-Up"), [.bodyweight])
        XCTAssertEqual(kinds("Push Ups"), [.bodyweight])
        XCTAssertEqual(kinds("Dips (Chest)"), [.bodyweight])
        XCTAssertEqual(kinds("Plank"), [.bodyweight])
        XCTAssertEqual(kinds("Kettlebell Swing"), [.kettlebell])
        XCTAssertEqual(kinds("KB Goblet Squat"), [.kettlebell])
    }

    /// No implement in the name: bodyweight, done with the back foot on a bench.
    func testBulgarianSplitSquatIsBodyweightOnBench() {
        XCTAssertEqual(kinds("Bulgarian split squats"), [.bodyweight, .bench])
    }

    func testSeededWorkoutNames() {
        XCTAssertEqual(kinds("Overhead Press"), [.barbell])
        XCTAssertEqual(kinds("Skull Crusher"), [.barbell, .bench])
    }

    func testCatalogClassificationFallback() {
        XCTAssertEqual(EquipmentClassifier.kinds(forName: "Mystery Move", catalogClassification: "Cable"), [.cable])
        XCTAssertEqual(EquipmentClassifier.kinds(forName: "Mystery Move", catalogClassification: "Dumbbell"), [.dumbbells])
        XCTAssertTrue(EquipmentClassifier.kinds(forName: "Mystery Move", catalogClassification: "Cardio").isEmpty)
    }

    func testUnknownIsExcluded() {
        XCTAssertTrue(kinds("Treadmill").isEmpty)
        XCTAssertTrue(kinds("").isEmpty)
    }

    func testNamesKeywordsBeatCatalog() {
        XCTAssertEqual(EquipmentClassifier.primaryKind(forName: "Cable Curl", catalogClassification: "Barbell"), .cable)
    }
}
