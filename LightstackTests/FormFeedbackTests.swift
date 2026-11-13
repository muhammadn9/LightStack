import XCTest
import AVFoundation
@testable import Lightstack

// MARK: - Fixtures

private enum FormFixtures {

    static func rep(_ n: Int, range: Double = 100, flags: [FormCheckKind] = []) -> RepSummary {
        let start = Double(n) * 3
        return RepSummary(
            rep: DetectedRep(number: n, start: start, peak: start + 1, end: start + 2,
                             restAngle: 170, peakAngle: 80, amplitudeDegrees: 90),
            rangePercent: range, flags: flags)
    }

    static func analysis(reps: [RepSummary], name: String = "Back Squat", status: TrackingStatus = .good,
                         tracked: Bool = true, score: Int? = 88) -> FormAnalysis {
        let profile = tracked ? MovementProfileLibrary.squat : MovementProfileLibrary.untracked
        let detection = RepDetection(reps: reps.map(\.rep), angle: .knee, side: .left, trackingQuality: 0.9,
                                     status: status, signal: [], otherSide: nil)
        return FormAnalysis(exerciseName: name, profile: profile, detection: detection, reps: reps,
                            findings: [], score: score)
    }

    static func track(duration: Double = 10, aspect: Double = 9.0 / 16.0) -> PoseTrack {
        let frames = stride(from: 0.0, through: duration, by: 0.1).map { t -> PoseFrame in
            PoseFrame(time: t, joints: [
                .leftShoulder: PosePoint(x: 0.5, y: 0.3, confidence: 1),
                .leftHip: PosePoint(x: 0.5, y: 0.55, confidence: 1),
                .leftKnee: PosePoint(x: 0.55, y: 0.7, confidence: 1),
                .leftAnkle: PosePoint(x: 0.5, y: 0.9, confidence: 1)
            ])
        }
        return PoseTrack(frames: frames, aspectRatio: aspect)
    }

    static func result(reps: [RepSummary], videoURL: URL? = nil, status: TrackingStatus = .good) -> FormSessionResult {
        FormSessionResult(exerciseName: "Back Squat", analysis: analysis(reps: reps, status: status),
                          track: track(), videoURL: videoURL, cameraPosition: .back)
    }

    /// A tiny solid-colour movie, `seconds` long.
    static func makeMovie(seconds: Double = 2, size: CGSize = CGSize(width: 160, height: 288)) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("formtest-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps = 30
        for i in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw NSError(domain: "test", code: 1) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let shade = UInt8(40 + (i * 5) % 160)
                memset(base, Int32(shade), CVPixelBufferGetBytesPerRow(buffer) * Int(size.height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "test", code: 2) }
        return url
    }
}

private final class FakeProvider: AIProvider {
    let name = "FormFake"
    let rateLimitKey = "form_fake_rate_limit_\(UUID().uuidString)"
    var isAvailable: Bool { true }
    var nextAvailableTime: Date? { nil }
    var result: Result<String, Error>
    private(set) var messages: [ChatMessage] = []
    private(set) var lastOptions: AIRequestOptions?
    init(_ result: Result<String, Error>) { self.result = result }
    func markRateLimited(until: Date) {}
    func clearRateLimit() {}
    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                      completion: @escaping (Result<String, Error>) -> Void) {
        self.messages = messages
        completion(result)
    }
    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool, options: AIRequestOptions,
                      completion: @escaping (Result<String, Error>) -> Void) {
        lastOptions = options
        generateChat(systemPrompt: systemPrompt, messages: messages, expectsJSON: expectsJSON, completion: completion)
    }
}

private struct StubFeedbackProvider: FormFeedbackProviding {
    var replies: Box
    final class Box { var queue: [FormFeedback?]; var calls = 0; init(_ q: [FormFeedback?]) { queue = q } }
    func feedback(for result: FormSessionResult) async -> FormFeedback? {
        replies.calls += 1
        return replies.queue.isEmpty ? nil : replies.queue.removeFirst()
    }
}

// MARK: - Moment selection

final class FormKeyFrameSelectionTests: XCTestCase {

    private func select(_ reps: [RepSummary], duration: Double = 60) -> [KeyMoment] {
        FormKeyFrameSheet.selectMoments(analysis: FormFixtures.analysis(reps: reps), duration: duration)
    }

    func testNoRepsGivesEightEvenlySpacedMomentsInTheMiddle() {
        let moments = select([], duration: 20)
        XCTAssertEqual(moments.count, 8)
        XCTAssertEqual(moments.first?.time ?? -1, 1.0, accuracy: 0.001)   // 5%
        XCTAssertEqual(moments.last?.time ?? -1, 19.0, accuracy: 0.001)   // 95%
        XCTAssertEqual(moments.first?.label, "0:01")
        XCTAssertEqual(moments.last?.label, "0:19")
        XCTAssertEqual(moments.map(\.time), moments.map(\.time).sorted())
    }

    func testZeroDurationGivesNoMoments() {
        XCTAssertTrue(select([], duration: 0).isEmpty)
    }

    func testOneRepGivesStartAndPeak() {
        let moments = select([FormFixtures.rep(1)])
        XCTAssertEqual(moments.map(\.label), ["Rep 1 start", "Rep 1 peak"])
        XCTAssertEqual(moments.map(\.time), [3, 4])
    }

    func testThreeRepsUseAllThree() {
        let moments = select([FormFixtures.rep(1), FormFixtures.rep(2), FormFixtures.rep(3)])
        XCTAssertEqual(moments.count, 6)
        XCTAssertEqual(moments.map(\.label).filter { $0.hasSuffix("start") }.count, 3)
    }

    func testTwelveRepsPickFirstLastWorstAndMiddleCappedAtEight() {
        let reps = (1...12).map { FormFixtures.rep($0, range: $0 == 7 ? 55 : 100, flags: $0 == 7 ? [.rangeConsistency] : []) }
        let moments = select(reps)
        XCTAssertEqual(moments.count, 8)
        let labels = moments.map(\.label)
        XCTAssertTrue(labels.contains("Rep 1 start"))
        XCTAssertTrue(labels.contains("Rep 12 peak"))
        XCTAssertTrue(labels.contains("Rep 7 start"), "the flagged rep must be included")
        // Four distinct reps, the fourth being a middle one (not first, last or the flagged rep).
        let numbers = Set(labels.compactMap { $0.split(separator: " ").dropFirst().first.flatMap { Int($0) } })
        XCTAssertEqual(numbers.count, 4)
        XCTAssertEqual(moments.map(\.time), moments.map(\.time).sorted())
        XCTAssertEqual(Set(moments.map(\.time)).count, moments.count)
    }

    func testWorstWithoutFlagsIsTheShortestRep() {
        let reps = (1...6).map { FormFixtures.rep($0, range: $0 == 2 ? 70 : 100) }
        XCTAssertTrue(select(reps).map(\.label).contains("Rep 2 peak"))
    }

    func testMomentsAreClampedToTheRecording() {
        let moments = select([FormFixtures.rep(1), FormFixtures.rep(2)], duration: 5)
        XCTAssertTrue(moments.allSatisfy { $0.time <= 5 })
        XCTAssertEqual(Set(moments.map { Int($0.time * 100) }).count, moments.count, "no duplicate times after clamping")
    }

    func testRenderSmokeTestProducesAJPEG() async throws {
        let url = try await FormFixtures.makeMovie()
        defer { try? FileManager.default.removeItem(at: url) }
        let moments = [KeyMoment(time: 0.2, label: "Rep 1 start"), KeyMoment(time: 0.9, label: "Rep 1 peak"),
                       KeyMoment(time: 1.5, label: "Rep 2 start")]
        let data = await FormKeyFrameSheet.render(videoURL: url, track: FormFixtures.track(duration: 2), moments: moments,
                                                  highlighted: FormKeyFrameSheet.highlightedJoints(for: MovementProfileLibrary.squat))
        let jpeg = try XCTUnwrap(data)
        XCTAssertGreaterThan(jpeg.count, 1_000)
        XCTAssertLessThan(jpeg.count, 1_000_000)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
        let image = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(image.size.width, 3 * 160, accuracy: 1)   // three tiles in one row
        XCTAssertGreaterThan(image.size.height, 288)   // frame plus its label strip
        XCTAssertLessThan(image.size.height, 288 + 40)
    }

    func testRenderReturnsNilForMissingMovie() async {
        let data = await FormKeyFrameSheet.render(videoURL: URL(fileURLWithPath: "/nonexistent.mov"),
                                                  track: FormFixtures.track(), moments: [KeyMoment(time: 1, label: "x")],
                                                  highlighted: [])
        XCTAssertNil(data)
    }
}

// MARK: - Prompt, parse, service

final class FormFeedbackServiceTests: XCTestCase {

    func testPromptCarriesExerciseRepTableCuesStatusAndImageWording() {
        let reps = [FormFixtures.rep(1), FormFixtures.rep(2, range: 60, flags: [.rangeConsistency])]
        let analysis = FormFixtures.analysis(reps: reps)
        let withImage = FormFeedbackService.buildUserPrompt(analysis: analysis, hasImage: true)
        XCTAssertTrue(withImage.contains("Back Squat"))
        XCTAssertTrue(withImage.contains("Rep | start s"))
        XCTAssertTrue(withImage.contains("Tracking status: good"))
        XCTAssertTrue(withImage.contains("Measured rep count: 2"))
        for cue in MovementProfileLibrary.squat.cues { XCTAssertTrue(withImage.contains(cue)) }
        XCTAssertTrue(withImage.contains("IMAGE: attached"))
        let noImage = FormFeedbackService.buildUserPrompt(analysis: analysis, hasImage: false)
        XCTAssertTrue(noImage.contains("IMAGE: none"))
        XCTAssertFalse(noImage.contains("IMAGE: attached"))
    }

    func testPromptForUntrackedExerciseHasNoMeasuredCount() {
        let analysis = FormFixtures.analysis(reps: [], name: "Cable Fly", status: .insufficient, tracked: false, score: nil)
        let prompt = FormFeedbackService.buildUserPrompt(analysis: analysis, hasImage: true)
        XCTAssertTrue(prompt.contains("not tracked"))
        XCTAssertTrue(prompt.contains("Tracking status: insufficient"))
        XCTAssertFalse(prompt.contains("Measured rep count"))
    }

    func testSystemPromptStatesTheRules() {
        let p = FormFeedbackService.systemPrompt
        for needle in ["estimatedReps", "No em dashes", "At most 3 fixes", "12 words", "Never invent a problem", "20 words"] {
            XCTAssertTrue(p.contains(needle), needle)
        }
    }

    func testOptionsAreLowTemperatureAndRoomyEnough() {
        let o = AIRequestOptions.forTask(.formFeedback)
        XCTAssertEqual(o.maxOutputTokens, 1200)
        XCTAssertLessThanOrEqual(o.temperature, 0.3)
    }

    func testParseCleanJSON() throws {
        let text = """
        {"verdict":"Solid set.","positives":["Good depth"],"fixes":[{"title":"Knees cave","why":"Rep 3 knees moved in.","cue":"Push knees out.","reps":[3]}],"estimatedReps":null}
        """
        let f = try XCTUnwrap(FormFeedbackService.parse(text))
        XCTAssertEqual(f.verdict, "Solid set.")
        XCTAssertEqual(f.positives, ["Good depth"])
        XCTAssertEqual(f.fixes.count, 1)
        XCTAssertEqual(f.fixes[0].reps, [3])
        XCTAssertEqual(f.fixes[0].id, "fix-1")
        XCTAssertNil(f.estimatedReps)
    }

    func testParseFencedJSONWithExtraKeysAndEstimate() throws {
        let text = """
        Here you go:
        ```json
        {"verdict":" Looks fine. ","positives":[],"fixes":[],"estimatedReps":8,"confidence":0.4,"notes":"x"}
        ```
        """
        let f = try XCTUnwrap(FormFeedbackService.parse(text))
        XCTAssertEqual(f.verdict, "Looks fine.")
        XCTAssertTrue(f.fixes.isEmpty)
        XCTAssertEqual(f.estimatedReps, 8)
    }

    func testParseClampsAndCleans() throws {
        let fix = { (i: Int) in "{\"title\":\"Fix \(i)\",\"why\":\"Why \(i) \u{2014} yes\",\"cue\":\"Cue\",\"reps\":[2,2,1,0]}" }
        let text = """
        {"verdict":"V","positives":["a","b","c"],"fixes":[\(fix(1)),{"title":"","why":"x","cue":"y","reps":[]},\(fix(2)),\(fix(3)),\(fix(4))]}
        """
        let f = try XCTUnwrap(FormFeedbackService.parse(text))
        XCTAssertEqual(f.positives, ["a", "b"])
        XCTAssertEqual(f.fixes.map(\.title), ["Fix 1", "Fix 2", "Fix 3"])
        XCTAssertEqual(f.fixes.map(\.id), ["fix-1", "fix-2", "fix-3"])
        XCTAssertEqual(f.fixes[0].reps, [1, 2])
        XCTAssertFalse(f.fixes[0].why.contains("\u{2014}"))
    }

    func testParseGarbageIsNil() {
        XCTAssertNil(FormFeedbackService.parse("I can't help with that."))
        XCTAssertNil(FormFeedbackService.parse("{\"unrelated\": 1}"))
        XCTAssertNil(FormFeedbackService.parse(""))
    }

    func testServiceReturnsNilWhenProviderFails() async {
        let provider = FakeProvider(.failure(NSError(domain: "x", code: 1)))
        let service = FormFeedbackService(aiServiceManager: AIServiceManager(providers: [provider]))
        let f = await service.feedback(for: FormFixtures.result(reps: [FormFixtures.rep(1)]))
        XCTAssertNil(f)
    }

    func testServiceReturnsNilOnUnparseableReply() async {
        let provider = FakeProvider(.success("not json"))
        let service = FormFeedbackService(aiServiceManager: AIServiceManager(providers: [provider]))
        let f = await service.feedback(for: FormFixtures.result(reps: [FormFixtures.rep(1)]))
        XCTAssertNil(f)
    }

    func testServiceSendsTextOnlyWithoutVideoAndParsesReply() async throws {
        let provider = FakeProvider(.success("{\"verdict\":\"Good.\",\"positives\":[],\"fixes\":[]}"))
        let service = FormFeedbackService(aiServiceManager: AIServiceManager(providers: [provider]))
        let f = await service.feedback(for: FormFixtures.result(reps: [FormFixtures.rep(1)]))
        XCTAssertEqual(f?.verdict, "Good.")
        let message = try XCTUnwrap(provider.messages.first)
        XCTAssertNil(message.imageJPEG)
        XCTAssertTrue(message.content.contains("IMAGE: none"))
        XCTAssertEqual(provider.lastOptions?.task, .formFeedback)
        XCTAssertNotNil(provider.lastOptions?.schema)
    }

    func testServiceAttachesTheContactSheetWhenThereIsAMovie() async throws {
        let url = try await FormFixtures.makeMovie()
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = FakeProvider(.success("{\"verdict\":\"Good.\",\"positives\":[],\"fixes\":[]}"))
        let service = FormFeedbackService(aiServiceManager: AIServiceManager(providers: [provider]))
        _ = await service.feedback(for: FormFixtures.result(reps: [FormFixtures.rep(0, range: 100)], videoURL: url))
        let message = try XCTUnwrap(provider.messages.first)
        XCTAssertNotNil(message.imageJPEG)
        XCTAssertTrue(message.content.contains("IMAGE: attached"))
    }
}

// MARK: - Lookup and view model

@MainActor
final class FormResultsViewModelTests: XCTestCase {

    func testNearestFrameBinarySearch() {
        let track = PoseTrack(frames: [0, 1, 2, 4].map { PoseFrame(time: $0, joints: [:]) }, aspectRatio: 0.5)
        XCTAssertEqual(track.nearestFrame(to: -3)?.time, 0)
        XCTAssertEqual(track.nearestFrame(to: 0.4)?.time, 0)
        XCTAssertEqual(track.nearestFrame(to: 0.6)?.time, 1)
        XCTAssertEqual(track.nearestFrame(to: 2.9)?.time, 2)
        XCTAssertEqual(track.nearestFrame(to: 3.1)?.time, 4)
        XCTAssertEqual(track.nearestFrame(to: 99)?.time, 4)
        XCTAssertNil(track.nearestFrame(to: 3, maxGap: 0.5), "gap of 1 s is too far")
        XCTAssertNil(PoseTrack(frames: [], aspectRatio: 1).nearestFrame(to: 1))
    }

    private func feedback(estimated: Int? = nil) -> FormFeedback {
        FormFeedback(verdict: "Good.", positives: [], fixes: [
            FormFix(id: "fix-1", title: "T", why: "W", cue: "C", reps: [9, 2, 3])
        ], estimatedReps: estimated)
    }

    private func model(_ queue: [FormFeedback?], reps: [RepSummary] = [FormFixtures.rep(1), FormFixtures.rep(2), FormFixtures.rep(3)])
        -> (FormResultsViewModel, StubFeedbackProvider.Box) {
        let box = StubFeedbackProvider.Box(queue)
        return (FormResultsViewModel(result: FormFixtures.result(reps: reps), provider: StubFeedbackProvider(replies: box)), box)
    }

    func testFeedbackIsRequestedOnlyOnce() async {
        let (vm, box) = model([feedback()])
        vm.loadFeedbackIfNeeded()
        vm.loadFeedbackIfNeeded()
        await vm.waitForFeedback()
        vm.loadFeedbackIfNeeded()
        await vm.waitForFeedback()
        XCTAssertEqual(box.calls, 1)
        XCTAssertNotNil(vm.feedback)
        XCTAssertFalse(vm.isLoadingFeedback)
        XCTAssertFalse(vm.feedbackFailed)
    }

    func testRetryAfterFailureLoadsFeedback() async {
        let (vm, box) = model([nil, feedback()])
        vm.loadFeedbackIfNeeded()
        await vm.waitForFeedback()
        XCTAssertTrue(vm.feedbackFailed)
        XCTAssertNil(vm.feedback)
        vm.retryFeedback()
        await vm.waitForFeedback()
        XCTAssertEqual(box.calls, 2)
        XCTAssertNotNil(vm.feedback)
        XCTAssertFalse(vm.feedbackFailed)
        vm.retryFeedback()   // already has feedback: no third call
        XCTAssertEqual(box.calls, 2)
    }

    func testSeekTargetIsFirstExistingAffectedRepsPeak() {
        let (vm, _) = model([])
        let fix = FormFix(id: "f", title: "", why: "", cue: "", reps: [9, 2, 3])
        XCTAssertEqual(vm.seekTime(for: fix), 7)   // rep 2: start 6, peak 7
        XCTAssertNil(vm.seekTime(for: FormFix(id: "g", title: "", why: "", cue: "", reps: [])))
        XCTAssertNil(vm.seekTime(for: FormFix(id: "h", title: "", why: "", cue: "", reps: [50])))
    }

    func testLeadInIsThreeTenthsBeforeAndNeverNegative() {
        XCTAssertEqual(FormReplayController.leadInTime(for: 7), 6.7, accuracy: 1e-9)
        XCTAssertEqual(FormReplayController.leadInTime(for: 0.1), 0)
    }

    func testSeekToMomentPlaysAtHalfSpeed() {
        let (vm, _) = model([])
        vm.seek(toRepStart: 2)
        XCTAssertEqual(vm.replay.speed, 0.5)
        XCTAssertTrue(vm.replay.isPlaying)
        XCTAssertEqual(vm.replay.currentTime, 5.7, accuracy: 1e-6)
        vm.teardown()
    }

    func testEstimatedRepsDisplayRule() {
        XCTAssertEqual(FormResultsViewModel.repDisplay(measured: 5, estimated: 9).value, "5")
        XCTAssertEqual(FormResultsViewModel.repDisplay(measured: 0, estimated: 8).value, "~8")
        XCTAssertEqual(FormResultsViewModel.repDisplay(measured: 0, estimated: 8).caption, "Reps (AI estimate)")
        XCTAssertEqual(FormResultsViewModel.repDisplay(measured: 0, estimated: nil).value, "0")
        XCTAssertEqual(FormResultsViewModel.repDisplay(measured: 0, estimated: 0).value, "0")
    }

    func testFindingsSortMostSevereFirst() {
        func f(_ id: String, _ s: FindingSeverity) -> FormFinding {
            FormFinding(id: id, kind: .tempoControl, severity: s, title: id, detail: "", cue: "", reps: [], time: nil)
        }
        let analysis = FormAnalysis(exerciseName: "x", profile: MovementProfileLibrary.squat,
                                    detection: RepDetection.insufficient(angle: .knee, quality: 1), reps: [],
                                    findings: [f("a", .good), f("b", .major), f("c", .minor), f("d", .major)], score: nil)
        let result = FormSessionResult(exerciseName: "x", analysis: analysis, track: FormFixtures.track(), videoURL: nil,
                                       cameraPosition: .back)
        let vm = FormResultsViewModel(result: result, provider: StubFeedbackProvider(replies: .init([])))
        XCTAssertEqual(vm.sortedFindings.map(\.id), ["b", "d", "c", "a"])
    }
}

final class FormFeedbackUITestFakeTests: XCTestCase {
    func testUITestFakeProviderReturnsParseableFeedback() async throws {
        let service = FormFeedbackService(aiServiceManager: AIServiceManager(providers: [UITestFakeAIProvider()]))
        let reply = await service.feedback(for: FormFixtures.result(reps: [FormFixtures.rep(1)]))
        let f = try XCTUnwrap(reply)
        XCTAssertTrue(f.verdict.contains("Steady set"))
        XCTAssertEqual(f.fixes.count, 2)
        XCTAssertEqual(f.fixes[0].reps, [4, 5])
    }
}
