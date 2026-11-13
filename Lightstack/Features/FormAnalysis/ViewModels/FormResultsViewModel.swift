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
    @Published private(set) var feedbackFailed = false

    private let provider: FormFeedbackProviding
    private var feedbackTask: Task<Void, Never>?
    private var requested = false

    init(result: FormSessionResult, provider: FormFeedbackProviding) {
        self.result = result
        self.provider = provider
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
        startFeedbackRequest()
    }

    private func startFeedbackRequest() {
        isLoadingFeedback = true
        feedbackFailed = false
        feedbackTask = Task { [weak self] in
            guard let self else { return }
            let reply = await provider.feedback(for: result)
                guard !Task.isCancelled else { return }
            feedback = reply
            feedbackFailed = reply == nil
            isLoadingFeedback = false
        }
    }

    /// Waits for the in-flight request (tests).
    func waitForFeedback() async { await feedbackTask?.value }

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

    /// Findings for the "From tracking" section, most severe first (stable within a severity).
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

    /// The moment a fix points at: the peak of its first affected rep that exists, else nil.
    func seekTime(for fix: FormFix) -> TimeInterval? {
        for number in fix.reps.sorted() {
            if let rep = analysis.reps.first(where: { $0.rep.number == number }) { return rep.rep.peak }
        }
        return nil
    }

    func seek(to fix: FormFix) {
        guard let time = seekTime(for: fix) else { return }
        replay.seekToMoment(time)
    }

    func seek(to finding: FormFinding) {
        guard let time = finding.time else { return }
        replay.seekToMoment(time)
    }
}
