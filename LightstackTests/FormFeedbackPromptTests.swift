import XCTest
@testable import Lightstack

/// Tests for RepQuality.isGood, FormAnalysisResult.repSummaryForPrompt(), and
/// FormFeedbackService.buildUserPrompt(from:). No network calls are made.
final class FormFeedbackPromptTests: XCTestCase {

    // MARK: - RepQuality.isGood

    /// isGood requires both: flags.isEmpty AND romPercent >= 70.
    func testIsGoodTrueWhenNoFlagsAndRomAtOrAboveSeventy() {
        let rep = RepQuality(repNumber: 1, romPercent: 70, symmetryScore: 90, durationSeconds: 2.0, flags: [])
        XCTAssertTrue(rep.isGood)
    }

    func testIsGoodTrueWhenRomWellAboveSeventyAndNoFlags() {
        let rep = RepQuality(repNumber: 1, romPercent: 95, symmetryScore: 100, durationSeconds: 2.0, flags: [])
        XCTAssertTrue(rep.isGood)
    }

    func testIsGoodFalseWhenRomBelowSeventy() {
        let rep = RepQuality(repNumber: 1, romPercent: 69.9, symmetryScore: 90, durationSeconds: 2.0, flags: [])
        XCTAssertFalse(rep.isGood)
    }

    func testIsGoodFalseWhenFlagsPresentEvenWithFullRom() {
        let rep = RepQuality(repNumber: 1, romPercent: 100, symmetryScore: 90, durationSeconds: 2.0, flags: ["Too fast"])
        XCTAssertFalse(rep.isGood)
    }

    // MARK: - FormAnalysisResult.repSummaryForPrompt()

    func testRepSummaryForPromptWithNoRepsReturnsExactString() {
        let result = FormAnalysisResult(exerciseName: "Squat", repCount: 0, repQualities: [])
        XCTAssertEqual(result.repSummaryForPrompt(), "No reps detected.")
    }

    func testRepSummaryForPromptFormatsGoodRep() {
        let rep = RepQuality(repNumber: 1, romPercent: 85, symmetryScore: 92, durationSeconds: 2.345, flags: [])
        let result = FormAnalysisResult(exerciseName: "Squat", repCount: 1, repQualities: [rep])

        XCTAssertEqual(result.repSummaryForPrompt(), "Rep 1: ROM 85%, symmetry 92%, 2.3s, good form")
    }

    func testRepSummaryForPromptFormatsFlaggedRepAndJoinsMultipleReps() {
        let rep1 = RepQuality(repNumber: 1, romPercent: 85, symmetryScore: 92, durationSeconds: 2.345, flags: [])
        let rep2 = RepQuality(repNumber: 2, romPercent: 60, symmetryScore: 70, durationSeconds: 0.5, flags: ["Shallow depth", "Too fast"])
        let result = FormAnalysisResult(exerciseName: "Squat", repCount: 2, repQualities: [rep1, rep2])

        let expected = "Rep 1: ROM 85%, symmetry 92%, 2.3s, good form\nRep 2: ROM 60%, symmetry 70%, 0.5s, Shallow depth, Too fast"
        XCTAssertEqual(result.repSummaryForPrompt(), expected)
    }

    // MARK: - FormAnalysisResult.goodRepCount

    func testGoodRepCountCountsOnlyGoodReps() {
        let goodRep = RepQuality(repNumber: 1, romPercent: 80, symmetryScore: 90, durationSeconds: 2.0, flags: [])
        let badRep = RepQuality(repNumber: 2, romPercent: 50, symmetryScore: 70, durationSeconds: 1.0, flags: ["Shallow depth"])
        let result = FormAnalysisResult(exerciseName: "Squat", repCount: 2, repQualities: [goodRep, badRep])

        XCTAssertEqual(result.goodRepCount, 1)
    }

    // MARK: - FormFeedbackService.buildUserPrompt(from:)

    func testBuildUserPromptContainsExerciseNameAndGoodRepSummary() {
        let goodRep = RepQuality(repNumber: 1, romPercent: 90, symmetryScore: 95, durationSeconds: 2.0, flags: [])
        let badRep = RepQuality(repNumber: 2, romPercent: 50, symmetryScore: 70, durationSeconds: 1.0, flags: ["Shallow depth"])
        let result = FormAnalysisResult(exerciseName: "Barbell Squat", repCount: 2, repQualities: [goodRep, badRep])

        let prompt = FormFeedbackService.buildUserPrompt(from: result)

        XCTAssertTrue(prompt.contains("Exercise: Barbell Squat"))
        XCTAssertTrue(prompt.contains("Total reps detected: 2"))
        XCTAssertTrue(prompt.contains("Good reps: 1/2"))
        XCTAssertTrue(prompt.contains("Rep 1: ROM 90%, symmetry 95%, 2.0s, good form"))
        XCTAssertTrue(prompt.contains("Rep 2: ROM 50%, symmetry 70%, 1.0s, Shallow depth"))
    }

    func testBuildUserPromptWithNoRepsIncludesNoRepsDetected() {
        let result = FormAnalysisResult(exerciseName: "Push Up", repCount: 0, repQualities: [])

        let prompt = FormFeedbackService.buildUserPrompt(from: result)

        XCTAssertTrue(prompt.contains("Exercise: Push Up"))
        XCTAssertTrue(prompt.contains("Total reps detected: 0"))
        XCTAssertTrue(prompt.contains("Good reps: 0/0"))
        XCTAssertTrue(prompt.contains("No reps detected."))
    }
}
