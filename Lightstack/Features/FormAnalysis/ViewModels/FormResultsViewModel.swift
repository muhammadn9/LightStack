import Foundation
import Combine

/// State behind the results screen: the AI feedback (requested once), and the replay.
@MainActor
final class FormResultsViewModel: ObservableObject {

    struct RepDisplay: Equatable {
        let value: String
        let caption: String
    }

    let result: FormSessionResult
    let replay: FormReplayController

    @Published private(set) var feedback: FormFeedback?
    @Published private(set) var isLoadingFeedback = false
    /// Why the last request failed (nil while loading, after success, or before the first request).
    @Published private(set) var failureReason: AIFailureReason?

    var feedbackFailed: Bool { failureReason != nil }

    /// Seconds to wait before the one automatic retry after a busy or timed-out request.
    static let autoRetryDelay: TimeInterval = 8

    private let provider: FormFeedbackProviding
    private let autoRetryDelay: TimeInterval
    private var feedbackTask: Task<Void, Never>?
    private var autoRetryTask: Task<Void, Never>?
    private var requested = false
    private var autoRetried = false

    init(result: FormSessionResult, provider: FormFeedbackProviding, autoRetryDelay: TimeInterval = FormResultsViewModel.autoRetryDelay) {
        self.result = result
        self.provider = provider
        self.autoRetryDelay = autoRetryDelay
        self.replay = FormReplayController(videoURL: result.videoURL, track: result.track)
    }

    var analysis: FormAnalysis { result.analysis }

    // MARK: Feedback

    /// Requests feedback the first time it is called; later calls do nothing.
    func loadFeedbackIfNeeded() {
        guard !requested else { return }
        requested = true
        startFeedbackRequest()
    }

    /// Asks again after a failure.
    func retryFeedback() {
        guard !isLoadingFeedback, feedback == nil else { return }
        autoRetryTask?.cancel()
        startFeedbackRequest()
    }

    private func startFeedbackRequest() {
        isLoadingFeedback = true
        failureReason = nil
        feedbackTask = Task { [weak self] in
            guard let self else { return }
            let reply = await provider.feedback(for: result)
            guard !Task.isCancelled else { return }
            switch reply {
            case .success(let value):
                feedback = value
                failureReason = nil
            case .failure(let reason):
                feedback = nil
                failureReason = reason
                scheduleAutoRetry(after: reason)
            }
            isLoadingFeedback = false
        }
    }

    /// One quiet retry a few seconds after a busy or timed-out request, while this screen is still alive.
    private func scheduleAutoRetry(after reason: AIFailureReason) {
        guard reason.isTemporary, !autoRetried else { return }
        autoRetried = true
        let delay = autoRetryDelay
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, feedback == nil, !isLoadingFeedback else { return }
            startFeedbackRequest()
        }
    }

    /// Waits for the in-flight request and any automatic retry (tests).
    func waitForFeedback() async {
        await feedbackTask?.value
        if let retry = autoRetryTask {
            await retry.value
            await feedbackTask?.value
        }
    }

    /// Called when the screen disappears. SwiftUI can report a disappear right after the first appear while a
    /// sheet settles, so this only pauses playback: the feedback request keeps running and the replay can resume.
    func teardown() {
        replay.pause()
    }

    // MARK: Display rules

    /// "5" normally; "~5" with an AI-estimate caption when the tracker could not count and the AI could.
    static func repDisplay(measured: Int, estimated: Int?) -> RepDisplay {
        if measured == 0, let estimated, estimated > 0 {
            return RepDisplay(value: "~\(estimated)", caption: "Reps (AI estimate)")
        }
        return RepDisplay(value: "\(measured)", caption: measured == 1 ? "Rep" : "Reps")
    }

    var repDisplay: RepDisplay {
        Self.repDisplay(measured: analysis.repCount, estimated: feedback?.estimatedReps)
    }

    /// True when the tracker produced a usable analysis, i.e. it found reps.
    var hasReps: Bool { !analysis.reps.isEmpty }

    /// Ids of findings that mean "nothing could be measured".
    static let untrackableIds: Set<String> = ["cantTrack", "noReps", "untracked"]

    var untrackableFinding: FormFinding? {
        analysis.findings.first { Self.untrackableIds.contains($0.id) }
    }

    /// Findings for the "Measured by tracking" section, most severe first (stable within a severity).
    var sortedFindings: [FormFinding] {
        let rank: [FindingSeverity: Int] = [.major: 0, .minor: 1, .good: 2]
        return analysis.findings.enumerated()
            .sorted { a, b in
                let ra = rank[a.element.severity] ?? 3, rb = rank[b.element.severity] ?? 3
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }

    // MARK: Seeking

    func seek(toRepStart number: Int) {
        guard let rep = analysis.reps.first(where: { $0.rep.number == number }) else { return }
        replay.seekToMoment(rep.rep.start)
    }

    /// The time of a key frame label the coach cited ("Rep 6 peak", "0:07"): looked up in the moments the AI
    /// was shown, then parsed from the label itself. nil when the label means nothing for this set.
    func time(forFrameLabel label: String) -> TimeInterval? {
        let wanted = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        let duration = (result.track.frames.last?.time ?? 0) + 0.05
        let moments = FormKeyFrameSheet.selectMoments(analysis: analysis, duration: duration)
        if let hit = moments.first(where: { $0.label.lowercased() == wanted }) { return hit.time }
        let parts = wanted.split(separator: " ").map(String.init)
        if parts.count == 3, parts[0] == "rep", let number = Int(parts[1]),
           let rep = analysis.reps.first(where: { $0.rep.number == number })?.rep {
            if parts[2] == "start" { return rep.start }
            if parts[2] == "peak" { return rep.peak }
            if parts[2] == "end" { return rep.end }
        }
        let clock = wanted.split(separator: ":")
        if clock.count == 2, let m = Int(clock[0]), let s = Int(clock[1]) { return Double(m * 60 + s) }
        return nil
    }

    /// The moment a fix points at: its cited frame, else the peak of its first affected rep that exists, else nil.
    func seekTime(for fix: FormFix) -> TimeInterval? {
        if let label = fix.frame, let time = time(forFrameLabel: label) { return time }
        for number in fix.reps.sorted() {
            if let rep = analysis.reps.first(where: { $0.rep.number == number }) { return rep.rep.peak }
        }
        return nil
    }

    func seek(to fix: FormFix) {
        guard let time = seekTime(for: fix) else { return }
        replay.seekToMoment(time)
    }

    // MARK: Sharing

    /// Writes the tracking data (no video) to a temporary JSON file for the share sheet.
    func trackingDataFile(trueReps: Int?) -> URL? {
        try? FormTrackingExport.writeFile(for: result, trueReps: trueReps)
    }

    func seek(to finding: FormFinding) {
        guard let time = finding.time else { return }
        replay.seekToMoment(time)
    }
}
