import SwiftUI
import AVFoundation

/// The replay at the top of the results: video (or a dark panel) with the skeleton on top, and controls.
struct FormReplayView: View {

    @ObservedObject var replay: FormReplayController
    let highlighted: Set<BodyJoint>
    let screenHeight: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            screen
            controls
        }
    }

    // MARK: Screen

    private var screen: some View {
        ZStack {
            Color.black
            // The overlay maps for aspect-fill. Laid out with exactly the video's aspect ratio it is an exact fit
            // over the (aspect-fit) video, so the bones land on the body.
            ZStack {
                if let player = replay.player {
                    PlayerLayerView(player: player)
                } else {
                    Color(white: 0.1)
                }
                SkeletonOverlayView(frame: replay.showSkeleton ? replay.frame : nil,
                                    aspectRatio: replay.track.aspectRatio,
                                    highlighted: highlighted)
            }
            .aspectRatio(replay.track.aspectRatio > 0 ? replay.track.aspectRatio : 9.0 / 16.0, contentMode: .fit)
        }
        .frame(height: screenHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Replay of your set")
        .accessibilityIdentifier("formResults.replay")
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button { replay.togglePlayPause() } label: {
                Image(systemName: replay.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent, in: Circle())
            }
            .accessibilityLabel(replay.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("formResults.playPause")

            Slider(
                value: Binding(get: { min(replay.currentTime, replay.duration) }, set: { replay.seek(to: $0) }),
                in: 0...max(replay.duration, 0.1),
                onEditingChanged: { editing in editing ? replay.beginScrub() : replay.endScrub() }
            )
            .tint(AppTheme.accent)
            .accessibilityLabel("Replay position")
            .accessibilityIdentifier("formResults.scrubber")

            Button { replay.toggleSpeed() } label: {
                Text(replay.speed < 1 ? "0.5×" : "1×")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(minWidth: 44, minHeight: 36)
                    .padding(.horizontal, 6)
                    .background(AppTheme.surfaceElevated, in: Capsule())
            }
            .accessibilityLabel("Playback speed")
            .accessibilityValue(replay.speed < 1 ? "Half speed" : "Normal speed")
            .accessibilityIdentifier("formResults.speed")

            Button { replay.showSkeleton.toggle() } label: {
                Image(systemName: "figure.arms.open")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(replay.showSkeleton ? AppTheme.onAccent : AppTheme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(replay.showSkeleton ? AppTheme.accent : AppTheme.surfaceElevated, in: Circle())
            }
            .accessibilityLabel("Skeleton")
            .accessibilityValue(replay.showSkeleton ? "Shown" : "Hidden")
            .accessibilityIdentifier("formResults.skeletonToggle")
        }
    }
}

/// An AVPlayerLayer in a view, aspect-fit. Not a VideoPlayer, so there are no system controls to fight with.
struct PlayerLayerView: UIViewRepresentable {

    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PlayerLayerUIView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerLayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            // layerClass guarantees the type; fall back to a detached layer rather than force-casting.
            (layer as? AVPlayerLayer) ?? AVPlayerLayer()
        }
    }
}
