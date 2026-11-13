import Foundation
import Combine
import UIKit

/// Runs one form recording: setup check -> countdown -> recording -> analysis.
///
/// All timing that decides behaviour (setup status refresh, live rep detection, "too short") comes from
/// frame times, so tests drive it with fake frames and never wait on a wall clock.
@MainActor
final class FormAnalysisViewModel: ObservableObject {

    enum Phase: Equatable {
        case setup
        case countdown(Int)
        case recording
        case analyzing
        case done
        case failed(String)
    }

    static let countdownSeconds = 5
    static let minimumRecordingSeconds = 1.0
    private static let setupWindow = 1.2
    private static let setupRefresh = 0.25
    private static let liveDetectInterval = 0.5
    /// A frame this late as the first of a recording still carries the old (pre-recording) clock.
    private static let staleFirstFrameTime = 2.0

    // MARK: Published state

    @Published private(set) var phase: Phase = .setup
    @Published private(set) var setupStatus: SetupStatus
    @Published private(set) var latestFrame: PoseFrame?
    @Published private(set) var aspectRatio: Double
    @Published private(set) var liveRepCount = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var result: FormSessionResult?
    @Published private(set) var permissionDenied: Bool
    /// A short message shown on the setup screen (e.g. the last recording was too short).
    @Published private(set) var notice: String?

    private(set) var profile: MovementProfile = MovementProfileLibrary.generic
    /// Joints of the profile's primary angle (both sides), for the skeleton overlay highlight.
    var highlightedJoints: Set<BodyJoint> {
        guard profile.isTracked else { return [] }
        var joints = Set<BodyJoint>()
        for side in [BodySide.left, .right] {
            let (a, b, c) = profile.primary.joints(side)
            joints.formUnion([a, b, c])
        }
        return joints
    }

    /// DEBUG/UI tests: resolve the movement profile from this name instead of the displayed one.
    var analysisNameOverride: String?

    let source: PoseSource
    private let countdownTick: Duration
    private var exerciseName = ""
    private var cancellables = Set<AnyCancellable>()
    private var countdownTask: Task<Void, Never>?

    // Setup
    private var recent: [PoseFrame] = []
    private var lastStatusTime: TimeInterval?

    // Recording
    private var frames: [PoseFrame] = []
    private var lastFrameTime: TimeInterval?
    private var detecting = false
    private var lastDetectTime: TimeInterval = 0

    /// Frames kept for the current recording (for tests and diagnostics).
    var recordedFrameCount: Int { frames.count }

    init(source: PoseSource, countdownTick: Duration = .seconds(1)) {
        self.source = source
        self.countdownTick = countdownTick
        self.aspectRatio = source.aspectRatio
        self.permissionDenied = source.permissionDenied
        self.setupStatus = SetupCheck.evaluate(recent: [], profile: MovementProfileLibrary.generic)

        source.framePublisher
            .sink { [weak self] frame in self?.handle(frame) }
            .store(in: &cancellables)
        source.permissionDeniedPublisher
            .sink { [weak self] denied in self?.permissionDenied = denied }
            .store(in: &cancellables)
        source.interruptionPublisher
            .sink { [weak self] in self?.handleInterruption() }
            .store(in: &cancellables)
    }

    // MARK: Public API

    /// Resolves the movement profile, resets everything and starts the camera.
    func prepare(exerciseName: String) {
        removeStaleMovies()
        countdownTask?.cancel()
        self.exerciseName = exerciseName
        profile = MovementProfileLibrary.profile(for: analysisNameOverride ?? exerciseName)
        result = nil
        notice = nil
        resetRecordingState()
        recent = []
        lastStatusTime = nil
        latestFrame = nil
        setupStatus = initialSetupStatus()
        phase = .setup
        source.start()
    }

    /// 5-second countdown, then recording starts. Cancel with `cancelCountdown()`.
    func startCountdown() {
        guard phase == .setup else { return }
        notice = nil
        phase = .countdown(Self.countdownSeconds)
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: Self.countdownSeconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                phase = .countdown(remaining)
                do { try await Task.sleep(for: countdownTick) } catch { return }
            }
            guard !Task.isCancelled, case .countdown = phase else { return }
            beginRecording()
        }
    }

    func cancelCountdown() {
        guard case .countdown = phase else { return }
        countdownTask?.cancel()
        countdownTask = nil
        phase = .setup
    }

    /// Stops recording, runs the analysis and publishes `result`.
    func finish() {
        guard phase == .recording else { return }
        phase = .analyzing
        Task { await completeRecording() }
    }

    /// Stops everything and deletes any temp movie.
    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        if phase == .recording {
            let source = source
            Task { Self.remove(await source.stopRecording()) }
        }
        source.stop()
        resetRecordingState()
        recent = []
        discardResult()
        phase = .setup
    }

    func discardResult() {
        Self.remove(result?.videoURL)
        result = nil
    }

    /// Switching cameras is only possible before the countdown.
    func flipCamera() {
        guard phase == .setup else { return }
        source.flipCamera()
        recent = []
        lastStatusTime = nil
        setupStatus = initialSetupStatus()
    }

    /// Phone call, app backgrounded, camera taken away: treat it like the user pressing Done.
    func handleInterruption() {
        switch phase {
        case .recording: finish()
        case .countdown: cancelCountdown()
        default: break
        }
    }

    // MARK: Frames

    private func handle(_ incoming: PoseFrame?) {
        aspectRatio = source.aspectRatio
        // Sources send an empty-joint frame for "no person"; a bare nil still becomes a gap in the track.
        let frame = incoming ?? PoseFrame(time: (lastFrameTime ?? 0) + 1.0 / 15.0, joints: [:])
        lastFrameTime = frame.time
        latestFrame = frame.joints.isEmpty ? nil : frame

        switch phase {
        case .setup: updateSetup(with: frame)
        case .recording: record(frame)
        default: break
        }
    }

    private func updateSetup(with frame: PoseFrame) {
        guard profile.isTracked else { return }
        recent.append(frame)
        recent.removeAll { $0.time < frame.time - Self.setupWindow }
        if let last = lastStatusTime, frame.time >= last, frame.time - last < Self.setupRefresh { return }
        lastStatusTime = frame.time
        let status = SetupCheck.evaluate(recent: recent, profile: profile)
        if status != setupStatus { setupStatus = status }
    }

    private func initialSetupStatus() -> SetupStatus {
        guard profile.isTracked else {
            return SetupStatus(isReady: false, missing: [],
                               message: "Rep counting isn't available for this exercise, but you can still record it.")
        }
        return SetupCheck.evaluate(recent: [], profile: profile)
    }

    private func beginRecording() {
        resetRecordingState()
        source.startRecording()
        phase = .recording
    }

    private func record(_ frame: PoseFrame) {
        if let last = frames.last {
            guard frame.time >= last.time else { return }
        } else if frame.time > Self.staleFirstFrameTime {
            return
        }
        frames.append(frame)
        elapsed = frame.time
        if profile.isTracked, !detecting, frame.time - lastDetectTime >= Self.liveDetectInterval {
            runLiveDetection()
        }
    }

    private func runLiveDetection() {
        detecting = true
        lastDetectTime = elapsed
        let snapshot = PoseTrack(frames: frames, aspectRatio: source.aspectRatio)
        let profile = profile
        Task {
            let count = await Task.detached(priority: .userInitiated) {
                RepDetector.detect(track: snapshot, profile: profile).reps.count
            }.value
            detecting = false
            guard phase == .recording, count > liveRepCount else { return }
            liveRepCount = count
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: Finishing

    private func completeRecording() async {
        let duration = (frames.last?.time ?? 0) - (frames.first?.time ?? 0)
        let url = await source.stopRecording()

        guard duration >= Self.minimumRecordingSeconds else {
            Self.remove(url)
            resetRecordingState()
            recent = []
            lastStatusTime = nil
            notice = "That recording was too short. Try again and keep going until your set is done."
            phase = .setup
            return
        }

        source.stop()
        let track = PoseTrack(frames: frames, aspectRatio: source.aspectRatio)
        let name = analysisNameOverride ?? exerciseName
        let analysis = await Task.detached(priority: .userInitiated) {
            FormAnalyzer.analyze(track: track, exerciseName: name)
        }.value

        guard phase == .analyzing else {   // cancelled while analysing
            Self.remove(url)
            return
        }
        result = FormSessionResult(exerciseName: exerciseName, analysis: analysis, track: track,
                                   videoURL: url, cameraPosition: source.cameraPosition)
        phase = .done
    }

    // MARK: Helpers

    private func resetRecordingState() {
        frames = []
        liveRepCount = 0
        elapsed = 0
        detecting = false
        lastDetectTime = 0
    }

    private static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Movies left behind by a crash or a force-quit.
    private func removeStaleMovies() {
        let dir = FileManager.default.temporaryDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasPrefix("form-") && name.hasSuffix(".mp4") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
