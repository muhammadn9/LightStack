import AVFoundation
import Combine
import Foundation

/// Plays the recorded set back with the skeleton in sync. With a movie it drives an AVPlayer (muted, looping);
/// without one (UI tests, recording failed) a timer walks through the pose track instead.
/// It never touches AVAudioSession, so the user's music keeps playing.
@MainActor
final class FormReplayController: ObservableObject {

    static let tickInterval = 1.0 / 30.0
    /// How far before a moment a seek lands, so the user sees it coming.
    static let leadIn: TimeInterval = 0.3
    static let slowSpeed = 0.5
    static let normalSpeed = 1.0
    /// A pose frame further than this from the playhead is not drawn (the person was not tracked there).
    static let maxFrameGap: TimeInterval = 0.3

    let track: PoseTrack
    let player: AVPlayer?

    @Published private(set) var isPlaying = false
    @Published private(set) var speed = FormReplayController.normalSpeed
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval
    @Published private(set) var frame: PoseFrame?
    @Published var showSkeleton = true

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var timer: Timer?
    private var lastTick: Date?
    private var isScrubbing = false
    private var resumeAfterScrub = false

    var hasVideo: Bool { player != nil }

    init(videoURL: URL?, track: PoseTrack) {
        self.track = track
        let trackEnd = track.frames.last?.time ?? 0
        self.duration = max(trackEnd, 0.1)
        if let videoURL {
            let item = AVPlayerItem(url: videoURL)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.actionAtItemEnd = .none
            self.player = player
        } else {
            self.player = nil
        }
        frame = track.nearestFrame(to: 0, maxGap: Self.maxFrameGap)
        if let player {
            attach(to: player)
            Task { [weak self] in
                guard let item = player.currentItem,
                      let seconds = try? await item.asset.load(.duration).seconds,
                      seconds.isFinite, seconds > 0 else { return }
                self?.duration = seconds
            }
        }
    }

    private func attach(to player: AVPlayer) {
        let interval = CMTime(seconds: Self.tickInterval, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.videoTimeChanged(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.loop() }
        }
    }

    // MARK: Controls

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        if let player {
            player.rate = Float(speed)
        } else {
            startTimer()
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        player?.pause()
        stopTimer()
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func setSpeed(_ value: Double) {
        speed = value
        if isPlaying, let player { player.rate = Float(value) }
    }

    func toggleSpeed() { setSpeed(speed < 1 ? Self.normalSpeed : Self.slowSpeed) }

    /// Jumps to `time` (clamped) without changing whether it is playing.
    func seek(to time: TimeInterval) {
        let target = min(max(0, time), max(0, duration - 0.01))
        currentTime = target
        frame = track.nearestFrame(to: target, maxGap: Self.maxFrameGap)
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Where a seek for a moment at `time` lands.
    static func leadInTime(for time: TimeInterval) -> TimeInterval { max(0, time - leadIn) }

    /// Jumps shortly before the moment and plays it slowly.
    func seekToMoment(_ time: TimeInterval) {
        seek(to: Self.leadInTime(for: time))
        setSpeed(Self.slowSpeed)
        play()
    }

    func beginScrub() {
        guard !isScrubbing else { return }
        isScrubbing = true
        resumeAfterScrub = isPlaying
        pause()
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        if resumeAfterScrub { play() }
    }

    /// Stops playback and releases the observers. Call when the screen goes away.
    func teardown() {
        pause()
        stopTimer()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    // MARK: Playback plumbing

    private func videoTimeChanged(_ seconds: TimeInterval) {
        guard seconds.isFinite, !isScrubbing else { return }
        currentTime = seconds
        frame = track.nearestFrame(to: seconds, maxGap: Self.maxFrameGap)
    }

    private func loop() {
        guard let player else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                player.rate = Float(self.speed)
            }
        }
    }

    private func startTimer() {
        stopTimer()
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        lastTick = nil
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick ?? now)
        lastTick = now
        var t = currentTime + dt * speed
        if t >= duration { t = 0 }
        currentTime = t
        frame = track.nearestFrame(to: t, maxGap: Self.maxFrameGap)
    }
}
