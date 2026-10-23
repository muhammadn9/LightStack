import XCTest
import Supabase
@testable import Lightstack

// MARK: - Expired session

final class SessionExpiryTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!
    private let userA = UUID()
    private let userB = UUID()

    override func setUp() {
        super.setUp()
        suite = "expiry-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAuthErrorsAreRecognisedAsSessionLoss() {
        XCTAssertTrue(SyncErrorClassifier.isSessionRejected(QueueTestError.postgres("PGRST301")))
        XCTAssertTrue(SyncErrorClassifier.isSessionRejected(AuthError.sessionMissing))
        XCTAssertFalse(SyncErrorClassifier.isSessionRejected(QueueTestError.offline))
        XCTAssertFalse(SyncErrorClassifier.isSessionRejected(QueueTestError.postgres("23505")))
        XCTAssertEqual(SyncErrorClassifier.classify(QueueTestError.postgres("PGRST301"), opType: .insertSet), .auth)
        XCTAssertEqual(SyncErrorClassifier.classify(AuthError.sessionMissing, opType: .insertSet), .auth)
    }

    func testSignedOutEventWeDidNotAskForMeansExpiry() {
        let now = Date()
        XCTAssertEqual(AuthService.expiredUserId(for: .signedOut, userSignOutAt: nil, lastKnownUserId: userA, now: now), userA)
        XCTAssertNil(AuthService.expiredUserId(for: .signedOut, userSignOutAt: now.addingTimeInterval(-2), lastKnownUserId: userA, now: now),
                     "a sign-out the user asked for is not an expiry")
        XCTAssertEqual(AuthService.expiredUserId(for: .signedOut, userSignOutAt: now.addingTimeInterval(-60), lastKnownUserId: userA, now: now), userA)
        XCTAssertNil(AuthService.expiredUserId(for: .tokenRefreshed, userSignOutAt: nil, lastKnownUserId: userA, now: now))
        XCTAssertNil(AuthService.expiredUserId(for: .signedOut, userSignOutAt: nil, lastKnownUserId: nil, now: now))
    }

    func testSameUserSigningInResumes() {
        let tracker = SessionExpiryTracker(defaults: defaults)
        XCTAssertFalse(tracker.isExpired)
        tracker.markExpired(userId: userA)
        XCTAssertTrue(tracker.isExpired)
        XCTAssertEqual(SessionExpiryTracker(defaults: defaults).expiredUserId, userA, "survives a relaunch")
        XCTAssertEqual(tracker.handleSignIn(userId: userA), .resumed)
        XCTAssertFalse(tracker.isExpired)
        XCTAssertEqual(tracker.handleSignIn(userId: userA), .notExpired)
    }

    func testDifferentUserSigningInDoesNotResume() {
        let tracker = SessionExpiryTracker(defaults: defaults)
        tracker.markExpired(userId: userA)
        XCTAssertEqual(tracker.handleSignIn(userId: userB), .differentUser)
        XCTAssertFalse(tracker.isExpired)
    }
}

final class ExpiredSessionOutboxTests: XCTestCase {

    private var dir: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private let user = UUID()

    override func setUp() {
        super.setUp()
        dir = makeTempDirectory()
        suite = "expired-outbox-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeQueue(remote: FakeRemote) -> OfflineQueueManager {
        let owner = user
        return OfflineQueueManager(remote: remote, directory: dir, ownerProvider: { owner },
                                   defaults: defaults, autoFlush: false)
    }

    func testAuthFailureIsReportedKeepsEveryChangeAndResumesAfterSignIn() async {
        let remote = FakeRemote()
        let signedOut = TestBox(true)
        remote.script = { _, _ in signedOut.value ? QueueTestError.postgres("PGRST301") : nil }
        let authFailures = TestBox(0)
        let queue = makeQueue(remote: remote)
        await queue.setObservers(onChange: nil, onAuthFailure: { authFailures.value += 1 })
        for label in ["a", "b", "c"] { await queue.enqueue(.insertWorkout, payload: makeTestWorkout(label, userId: user)) }

        await queue.flush()
        XCTAssertEqual(authFailures.value, 1)
        let blocked = await queue.snapshot()
        XCTAssertTrue(blocked.authBlocked)
        XCTAssertEqual(blocked.pending, 3, "nothing is dropped")
        XCTAssertNil(blocked.lastSuccessfulFlush)

        signedOut.value = false   // same user signs in again
        await queue.flush()
        let resumed = await queue.snapshot()
        XCTAssertEqual(resumed.pending, 0)
        XCTAssertFalse(resumed.authBlocked)
        XCTAssertNotNil(resumed.lastSuccessfulFlush)
        XCTAssertEqual(remote.calls.filter { $0.hasPrefix("insertWorkout") }.count, 4, "1 refused + 3 uploaded")
    }

    func testChangeObserverFiresOnEnqueueAndFlush() async {
        let remote = FakeRemote()
        let queue = makeQueue(remote: remote)
        let changes = TestBox(0)
        await queue.setObservers(onChange: { changes.value += 1 }, onAuthFailure: nil)
        await queue.enqueue(.insertWorkout, payload: makeTestWorkout("a", userId: user))
        let afterEnqueue = changes.value
        XCTAssertGreaterThan(afterEnqueue, 0)
        await queue.flush()
        XCTAssertGreaterThan(changes.value, afterEnqueue)
    }

    func testEmptyQueueFlushRecordsLastBackup() async {
        let queue = makeQueue(remote: FakeRemote())
        let before = await queue.snapshot()
        XCTAssertNil(before.lastSuccessfulFlush)
        await queue.flush()
        let after = await queue.snapshot()
        XCTAssertNotNil(after.lastSuccessfulFlush)
    }
}

// MARK: - Backup status

final class BackupStatusTests: XCTestCase {

    private let last = Date(timeIntervalSince1970: 1_800_000_000)

    private func derive(pending: Int = 0, failed: Int = 0, flushing: Bool = false, signedOut: Bool = false,
                        last: Date? = nil) -> BackupStatus {
        BackupStatus.derive(pending: pending, failed: failed, isFlushing: flushing, signedOut: signedOut, lastSuccessfulFlush: last)
    }

    func testAllBackedUp() {
        let s = derive(last: last)
        XCTAssertEqual(s, .allBackedUp(lastBackup: last))
        XCTAssertEqual(s.title, "All changes backed up")
        XCTAssertNotNil(s.subtitle(now: last.addingTimeInterval(300)))
        XCTAssertTrue(s.subtitle(now: last.addingTimeInterval(300))?.hasPrefix("Last backed up") ?? false)
        XCTAssertNil(derive().subtitle())
    }

    func testWaitingAndBackingUp() {
        XCTAssertEqual(derive(pending: 2, failed: 1), .waiting(count: 3))
        XCTAssertEqual(derive(pending: 3).title, "3 changes waiting to back up")
        XCTAssertEqual(derive(pending: 1).title, "1 change waiting to back up")
        XCTAssertEqual(derive(pending: 2, flushing: true), .backingUp)
        XCTAssertEqual(derive(pending: 2, flushing: true).title, "Backing up\u{2026}")
        XCTAssertEqual(derive(flushing: true, last: last), .allBackedUp(lastBackup: last), "an empty flush is not 'backing up'")
    }

    func testSignedOutWinsOverEverything() {
        let s = derive(pending: 4, flushing: true, signedOut: true, last: last)
        XCTAssertEqual(s, .signedOut)
        XCTAssertEqual(s.title, "Signed out \u{2014} not backing up")
    }
}

// MARK: - Diagnostics

final class DiagnosticsTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = makeTempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func entry(_ n: Int, summary: String = "s", frames: [String] = []) -> DiagnosticEntry {
        DiagnosticEntry(id: "e\(n)", date: Date(timeIntervalSince1970: 1_800_000_000 + Double(n)),
                        kind: .crash, summary: summary, frames: frames)
    }

    func testParsesCrashAndHangJSON() throws {
        let json = """
        {"crashDiagnostics":[{"diagnosticMetaData":{"exceptionType":1,"signal":"SIGSEGV","appVersion":"1.2",
          "terminationReason":"Namespace SIGNAL"},
         "callStackTree":{"callStacks":[{"threadAttributed":false,"callStackRootFrames":[{"binaryName":"Other","offsetIntoBinaryTextSegment":1}]},
           {"threadAttributed":true,"callStackRootFrames":[{"binaryName":"Lightstack","offsetIntoBinaryTextSegment":100,
             "subFrames":[{"binaryName":"UIKit","offsetIntoBinaryTextSegment":5}]}]}]}}],
         "hangDiagnostics":[{"diagnosticMetaData":{"hangDuration":"3.2 sec"},"callStackTree":{"callStacks":[]}}]}
        """
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = DiagnosticPayloadParser.entries(fromDiagnosticJSON: Data(json.utf8), received: at)
        XCTAssertEqual(entries.count, 2)
        let crash = try XCTUnwrap(entries.first { $0.kind == .crash })
        XCTAssertEqual(crash.frames, ["Lightstack +100", "UIKit +5"])
        XCTAssertTrue(crash.summary.contains("SIGSEGV"))
        XCTAssertEqual(crash.appVersion, "1.2")
        let hang = try XCTUnwrap(entries.first { $0.kind == .hang })
        XCTAssertEqual(hang.summary, "hung for 3.2 sec")
        // Re-reading the same payload gives the same ids (no duplicates in the store).
        XCTAssertEqual(entries.map(\.id), DiagnosticPayloadParser.entries(fromDiagnosticJSON: Data(json.utf8), received: at).map(\.id))
    }

    func testGarbageParsesToNothing() {
        XCTAssertTrue(DiagnosticPayloadParser.entries(fromDiagnosticJSON: Data("nope".utf8), received: Date()).isEmpty)
        XCTAssertNil(DiagnosticPayloadParser.entry(fromMetricJSON: Data("[]".utf8), received: Date()))
    }

    func testStoreKeepsNewestTwentyAndSurvivesReload() {
        let store = DiagnosticsStore(directory: dir)
        for n in 0..<30 { store.append([entry(n)]) }
        let loaded = DiagnosticsStore(directory: dir).load()
        XCTAssertEqual(loaded.count, 20)
        XCTAssertEqual(loaded.first?.id, "e29")
        XCTAssertEqual(loaded.last?.id, "e10")
    }

    func testStoreReplacesSameIdAndCapsBytes() {
        let store = DiagnosticsStore(directory: dir, maxEntries: 20, maxBytes: 4_000)
        store.append([entry(1, summary: "first")])
        store.append([entry(1, summary: "second")])
        XCTAssertEqual(store.load().map(\.summary), ["second"])
        let bigFrames = Array(repeating: String(repeating: "x", count: 200), count: 12)
        for n in 2..<12 { store.append([entry(n, frames: bigFrames)]) }
        let data = (try? Data(contentsOf: dir.appendingPathComponent("diagnostics.json"))) ?? Data()
        XCTAssertLessThanOrEqual(data.count, 4_000)
        XCTAssertEqual(store.load().first?.id, "e11", "the newest survives, the oldest go first")
    }

    func testExportFileContainsEntries() throws {
        let store = DiagnosticsStore(directory: dir)
        store.append([entry(1)])
        let url = try XCTUnwrap(store.exportFile())
        XCTAssertTrue((try String(contentsOf: url, encoding: .utf8)).contains("\"e1\""))
    }
}

// MARK: - Synced exercise feedback

final class SyncedExerciseFeedbackTests: XCTestCase {

    private var stack: OutboxTestStack!
    private var workouts: WorkoutRepository!
    private var store: CoachReviewStore!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
        workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        store = CoachReviewStore(workoutRepository: workouts)
        suite = "feedback-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDocumentRoundTripKeepsFeedbackAndOldDocumentsStillLoad() throws {
        let id = UUID()
        var doc = CoachReviewDocument()
        doc.feedback[id.uuidString] = SessionFeedback.tooHard.rawValue
        let text = try XCTUnwrap(doc.encoded())
        XCTAssertEqual(CoachReviewDocument.parse(text)?.feedback(forExercise: id), .tooHard)

        // A version-1 document has no feedback field.
        let old = "{\"coachReview\":1,\"inSessionReasons\":{\"Bench\":\"lowEnergy\"}}"
        let parsed = try XCTUnwrap(CoachReviewDocument.parse(old))
        XCTAssertTrue(parsed.feedback.isEmpty)
        XCTAssertEqual(parsed.inSessionReasons["Bench"], "lowEnergy")
    }

    func testAnswerIsWrittenThroughTheWorkoutUpdatePathAndRestoresFromTheDocument() throws {
        let w = Workout.create(userId: stack.userId, workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        workouts.createWorkout(w)
        let ex = UUID()
        XCTAssertTrue(store.recordFeedback(.tooEasy, exerciseId: ex, workoutId: w.id))

        // "New device": only the workout row (with its note) exists, UserDefaults is empty.
        let restored = try XCTUnwrap(workouts.fetchWorkout(id: w.id))
        let reader = ExerciseFeedbackStore.reader(workouts: [restored], fallback: { _ in nil })
        XCTAssertEqual(reader(ex), .tooEasy)

        XCTAssertTrue(store.recordFeedback(nil, exerciseId: ex, workoutId: w.id))
        let cleared = try XCTUnwrap(workouts.fetchWorkout(id: w.id))
        XCTAssertNil(ExerciseFeedbackStore.reader(workouts: [cleared], fallback: { _ in nil })(ex))
    }

    func testStoreWritesDocumentAndDeviceCopy() throws {
        let w = Workout.create(userId: stack.userId, workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        workouts.createWorkout(w)
        let feedbackStore = ExerciseFeedbackStore(defaults: defaults)
        feedbackStore.attach(reviewStore: store)
        let ex = UUID()
        feedbackStore.set(.aboutRight, forExercise: ex, workoutId: w.id)
        XCTAssertEqual(feedbackStore.deviceFeedback(forExercise: ex), .aboutRight)
        XCTAssertEqual(store.document(forWorkoutId: w.id)?.feedback(forExercise: ex), .aboutRight)
        XCTAssertEqual(feedbackStore.feedback(forExercise: ex, workoutId: w.id), .aboutRight)
    }

    func testReaderPrefersDocumentAndFallsBackToDeviceCopy() {
        let synced = UUID(), legacy = UUID(), conflict = UUID()
        var doc = CoachReviewDocument()
        doc.feedback[synced.uuidString] = SessionFeedback.tooHard.rawValue
        doc.feedback[conflict.uuidString] = SessionFeedback.tooEasy.rawValue
        doc.feedback["not-a-uuid"] = SessionFeedback.tooEasy.rawValue
        var w = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        w.aiProgressionNote = doc.encoded()

        let device: (UUID) -> SessionFeedback? = { id in
            id == legacy ? .aboutRight : (id == conflict ? .tooHard : nil)
        }
        let reader = ExerciseFeedbackStore.reader(workouts: [w], fallback: device)
        XCTAssertEqual(reader(synced), .tooHard)
        XCTAssertEqual(reader(legacy), .aboutRight, "old answers only on this device still count")
        XCTAssertEqual(reader(conflict), .tooEasy, "the synced document wins")
        XCTAssertNil(reader(UUID()))
    }
}
