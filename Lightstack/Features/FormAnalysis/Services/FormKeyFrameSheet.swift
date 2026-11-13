import AVFoundation
import UIKit

/// One moment of the recording worth showing to the AI.
struct KeyMoment: Equatable {
    let time: TimeInterval
    let label: String
}

/// Builds the contact sheet (a grid of labelled video frames cropped to the lifter, with the tracked skeleton
/// drawn thinly on) that the AI looks at, so its feedback comes from what actually happened and not only from
/// numbers.
///
/// Layout: up to 3 columns by 2 rows. With reps, each column is one rep (first, worst, last) with its start
/// above its peak, so the same joint can be compared down and across. Without reps, six evenly spaced frames
/// read down each column in time order.
enum FormKeyFrameSheet {

    static let maxMoments = 6
    static let maxTileLongSide: CGFloat = 640
    static let maxColumns = 3
    static let jpegByteBudget = 900_000
    /// A crop never gets smaller than this fraction of the frame in either direction.
    static let minCropFraction: CGFloat = 0.35
    /// Extra room around the lifter, as a fraction of the box size (split across both sides).
    static let cropPadding: CGFloat = 0.30

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
            guard (0..<n).contains(index), !chosen.contains(index), chosen.count < 3 else { return }
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
        // Still short of three columns: a middle rep (nearest free neighbour when the middle is taken).
        let middle = n / 2
        for offset in 0..<n where chosen.count < 3 {
            add(middle - offset)
            if chosen.count < 3 { add(middle + offset) }
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

    /// Grid size for a number of tiles: two rows, up to three columns, filled column by column.
    static func gridSize(forTiles count: Int) -> (columns: Int, rows: Int) {
        guard count > 0 else { return (0, 0) }
        return (min(maxColumns, (count + 1) / 2), count == 1 ? 1 : 2)
    }

    // MARK: Crop (pure)

    /// The region of the (upright) frame that holds the lifter over the active span, as fractions of the
    /// frame (origin top-left): the union box of visible joints, padded and clamped. One crop for every tile
    /// so the frames stay comparable. Falls back to the whole frame when there is nothing to measure.
    static func lifterCrop(track: PoseTrack, reps: [DetectedRep]) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        var from = -Double.infinity, to = Double.infinity
        if let first = reps.map(\.start).min(), let last = reps.map(\.end).max() {
            from = first - 0.5
            to = last + 0.5
        }
        var xs: [Double] = [], ys: [Double] = []
        for frame in track.frames where frame.time >= from && frame.time <= to {
            let seen = frame.joints.values.filter { $0.confidence >= 0.3 }
            guard seen.count >= 3 else { continue }
            for p in seen { xs.append(p.x); ys.append(p.y) }
        }
        guard xs.count >= 10 else { return full }
        xs.sort(); ys.sort()
        func pct(_ v: [Double], _ q: Double) -> Double { v[min(v.count - 1, max(0, Int(Double(v.count - 1) * q)))] }
        var minX = CGFloat(pct(xs, 0.01)), maxX = CGFloat(pct(xs, 0.99))
        var minY = CGFloat(pct(ys, 0.01)), maxY = CGFloat(pct(ys, 0.99))
        let padX = (maxX - minX) * cropPadding / 2, padY = (maxY - minY) * cropPadding / 2
        minX -= padX; maxX += padX; minY -= padY; maxY += padY
        // Never tighter than a third of the frame, so a still limb does not become an extreme close-up.
        func widen(_ lo: inout CGFloat, _ hi: inout CGFloat) {
            if hi - lo < minCropFraction {
                let mid = (lo + hi) / 2
                lo = mid - minCropFraction / 2
                hi = mid + minCropFraction / 2
            }
        }
        widen(&minX, &maxX); widen(&minY, &maxY)
        // Shift (rather than squash) a box that pokes out of the frame, then clamp.
        func fit(_ lo: inout CGFloat, _ hi: inout CGFloat) {
            if lo < 0 { hi -= lo; lo = 0 }
            if hi > 1 { lo -= hi - 1; hi = 1 }
            lo = max(0, lo)
        }
        fit(&minX, &maxX); fit(&minY, &maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Rendering

    /// The finished sheet for a recorded set, or nil when there is no movie or anything fails.
    static func sheet(for result: FormSessionResult) async -> Data? {
        await makeSheet(for: result)?.data
    }

    /// The JPEG plus the moments (and so the frame labels) it shows.
    static func makeSheet(for result: FormSessionResult) async -> (data: Data, moments: [KeyMoment])? {
        guard let url = result.videoURL else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return nil }
        let moments = selectMoments(analysis: result.analysis, duration: duration)
        guard !moments.isEmpty else { return nil }
        guard let data = await render(videoURL: url, track: result.track, moments: moments,
                                      highlighted: highlightedJoints(for: result.analysis.profile),
                                      reps: result.analysis.detection.reps) else { return nil }
        return (data, moments)
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

    static func render(videoURL: URL, track: PoseTrack, moments: [KeyMoment], highlighted: Set<BodyJoint>,
                       reps: [DetectedRep] = []) async -> Data? {
        guard !moments.isEmpty else { return nil }
        let crop = lifterCrop(track: track, reps: reps)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        // Ask for enough resolution that the cropped region itself reaches the tile size.
        let aspect = CGFloat(track.aspectRatio > 0 ? track.aspectRatio : 1)
        let cropLong = max(crop.width * aspect, crop.height)
        let frameLong = max(aspect, 1)
        let requested = min(2400, max(maxTileLongSide, maxTileLongSide * frameLong / max(cropLong, 0.05)))
        generator.maximumSize = CGSize(width: requested, height: requested)
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var tiles: [(image: CGImage, moment: KeyMoment)] = []
        for moment in moments.prefix(maxMoments) {
            let time = CMTime(seconds: moment.time, preferredTimescale: 600)
            guard let full = try? await generator.image(at: time).image else { return nil }
            let pixels = CGRect(x: (crop.minX * CGFloat(full.width)).rounded(.down),
                                y: (crop.minY * CGFloat(full.height)).rounded(.down),
                                width: (crop.width * CGFloat(full.width)).rounded(),
                                height: (crop.height * CGFloat(full.height)).rounded())
            guard let cropped = full.cropping(to: pixels.intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height)))
            else { return nil }
            tiles.append((cropped, moment))
        }
        guard let first = tiles.first else { return nil }
        let scale = min(1, maxTileLongSide / CGFloat(max(first.image.width, first.image.height)))
        let tileSize = CGSize(width: (CGFloat(first.image.width) * scale).rounded(),
                              height: (CGFloat(first.image.height) * scale).rounded())
        return composite(tiles: tiles, tileSize: tileSize, crop: crop, track: track, highlighted: highlighted)
    }

    private static func composite(tiles: [(image: CGImage, moment: KeyMoment)], tileSize: CGSize, crop: CGRect,
                                  track: PoseTrack, highlighted: Set<BodyJoint>) -> Data? {
        guard tileSize.width > 0, tileSize.height > 0 else { return nil }
        let grid = gridSize(forTiles: tiles.count)
        // The label strip sits above each frame, so it never hides the top of the picture (arms overhead).
        let stripHeight = max(24, tileSize.height * 0.06).rounded()
        let cellHeight = tileSize.height + stripHeight
        let sheetSize = CGSize(width: tileSize.width * CGFloat(grid.columns), height: cellHeight * CGFloat(grid.rows))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let font = UIFont.systemFont(ofSize: stripHeight * 0.66, weight: .bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph
        ]

        func draw(_ size: CGSize, scale: CGFloat) -> UIImage {
            let f = UIGraphicsImageRendererFormat()
            f.scale = scale
            f.opaque = true
            return UIGraphicsImageRenderer(size: size, format: f).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: sheetSize))
                let cg = context.cgContext
                for (index, tile) in tiles.enumerated() {
                    // Column by column: a rep's start above its peak.
                    let cell = CGPoint(x: CGFloat(index / 2) * tileSize.width, y: CGFloat(index % 2) * cellHeight)
                    let rect = CGRect(x: cell.x, y: cell.y + stripHeight, width: tileSize.width, height: tileSize.height)
                    UIImage(cgImage: tile.image).draw(in: rect)

                    if let frame = track.nearestFrame(to: tile.moment.time, maxGap: 0.5) {
                        cg.saveGState()
                        cg.clip(to: rect)
                        drawSkeleton(frame, in: rect, crop: crop, highlighted: highlighted, context: cg)
                        cg.restoreGState()
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
        }

        // Stay under the byte budget: lower the JPEG quality, then the resolution.
        var scale: CGFloat = 1
        for _ in 0..<3 {
            let image = draw(sheetSize, scale: scale)
            for quality in [0.78, 0.65, 0.5] as [CGFloat] {
                if let data = image.jpegData(compressionQuality: quality), data.count <= jpegByteBudget { return data }
            }
            scale *= 0.8
        }
        return draw(sheetSize, scale: scale).jpegData(compressionQuality: 0.4)
    }

    /// Thin, semi-transparent skeleton so it does not hide the joints it marks. `rect` shows `crop` of the frame.
    private static func drawSkeleton(_ frame: PoseFrame, in rect: CGRect, crop: CGRect, highlighted: Set<BodyJoint>,
                                     context cg: CGContext) {
        func point(_ joint: BodyJoint) -> CGPoint? {
            guard let p = PoseGeometry.point(frame, joint) else { return nil }
            let nx = (CGFloat(p.x) - crop.minX) / crop.width
            let ny = (CGFloat(p.y) - crop.minY) / crop.height
            return CGPoint(x: rect.minX + nx * rect.width, y: rect.minY + ny * rect.height)
        }
        let accent = UIColor(red: 0.24, green: 0.86, blue: 0.29, alpha: 0.65)
        let plain = UIColor.white.withAlphaComponent(0.45)
        let unit = max(rect.width, rect.height) / 640
        cg.setLineCap(.round)
        for (a, b) in SkeletonOverlayView.bones {
            guard let pa = point(a), let pb = point(b) else { continue }
            let on = highlighted.contains(a) && highlighted.contains(b)
            cg.setStrokeColor((on ? accent : plain).cgColor)
            cg.setLineWidth(max(1, (on ? 2.2 : 1.5) * unit))
            cg.move(to: pa)
            cg.addLine(to: pb)
            cg.strokePath()
        }
        for joint in BodyJoint.allCases {
            guard let p = point(joint) else { continue }
            let on = highlighted.contains(joint)
            let r = max(1.5, (on ? 3.5 : 2.5) * unit)
            cg.setFillColor((on ? accent : plain).cgColor)
            cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }
}
