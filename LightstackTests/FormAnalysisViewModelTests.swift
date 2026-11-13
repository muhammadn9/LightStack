import XCTest
import AVFoundation
import Combine
@testable import Lightstack

@MainActor
private final class FakePoseSource: PoseSource {
    let subject = PassthroughSubject<PoseFrame?, Never>()
    let denied = CurrentValueSubject<Bool, Never>(false)
    let interruptions = PassthroughSubject<Void, Never>()
    var framePublisher: AnyPublisher<PoseFrame?, Never> { subject.eraseToAnyPublisher() }
    var aspectRatio: Double { SyntheticPoseSource.aspect }
    var previewSession: AVCaptureSession? { nil }
    var permissionDenied: Bool { denied.value }
    var permissionDeniedPublisher: AnyPublisher<Bool, Never> { denied.eraseToAnyPublisher() }
    var interruptionPublisher: AnyPublisher<Void, Never> { interruptions.eraseToAnyPublisher() }
    var cameraPosition: AVCaptureDevice.Position = .back

    var startCount = 0, stopCount = 0, flipCount = 0, startRecordingCount = 0, stopRecordingCount = 0
    var movieToReturn: URL?

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func flipCamera() { flipCount += 1 }
    func startRecording() { startRecordingCount += 1 }
    func stopRecording() async -> URL? { stopRecordingCount += 1; return movieToReturn }

    func send(_ frame: PoseFrame?) { subject.send(frame) }
}

@MainActor
final class FormAnalysisViewModelTests: XCTestCase {

    private func makeModel(tick: Duration = .milliseconds(5)) -> (FormAnalysisViewModel, FakePoseSource) {
        let source = FakePoseSource()
        return (FormAnalysisViewModel(source: source, countdownTick: tick), source)
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func feed(_ source: FakePoseSource, from start: Double, to end: Double) {
        for t in stride(from: start, through: end, by: 1 / SyntheticPoseSource.frameRate) {
            source.send(SyntheticPoseSource.frame(at: t))
        }
    }

    private func record(_ model: FormAnalysisViewModel) async {
        model.startCountdown()
        await waitUntil { model.phase == .recording }
        XCTAssertEqual(model.phase, .recording)
    }

    func testPrepareStartsSourceAndShowsSetup() {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        XCTAssertEqual(model.phase, .setup)
        XCTAssertEqual(source.startCount, 1)
        XCTAssertTrue(model.profile.isTracked)
        XCTAssertFalse(model.setupStatus.isReady)
    }

    func testSetupStatusBecomesReadyWhenArmsAreVisible() {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        feed(source, from: 100, to: 102)
        XCTAssertTrue(model.setupStatus.isReady)
        XCTAssertEqual(model.recordedFrameCount, 0)
    }

    func testUntrackedExerciseExplainsAndStillRecords() async {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Plank")
        XCTAssertFalse(model.profile.isTracked)
        XCTAssertTrue(model.setupStatus.message.contains("isn't available"))
        XCTAssertTrue(model.highlightedJoints.isEmpty)
        await record(model)
        XCTAssertEqual(source.startRecordingCount, 1)
    }

    func testCountdownTicksDownThenRecords() async {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        model.startCountdown()
        XCTAssertEqual(model.phase, .countdown(FormAnalysisViewModel.countdownSeconds))
        await waitUntil { model.phase == .recording }
        XCTAssertEqual(model.phase, .recording)
        XCTAssertEqual(source.startRecordingCount, 1)
    }

    func testCancelCountdownReturnsToSetupWithoutRecording() async {
        let (model, source) = makeModel(tick: .seconds(1))
        model.prepare(exerciseName: "Lateral Raise")
        model.startCountdown()
        XCTAssertEqual(model.phase, .countdown(5))
        model.cancelCountdown()
        XCTAssertEqual(model.phase, .setup)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.phase, .setup)
        XCTAssertEqual(source.startRecordingCount, 0)
    }

    func testFramesAreAppendedOnlyWhileRecording() async {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        feed(source, from: 50, to: 51)
        XCTAssertEqual(model.recordedFrameCount, 0)

        await record(model)
        feed(source, from: 0, to: 1)
        let during = model.recordedFrameCount
        XCTAssertGreaterThan(during, 10)
        source.send(nil)   // a gap is represented as an empty frame
        XCTAssertEqual(model.recordedFrameCount, during + 1)
    }

    func testStaleFirstFrameFromOldClockIsDropped() async {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        await record(model)
        source.send(SyntheticPoseSource.frame(at: 4_000))
        XCTAssertEqual(model.recordedFrameCount, 0)
        source.send(SyntheticPoseSource.frame(at: 0.1))
        XCTAssertEqual(model.recordedFrameCount, 1)
    }

    func testFinishProducesResultWithExpectedReps() async {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        await record(model)
        feed(source, from: 0, to: 12)
        model.finish()
        XCTAssertEqual(model.phase, .analyzing)
        await waitUntil { model.phase == .done }
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.result?.analysis.repCount, 5)
        XCTAssertEqual(model.result?.exerciseName, "Lateral Raise")
        XCTAssertEqual(source.stopRecordingCount, 1)
        XCTAssertGreaterThanOrEqual(source.stopCount, 1)
    }

    func testLiveRepCountRisesWhileRecording() async {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        await record(model)
        for t in stride(from: 0.0, through: 9, by: 1 / SyntheticPoseSource.frameRate) {
            source.send(SyntheticPoseSource.frame(at: t))
        }
        await model.refreshLiveRepCount()
        XCTAssertGreaterThanOrEqual(model.liveRepCount, 1)
    }

    func testTooShortRecordingReturnsToSetupWithMessage() async {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        await record(model)
        feed(source, from: 0, to: 0.5)
        model.finish()
        await waitUntil { model.phase == .setup }
        XCTAssertEqual(model.phase, .setup)
        XCTAssertNil(model.result)
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(source.stopRecordingCount, 1)
    }

    func testInterruptionWhileRecordingActsLikeDone() async {
        let (model, source) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        await record(model)
        feed(source, from: 0, to: 6)
        source.interruptions.send()
        await waitUntil { model.phase == .done }
        XCTAssertEqual(model.phase, .done)
    }

    func testInterruptionDuringCountdownCancelsIt() {
        let (model, source) = makeModel(tick: .seconds(1))
        model.prepare(exerciseName: "Lateral Raise")
        model.startCountdown()
        source.interruptions.send()
        XCTAssertEqual(model.phase, .setup)
    }

    func testFlipOnlyAllowedInSetup() async {
        let (model, source) = makeModel(tick: .seconds(1))
        model.prepare(exerciseName: "Lateral Raise")
        model.flipCamera()
        XCTAssertEqual(source.flipCount, 1)
        model.startCountdown()
        model.flipCamera()
        XCTAssertEqual(source.flipCount, 1)
    }

    func testCancelDeletesMovieAndStopsSource() async throws {
        let (model, source) = makeModel()
        let movie = FileManager.default.temporaryDirectory.appendingPathComponent("form-\(UUID().uuidString).mp4")
        try Data([1, 2, 3]).write(to: movie)
        source.movieToReturn = movie
        model.prepare(exerciseName: "Lateral Raise")
        await record(model)
        model.cancel()
        await waitUntil { !FileManager.default.fileExists(atPath: movie.path) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: movie.path))
        XCTAssertEqual(model.phase, .setup)
        XCTAssertGreaterThanOrEqual(source.stopCount, 1)
    }

    func testDiscardResultDeletesMovie() async throws {
        let (model, source) = makeModel()
        let movie = FileManager.default.temporaryDirectory.appendingPathComponent("form-\(UUID().uuidString).mp4")
        try Data([1, 2, 3]).write(to: movie)
        source.movieToReturn = movie
        model.prepare(exerciseName: "Lateral Raise")
        await record(model)
        feed(source, from: 0, to: 12)
        model.finish()
        await waitUntil { model.phase == .done }
        XCTAssertEqual(model.result?.videoURL, movie)
        model.discardResult()
        XCTAssertFalse(FileManager.default.fileExists(atPath: movie.path))
        XCTAssertNil(model.result)
    }

    func testPrepareRemovesLeftoverMovies() throws {
        let leftover = FileManager.default.temporaryDirectory.appendingPathComponent("form-\(UUID().uuidString).mp4")
        try Data([1]).write(to: leftover)
        let (model, _) = makeModel()
        model.prepare(exerciseName: "Lateral Raise")
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    }
}
