import AVFoundation
import UIKit

/// One moment of the recording worth showing to the AI.
struct KeyMoment: Equatable {
    let time: TimeInterval
    let label: String
}

/// Builds the contact sheet (a grid of labelled video frames with the tracked skeleton drawn on) that the
/// AI looks at, so its feedback comes from what actually happened and not only from numbers.
enum FormKeyFrameSheet {

    static let maxMoments = 8
    static let maxTileLongSide: CGFloat = 512
    static let columns = 4
    static let jpegQuality: CGFloat = 0.7

    // MARK: Selection (pure)

    static func selectMoments(analysis: FormAnalysis, duration: TimeInterval) -> [KeyMoment] {
        let moments = analysis.reps.isEmpty
            ? evenlySpaced(duration: duration)
            : repMoments(reps: analysis.reps)
        return finalize(moments, duration: duration)
    }

    private static func repMoments(reps: [RepSummary]) -> [KeyMoment] {
        let n = reps.count
        var chosen: [Int] = []
        func add(_ index: Int) {
            guard (0..<n).contains(index), !chosen.contains(index), chosen.count < 4 else { return }
            chosen.append(index)
        }
        add(0)
        add(n - 1)
        // Worst rep: most flags, then lowest range. A set with no flags falls back to its shortest rep.
        let worst = reps.indices.min { a, b in
            if reps[a].flags.count != reps[b].flags.count { return reps[a].flags.count > reps[b].flags.count }
            return reps[a].rangePercent < reps[b].rangePercent
        }
        if let worst { add(worst) }
        // Middle rep; when it is already taken use the nearest free neighbour.
        let middle = n / 2
        for offset in 0..<n {
            if chosen.count >= 4 { break }
            let before = middle - offset, after = middle + offset
            if !chosen.contains(before), before > 0, before < n - 1 { add(before); break }
            if !chosen.contains(after), after > 0, after < n - 1 { add(after); break }
        }
        return chosen.sorted().flatMap { index -> [KeyMoment] in
            let rep = reps[index].rep
            return [KeyMoment(time: rep.start, label: "Rep \(rep.number) start"),
                    KeyMoment(time: rep.peak, label: "Rep \(rep.number) peak")]
        }
    }

    private static func evenlySpaced(duration: TimeInterval) -> [KeyMoment] {
        guard duration > 0 else { return [] }
        let count = maxMoments
        return (0..<count).map { i in
            let t = duration * (0.05 + 0.9 * Double(i) / Double(count - 1))
            return KeyMoment(time: t, label: clock(t))
        }
    }

    /// Clamps into the recording, orders by time, drops duplicate times and caps the count.
    private static func finalize(_ moments: [KeyMoment], duration: TimeInterval) -> [KeyMoment] {
        var seen = Set<Int>()
        var out: [KeyMoment] = []
        let limit = duration > 0 ? max(0, duration - 0.05) : .infinity
        for moment in moments.sorted(by: { $0.time < $1.time }) {
            let t = min(max(0, moment.time), limit)
            let key = Int((t * 100).rounded())
            guard seen.insert(key).inserted else { continue }
            out.append(KeyMoment(time: t, label: moment.label))
        }
        return Array(out.prefix(maxMoments))
    }

    static func clock(_ time: TimeInterval) -> String {
        let s = max(0, Int(time))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    // MARK: Rendering

    /// The finished sheet for a recorded set, or nil when there is no movie or anything fails.
    static func sheet(for result: FormSessionResult) async -> Data? {
        guard let url = result.videoURL else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return nil }
        let moments = selectMoments(analysis: result.analysis, duration: duration)
        guard !moments.isEmpty else { return nil }
        return await render(videoURL: url, track: result.track, moments: moments,
                            highlighted: highlightedJoints(for: result.analysis.profile))
    }

    static func highlightedJoints(for profile: MovementProfile) -> Set<BodyJoint> {
        guard profile.isTracked else { return [] }
        var joints = Set<BodyJoint>()
        for side in [BodySide.left, .right] {
            let (a, b, c) = profile.primary.joints(side)
            joints.formUnion([a, b, c])
        }
        return joints
    }

    static func render(videoURL: URL, track: PoseTrack, moments: [KeyMoment], highlighted: Set<BodyJoint>) async -> Data? {
        guard !moments.isEmpty else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxTileLongSide, height: maxTileLongSide)
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var tiles: [(image: CGImage, moment: KeyMoment)] = []
        for moment in moments.prefix(maxMoments) {
            let time = CMTime(seconds: moment.time, preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image else { return nil }
            tiles.append((image, moment))
        }
        guard let first = tiles.first else { return nil }
        return composite(tiles: tiles, tileSize: CGSize(width: first.image.width, height: first.image.height),
                         track: track, highlighted: highlighted)
    }

    private static func composite(tiles: [(image: CGImage, moment: KeyMoment)], tileSize: CGSize,
                                  track: PoseTrack, highlighted: Set<BodyJoint>) -> Data? {
        guard tileSize.width > 0, tileSize.height > 0 else { return nil }
        let cols = min(columns, tiles.count)
        let rows = (tiles.count + columns - 1) / columns
        // The label strip sits above each frame, so it never hides the top of the picture (arms overhead).
        let stripHeight = max(22, tileSize.height * 0.07).rounded()
        let cellHeight = tileSize.height + stripHeight
        let sheetSize = CGSize(width: tileSize.width * CGFloat(cols), height: cellHeight * CGFloat(rows))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let font = UIFont.systemFont(ofSize: stripHeight * 0.66, weight: .bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph
        ]

        let image = UIGraphicsImageRenderer(size: sheetSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: sheetSize))
            let cg = context.cgContext
            for (index, tile) in tiles.enumerated() {
                let cell = CGPoint(x: CGFloat(index % columns) * tileSize.width,
                                   y: CGFloat(index / columns) * cellHeight)
                let rect = CGRect(x: cell.x, y: cell.y + stripHeight, width: tileSize.width, height: tileSize.height)
                UIImage(cgImage: tile.image).draw(in: rect)

                if let frame = track.nearestFrame(to: tile.moment.time, maxGap: 0.5) {
                    drawSkeleton(frame, in: rect, highlighted: highlighted, context: cg)
                }

                let strip = CGRect(x: cell.x, y: cell.y, width: tileSize.width, height: stripHeight)
                UIColor.black.setFill()
                cg.fill(strip)
                let textRect = strip.insetBy(dx: 2, dy: (stripHeight - font.lineHeight) / 2)
                (tile.moment.label as NSString).draw(in: textRect, withAttributes: attributes)

                UIColor.white.withAlphaComponent(0.5).setStroke()
                cg.setLineWidth(1)
                cg.stroke(CGRect(x: cell.x, y: cell.y, width: tileSize.width, height: cellHeight))
            }
        }
        return image.jpegData(compressionQuality: jpegQuality)
    }

    private static func drawSkeleton(_ frame: PoseFrame, in rect: CGRect, highlighted: Set<BodyJoint>, context cg: CGContext) {
        let aspect = Double(rect.width / rect.height)
        func point(_ joint: BodyJoint) -> CGPoint? {
            guard let p = PoseGeometry.point(frame, joint) else { return nil }
            // The tile has the image's own aspect, so the overlay's aspect-fill mapping is an exact fit.
            let mapped = SkeletonOverlayView.point(for: p, aspectRatio: aspect, in: rect.size)
            return CGPoint(x: rect.minX + mapped.x, y: rect.minY + mapped.y)
        }
        let accent = UIColor(red: 0.24, green: 0.86, blue: 0.29, alpha: 1)
        let plain = UIColor.white.withAlphaComponent(0.85)
        let unit = rect.height / 512
        cg.setLineCap(.round)
        for (a, b) in SkeletonOverlayView.bones {
            guard let pa = point(a), let pb = point(b) else { continue }
            let on = highlighted.contains(a) && highlighted.contains(b)
            cg.setStrokeColor((on ? accent : plain).cgColor)
            cg.setLineWidth((on ? 4 : 2.5) * unit)
            cg.move(to: pa)
            cg.addLine(to: pb)
            cg.strokePath()
        }
        for joint in BodyJoint.allCases {
            guard let p = point(joint) else { continue }
            let on = highlighted.contains(joint)
            let r = (on ? 5.5 : 3.5) * unit
            cg.setFillColor((on ? accent : plain).cgColor)
            cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }
}
