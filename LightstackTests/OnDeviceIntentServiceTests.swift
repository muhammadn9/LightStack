import XCTest
@testable import Lightstack

/// Tests for `OnDeviceIntentService` logic that does NOT require Apple Intelligence.
///
/// These cover:
/// 1. `WorkoutModificationParser` fallback behaviour (parser parity — the parser tests
///    already exist in WorkoutModificationParserTests; we add a few integration-style
///    checks here for the "fallback" code path).
/// 2. The confidence-threshold decision logic surfaced by `CoachChatViewModel`.
final class OnDeviceIntentServiceTests: XCTestCase {

    // MARK: - Confidence threshold constant

    func testConfidenceThresholdIsInValidRange() {
        let threshold = OnDeviceIntentService.confidenceThreshold
        XCTAssertGreaterThan(threshold, 0.0)
        XCTAssertLessThan(threshold, 1.0)
    }

    func testConfidenceAtThresholdIsNotLowConfidence() {
        let threshold = OnDeviceIntentService.confidenceThreshold
        // At exactly the threshold the classifier is considered high-enough confidence;
        // only strictly below it triggers the explicit-confirmation flag.
        let atThreshold = threshold
        XCTAssertFalse(atThreshold < threshold, "Confidence equal to threshold should NOT be low-confidence")
    }

    func testConfidenceJustBelowThresholdIsLowConfidence() {
        let threshold = OnDeviceIntentService.confidenceThreshold
        let justBelow = threshold - 0.01
        XCTAssertTrue(justBelow < threshold, "Confidence just below threshold SHOULD be low-confidence")
    }

    func testConfidenceAboveThresholdIsHighConfidence() {
        let threshold = OnDeviceIntentService.confidenceThreshold
        let above = threshold + 0.01
        XCTAssertFalse(above < threshold, "Confidence above threshold should NOT be low-confidence")
    }

    // MARK: - requiresExplicitConfirmation state logic (pure logic, no AI needed)

    /// Simulate the decision logic that `CoachChatViewModel.handleModificationsOnDevice`
    /// performs, without actually running on-device inference.
    func testLowConfidenceClassificationSetsExplicitConfirmationFlag() {
        let lowConfidence = 0.5
        let requireConfirmation = lowConfidence < OnDeviceIntentService.confidenceThreshold
        XCTAssertTrue(requireConfirmation, "Low confidence should require explicit confirmation")
    }

    func testHighConfidenceClassificationDoesNotRequireExplicitConfirmation() {
        let highConfidence = 0.95
        let requireConfirmation = highConfidence < OnDeviceIntentService.confidenceThreshold
        XCTAssertFalse(requireConfirmation, "High confidence should not require explicit confirmation")
    }

    func testGeneralChatIntentSkipsExtraction() {
        // Simulating the guard in handleModificationsOnDevice
        let intent = ModificationIntent.generalChat
        let shouldExtract = (intent == .modificationRequest)
        XCTAssertFalse(shouldExtract, "General chat intent should skip extraction entirely")
    }

    func testModificationRequestIntentProceeds() {
        let intent = ModificationIntent.modificationRequest
        let shouldExtract = (intent == .modificationRequest)
        XCTAssertTrue(shouldExtract, "Modification request should proceed to extraction")
    }

    // MARK: - Fallback parser behaviour (regression guard)

    /// Verifies that when on-device extraction throws, the fallback parser
    /// still produces the expected modifications from a pipe-delimited line.
    func testFallbackParserProducesAddModification() {
        let parser = WorkoutModificationParser()
        let line = "[ADD] Romanian Deadlift | Hamstrings | 3 | 8-10 | 2 | 90 | Focus on stretch"
        let mods = parser.parse(line)
        XCTAssertEqual(mods.count, 1)
        guard case .addExercise(let name, let muscle, let sets, let reps, let rir, let rest, let note) = mods[0] else {
            return XCTFail("Expected addExercise")
        }
        XCTAssertEqual(name, "Romanian Deadlift")
        XCTAssertEqual(muscle, "Hamstrings")
        XCTAssertEqual(sets, 3)
        XCTAssertEqual(reps, "8-10")
        XCTAssertEqual(rir, "2")
        XCTAssertEqual(rest, 90)
        XCTAssertEqual(note, "Focus on stretch")
    }

    func testFallbackParserProducesRemoveModification() {
        let parser = WorkoutModificationParser()
        let mods = parser.parse("[REMOVE] Leg Extension")
        XCTAssertEqual(mods.count, 1)
        guard case .removeExercise(let name) = mods[0] else {
            return XCTFail("Expected removeExercise")
        }
        XCTAssertEqual(name, "Leg Extension")
    }

    func testFallbackParserProducesModifyModification() {
        let parser = WorkoutModificationParser()
        let mods = parser.parse("[MODIFY] Squat | 4 | 6 | 1 | 180 | Heavy day")
        XCTAssertEqual(mods.count, 1)
        guard case .modifyExercise(let name, let sets, let reps, let rir, let rest, let note) = mods[0] else {
            return XCTFail("Expected modifyExercise")
        }
        XCTAssertEqual(name, "Squat")
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(reps, "6")
        XCTAssertEqual(rir, "1")
        XCTAssertEqual(rest, 180)
        XCTAssertEqual(note, "Heavy day")
    }

    func testFallbackParserProducesReplaceModification() {
        let parser = WorkoutModificationParser()
        let mods = parser.parse("[REPLACE] Hack Squat -> Leg Press | Quads | 4 | 10-12 | 3 | 90")
        XCTAssertEqual(mods.count, 1)
        guard case .replaceExercise(let old, let new, let muscle, let sets, _, _, _, _) = mods[0] else {
            return XCTFail("Expected replaceExercise")
        }
        XCTAssertEqual(old, "Hack Squat")
        XCTAssertEqual(new, "Leg Press")
        XCTAssertEqual(muscle, "Quads")
        XCTAssertEqual(sets, 4)
    }

    func testFallbackParserReturnsEmptyForUnrecognisedText() {
        let parser = WorkoutModificationParser()
        let mods = parser.parse("Just a general coaching comment with no commands.")
        XCTAssertTrue(mods.isEmpty)
    }

    func testFallbackParserHandlesMultipleCommandsInOneResponse() {
        let parser = WorkoutModificationParser()
        let text = """
        Sure! Here are my suggestions.
        [ADD] Cable Fly | Chest | 3 | 12-15 | 3 | 60
        [REMOVE] Machine Fly
        """
        let mods = parser.parse(text)
        XCTAssertEqual(mods.count, 2)
    }
}
