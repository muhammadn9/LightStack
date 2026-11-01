import XCTest
import CoreGraphics
@testable import Lightstack

final class NutritionLabelParserTests: XCTestCase {

    // MARK: Fixture model

    private struct ExpectedField: Decodable { let value: Double; let unit: String }
    private struct Expected: Decodable {
        let format: String
        let servingLabel: String?
        let servingGrams: Double?
        let servingMl: Double?
        let servingsPerContainer: Double?
        let servingIsUncertain: Bool?
        let fields: [String: ExpectedField]
        let lowConfidence: [String]?
        let absent: [String]?
        let warningsContain: [String]?
    }

    private func fixtureData(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: NutritionLabelParserTests.self)
        let url = bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "labels")
        let found = try XCTUnwrap(url, "Missing fixture \(name).\(ext)")
        return try Data(contentsOf: found)
    }

    private func check(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let text = String(decoding: try fixtureData(name, "txt"), as: UTF8.self)
        let exp = try JSONDecoder().decode(Expected.self, from: try fixtureData(name + ".expected", "json"))
        let parsed = NutritionLabelParser.parse(text: text)

        XCTAssertEqual(parsed.format.rawValue, exp.format, "format", file: file, line: line)
        if let l = exp.servingLabel { XCTAssertEqual(parsed.servingLabel, l, "servingLabel", file: file, line: line) }
        XCTAssertEqual(parsed.servingGrams, exp.servingGrams, "servingGrams", file: file, line: line)
        XCTAssertEqual(parsed.servingMl, exp.servingMl, "servingMl", file: file, line: line)
        XCTAssertEqual(parsed.servingsPerContainer, exp.servingsPerContainer, "servingsPerContainer", file: file, line: line)
        if let u = exp.servingIsUncertain { XCTAssertEqual(parsed.servingIsUncertain, u, "uncertain", file: file, line: line) }

        XCTAssertEqual(Set(parsed.fields.keys.map(\.rawValue)), Set(exp.fields.keys), "field set", file: file, line: line)
        for (key, e) in exp.fields {
            guard let n = Nutrient(rawValue: key), let got = parsed.fields[n] else { continue }
            XCTAssertEqual(got.value, e.value, accuracy: 0.051, key, file: file, line: line)
            XCTAssertEqual(got.unit.rawValue, e.unit, "\(key) unit", file: file, line: line)
        }
        if let low = exp.lowConfidence {
            XCTAssertEqual(parsed.lowConfidenceFields.map(\.rawValue), low.sorted(), "low confidence", file: file, line: line)
        }
        for a in exp.absent ?? [] { XCTAssertNil(parsed.fields[Nutrient(rawValue: a) ?? .calories], "absent \(a)", file: file, line: line) }
        for w in exp.warningsContain ?? [] {
            XCTAssertTrue(parsed.warnings.contains { $0.contains(w) }, "warning containing '\(w)' in \(parsed.warnings)", file: file, line: line)
        }
    }

    // MARK: Fixtures

    func testUSStandard() throws { try check("us_standard") }
    func testUSAddedSugarsAndVitamins() throws { try check("us_added_sugars_vitamins") }
    func testUSDecimals() throws { try check("us_decimals") }
    func testEUDualColumn() throws { try check("eu_dual_column") }
    func testUKEnergySlashSalt() throws { try check("uk_energy_salt") }
    func testPer100mlDrink() throws { try check("per100ml_drink") }
    func testOCRNoise() throws { try check("ocr_noise") }
    func testLessThanTraceZero() throws { try check("less_than_trace_zero") }
    func testDVOnlyMicro() throws { try check("dv_only_micro") }
    func testMacroInconsistent() throws { try check("macro_inconsistent") }
    func testGarbage() throws { try check("garbage") }

    // MARK: Inline cases

    func testKJOnlyDerivesKcalWithLowerConfidence() {
        let p = NutritionLabelParser.parse(text: "Nutrition information\nTypical values per 30g serving\nEnergy 628kJ\nProtein 2g\nCarbohydrate 18g\nFat 0.5g")
        XCTAssertEqual(p.fields[.calories]?.value ?? 0, 150.1, accuracy: 0.2)
        XCTAssertLessThan(p.fields[.calories]?.confidence ?? 1, 0.9)
        XCTAssertEqual(p.servingGrams, 30)
    }

    func testPer100OnlyWithExplicitServingScales() {
        let p = NutritionLabelParser.parse(text: "Nutrition information\nServing size 50g\nTypical values per 100g\nEnergy 400kcal\nProtein 10g\nCarbohydrate 60g\nFat 5g")
        XCTAssertEqual(p.fields[.calories]?.value, 200)
        XCTAssertEqual(p.fields[.protein]?.value, 5)
        XCTAssertEqual(p.fields[.calories]?.per100, 400)
        XCTAssertFalse(p.servingIsUncertain)
    }

    func testSugarsAboveCarbsFlagged() {
        let p = NutritionLabelParser.parse(text: "Nutrition Facts\nServing size 1 cup (100g)\nCalories 100\nTotal Carbohydrate 10g\nTotal Sugars 20g\nProtein 1g\nTotal Fat 0g")
        XCTAssertTrue(p.lowConfidenceFields.contains(.sugars))
        XCTAssertTrue(p.warnings.contains { $0.contains("Sugars") })
    }

    func testSaturatedAboveTotalFatFlagged() {
        let p = NutritionLabelParser.parse(text: "Nutrition Facts\nServing size 1 cup (100g)\nCalories 90\nTotal Fat 2g\nSaturated Fat 5g\nTotal Carbohydrate 10g\nProtein 1g")
        XCTAssertTrue(p.lowConfidenceFields.contains(.saturatedFat))
    }

    func testPercentIsNeverTheAmount() {
        let p = NutritionLabelParser.parse(text: "Nutrition Facts\nServing size 1 cup (30g)\nCalories 100\nTotal Fat 0g 0%\nSodium 15%\nTotal Carbohydrate 20g 7%\nProtein 2g")
        XCTAssertNil(p.fields[.sodium])
        XCTAssertEqual(p.fields[.totalCarbs]?.value, 20)
    }

    func testDVMismatchLowersConfidence() {
        let p = NutritionLabelParser.parse(text: "Nutrition Facts\nServing size 1 cup (30g)\nCalories 100\nTotal Fat 0g\nTotal Carbohydrate 20g\nProtein 2g\nCalcium 26mg 20%")
        XCTAssertTrue(p.fields[.calcium]?.needsReview ?? false)
    }

    func testBoundingBoxesJoinColumnsOnSameBaseline() {
        let lines = [
            OCRLine(text: "Protein", box: CGRect(x: 0.1, y: 0.50, width: 0.2, height: 0.03)),
            OCRLine(text: "3g", box: CGRect(x: 0.7, y: 0.505, width: 0.1, height: 0.03)),
            OCRLine(text: "Calories", box: CGRect(x: 0.1, y: 0.30, width: 0.2, height: 0.03)),
            OCRLine(text: "110", box: CGRect(x: 0.7, y: 0.30, width: 0.1, height: 0.03)),
            OCRLine(text: "Serving size 1 cup (30g)", box: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03))
        ]
        let p = NutritionLabelParser.parse(lines: lines)
        XCTAssertEqual(p.fields[.protein]?.value, 3)
        XCTAssertEqual(p.fields[.calories]?.value, 110)
        XCTAssertEqual(p.servingGrams, 30)
    }

    func testMissingRequiredReported() {
        let p = NutritionLabelParser.parse(text: "Nutrition Facts\nServing size 1 cup (30g)\nProtein 3g")
        XCTAssertEqual(Set(p.missingRequired), [.calories, .totalCarbs, .totalFat])
    }

    // MARK: NutritionUnit

    func testNutritionUnitConversions() {
        XCTAssertEqual(NutritionUnit.oz.grams(forQuantity: 2) ?? 0, 56.699, accuracy: 0.001)
        XCTAssertEqual(NutritionUnit.g.grams(forQuantity: 5), 5)
        XCTAssertNil(NutritionUnit.cup.grams(forQuantity: 1))
        XCTAssertEqual(NutritionUnit.cup.millilitres(forQuantity: 1) ?? 0, 236.588, accuracy: 0.001)
        XCTAssertEqual(NutritionUnit.tbsp.millilitres(forQuantity: 2) ?? 0, 29.574, accuracy: 0.001)
        XCTAssertNil(NutritionUnit.piece.millilitres(forQuantity: 1))
        XCTAssertNil(NutritionUnit.serving.gramsPerUnit)
        XCTAssertEqual(NutritionUnit.parse("Cups"), .cup)
        XCTAssertEqual(NutritionUnit.parse("fl oz"), .flOz)
        XCTAssertNil(NutritionUnit.parse("banana"))
    }
}
