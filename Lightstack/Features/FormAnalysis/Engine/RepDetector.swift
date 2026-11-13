import Foundation

struct DetectedRep: Equatable, Codable {
    let number: Int                 // 1-based
    let start: TimeInterval
    let peak: TimeInterval
    let end: TimeInterval
    let restAngle: Double
    let peakAngle: Double
    let amplitudeDegrees: Double
    var duration: TimeInterval { end - start }
    var outPhase: TimeInterval { peak - start }     // rest -> peak
    var returnPhase: TimeInterval { end - peak }    // peak -> rest
}

enum TrackingStatus: String, Codable { case good, partial, insufficient }

struct SignalSample: Equatable {
    let time: TimeInterval
    let degrees: Double
}

/// What the engine found on the side that was not used (for the left/right comparison).
struct SideSummary: Equatable {
    let side: BodySide
    let reps: [DetectedRep]
    let visibility: Double
}

struct RepDetection: Equatable {
    let reps: [DetectedRep]
    let angle: JointAngle           // signal actually used
    let side: BodySide?             // nil when both sides were fused (never today)
    let trackingQuality: Double     // 0-1: fraction of frames where the used joints were visible
    let status: TrackingStatus
    /// Smoothed signal used for detection (time, degrees) for charts/debug.
    let signal: [SignalSample]
    /// The other side's result, when that side was usable.
    let otherSide: SideSummary?

    static func insufficient(angle: JointAngle, quality: Double) -> RepDetection {
        RepDetection(reps: [], angle: angle, side: nil, trackingQuality: quality,
                     status: .insufficient, signal: [], otherSide: nil)
    }
}

enum RepDetector {

    // MARK: Tunables

    private static let maxInterpolatedGap = 0.6
    private static let smoothingWindow = 0.3
    private static let restTolerance = 0.35     // x median amplitude
    private static let peakTolerance = 0.5      // x median amplitude (reps shrink when tired)
    private static let usableVisibility = 0.5
    private static let goodVisibility = 0.75
    private static let bothSidesVisibility = 0.6
    private static let minReps = 2

    static func detect(track: PoseTrack, profile: MovementProfile) -> RepDetection {
        guard profile.isTracked else { return .insufficient(angle: profile.primary, quality: 0) }
        let frames = track.frames
        guard frames.count >= 10 else { return .insufficient(angle: profile.primary, quality: 0) }

        // Span in which a person is present (at least 3 visible joints).
        var first = -1, last = -1
        for (i, f) in frames.enumerated() {
            var n = 0
            for p in f.joints.values where p.confidence >= PoseGeometry.visibleConfidence { n += 1 }
            if n >= 3 {
                if first < 0 { first = i }
                last = i
            }
        }
        guard first >= 0, last - first + 1 >= 10 else { return .insufficient(angle: profile.primary, quality: 0) }

        let times = frames.map(\.time)
        let aspect = track.aspectRatio > 0 ? track.aspectRatio : 1

        func candidates(for angle: JointAngle) -> [Candidate] {
            [BodySide.left, .right].map {
                analyzeSide($0, angle: angle, frames: frames, times: times, aspect: aspect,
                            span: first...last, minAmp: profile.minAmplitudeDegrees)
            }
        }

        var angle = profile.primary
        var cands = candidates(for: angle)
        if !cands.contains(where: { $0.visibility >= usableVisibility }), let secondary = profile.secondary {
            let alt = candidates(for: secondary)
            if alt.contains(where: { $0.visibility >= usableVisibility }) {
                angle = secondary
                cands = alt
            }
        }

        let usable = cands.filter { $0.visibility >= usableVisibility }
        guard !usable.isEmpty else {
            return .insufficient(angle: angle, quality: cands.map(\.visibility).max() ?? 0)
        }

        let chosen = choose(usable)
        let other = cands.first { $0.side != chosen.side && $0.visibility >= usableVisibility }
        guard chosen.reps.count >= minReps else {
            return .insufficient(angle: angle, quality: chosen.visibility)
        }
        return RepDetection(
            reps: chosen.reps, angle: angle, side: chosen.side,
            trackingQuality: chosen.visibility,
            status: chosen.visibility >= goodVisibility ? .good : .partial,
            signal: chosen.signal,
            otherSide: other.map { SideSummary(side: $0.side, reps: $0.reps, visibility: $0.visibility) })
    }

    // MARK: Side choice

    private struct Candidate {
        let side: BodySide
        let reps: [DetectedRep]
        let visibility: Double
        let signal: [SignalSample]
    }

    private static func choose(_ usable: [Candidate]) -> Candidate {
        guard usable.count == 2 else { return usable[0] }
        let a = usable[0], b = usable[1]
        if a.reps.isEmpty != b.reps.isEmpty { return a.reps.isEmpty ? b : a }
        let bothVisible = a.visibility >= bothSidesVisibility && b.visibility >= bothSidesVisibility
        if bothVisible, a.reps.count != b.reps.count, abs(a.reps.count - b.reps.count) <= 1 {
            return a.reps.count > b.reps.count ? a : b
        }
        if a.reps.count == b.reps.count || abs(a.reps.count - b.reps.count) > 1 {
            return b.visibility > a.visibility ? b : a
        }
        return a.reps.count > b.reps.count ? a : b
    }

    // MARK: Per-side analysis

    private static func analyzeSide(_ side: BodySide, angle: JointAngle, frames: [PoseFrame], times: [Double],
                                    aspect: Double, span: ClosedRange<Int>, minAmp: Double) -> Candidate {
        var raw = [Double](repeating: .nan, count: frames.count)
        var visible = 0
        for i in span {
            if let a = PoseGeometry.angle(in: frames[i], kind: angle, side: side, aspect: aspect) {
                raw[i] = a
                visible += 1
            }
        }
        let visibility = Double(visible) / Double(span.count)
        guard visibility >= usableVisibility else {
            return Candidate(side: side, reps: [], visibility: visibility, signal: [])
        }
        let smooth = prepare(raw, times: times)
        let cycles = findReps(smooth, times: times, minAmp: minAmp)
        let reps = cycles.enumerated().map { i, c in
            DetectedRep(number: i + 1, start: c.start, peak: c.peak, end: c.end,
                        restAngle: c.rest, peakAngle: c.peakValue,
                        amplitudeDegrees: abs(c.peakValue - c.rest))
        }
        var signal: [SignalSample] = []
        signal.reserveCapacity(smooth.count)
        for (i, v) in smooth.enumerated() where !v.isNaN { signal.append(SignalSample(time: times[i], degrees: v)) }
        return Candidate(side: side, reps: reps, visibility: visibility, signal: signal)
    }

    // MARK: Signal preparation

    /// Median-of-3 despike, interpolate short gaps only, then a ~0.3 s moving average.
    /// Longer gaps stay NaN. Linear time.
    static func prepare(_ input: [Double], times t: [Double]) -> [Double] {
        var s = input
        let idx = s.indices.filter { !s[$0].isNaN }
        guard idx.count >= 10 else { return s }

        let v = idx.map { s[$0] }
        var despiked = v
        if v.count >= 3 {
            for i in 1..<(v.count - 1) {
                let a = v[i - 1], b = v[i], c = v[i + 1]
                despiked[i] = max(min(a, b), min(max(a, b), c))
            }
        }
        for (k, i) in idx.enumerated() { s[i] = despiked[k] }

        for k in 0..<(idx.count - 1) {
            let a = idx[k], b = idx[k + 1]
            guard b - a > 1, t[b] - t[a] <= maxInterpolatedGap, t[b] > t[a] else { continue }
            for j in (a + 1)..<b {
                let f = (t[j] - t[a]) / (t[b] - t[a])
                s[j] = s[a] + (s[b] - s[a]) * f
            }
        }

        var diffs: [Double] = []
        diffs.reserveCapacity(t.count)
        for i in 1..<t.count where t[i] > t[i - 1] { diffs.append(t[i] - t[i - 1]) }
        let dt = diffs.isEmpty ? 1.0 / 15 : median(diffs)
        let k = max(1, Int((smoothingWindow / dt).rounded()) | 1)
        let half = k / 2

        // Prefix sums of valid values and counts for an O(1) window mean.
        var sum = [Double](repeating: 0, count: s.count + 1)
        var cnt = [Int](repeating: 0, count: s.count + 1)
        for i in s.indices {
            sum[i + 1] = sum[i] + (s[i].isNaN ? 0 : s[i])
            cnt[i + 1] = cnt[i] + (s[i].isNaN ? 0 : 1)
        }
        var out = s
        for i in s.indices {
            if s[i].isNaN { continue }
            let lo = max(0, i - half), hi = min(s.count - 1, i + half)
            let n = cnt[hi + 1] - cnt[lo]
            out[i] = n >= max(1, half) ? (sum[hi + 1] - sum[lo]) / Double(n) : .nan
        }
        return out
    }

    // MARK: Zigzag

    struct Turn { let index: Int; let value: Double }

    static func zigzag(_ s: [Double], delta: Double) -> [Turn] {
        var vals: [Turn] = []
        vals.reserveCapacity(s.count)
        for (i, v) in s.enumerated() where !v.isNaN { vals.append(Turn(index: i, value: v)) }
        guard vals.count >= 3 else { return [] }

        var pts: [Turn] = []
        var lo = vals[0], hi = vals[0]
        var direction = 0
        var ext: Turn?
        for p in vals.dropFirst() {
            if direction == 0 {
                if p.value > hi.value { hi = p }
                if p.value < lo.value { lo = p }
                if hi.value - lo.value >= delta {
                    if hi.index > lo.index { pts.append(lo); direction = 1; ext = hi }
                    else { pts.append(hi); direction = -1; ext = lo }
                }
            } else if direction == 1, let e = ext {
                if p.value > e.value { ext = p }
                else if e.value - p.value >= delta { pts.append(e); direction = -1; ext = p }
            } else if let e = ext {
                if p.value < e.value { ext = p }
                else if p.value - e.value >= delta { pts.append(e); direction = 1; ext = p }
            }
        }
        if let e = ext { pts.append(e) }
        return pts
    }

    // MARK: Cycles

    private struct Cycle {
        let start: Double, peak: Double, end: Double
        let amp: Double, rest: Double, peakValue: Double
        var duration: Double { end - start }
    }

    private static func findReps(_ s: [Double], times t: [Double], minAmp: Double) -> [Cycle] {
        let pts = zigzag(s, delta: minAmp)
        guard pts.count >= 3 else { return [] }

        var nanPrefix = [Int](repeating: 0, count: s.count + 1)
        for i in s.indices { nanPrefix[i + 1] = nanPrefix[i] + (s[i].isNaN ? 1 : 0) }

        var best: [Cycle] = []
        var bestScore = 0.0
        for pol in [1.0, -1.0] {
            var cyc: [Cycle] = []
            var gaps: [Double] = []
            for k in 0..<(pts.count - 2) {
                let a = pts[k], b = pts[k + 1], c = pts[k + 2]
                guard pol * (b.value - a.value) > 0, pol * (b.value - c.value) > 0 else { continue }
                let amp = min(abs(b.value - a.value), abs(b.value - c.value))
                let band = 0.15 * amp
                // Trim the quiet rest at either end so pauses don't stretch the rep.
                var si = a.index
                var i = b.index
                while i >= a.index {
                    if !s[i].isNaN, pol * (s[i] - a.value) <= band { si = i; break }
                    i -= 1
                }
                var ei = c.index
                i = b.index
                while i <= c.index {
                    if !s[i].isNaN, pol * (s[i] - c.value) <= band { ei = i; break }
                    i += 1
                }
                let total = c.index - a.index + 1
                let gap = Double(nanPrefix[c.index + 1] - nanPrefix[a.index]) / Double(total)
                cyc.append(Cycle(start: t[si], peak: t[b.index], end: t[ei], amp: amp,
                                 rest: (a.value + c.value) / 2, peakValue: b.value))
                gaps.append(gap)
            }
            guard !cyc.isEmpty else { continue }
            let ma = median(cyc.map(\.amp)), md = median(cyc.map(\.duration))
            let mr = median(cyc.map(\.rest)), mp = median(cyc.map(\.peakValue))
            var good: [Cycle] = []
            for (c, gap) in zip(cyc, gaps) {
                if c.amp >= 0.5 * ma, c.duration >= 0.4 * md, c.duration <= 2.5 * md,
                   c.duration >= 0.5, c.duration <= 12,
                   abs(c.rest - mr) <= restTolerance * ma, abs(c.peakValue - mp) <= peakTolerance * ma,
                   gap < 0.4 {
                    good.append(c)
                }
            }
            var runs: [[Cycle]] = []
            var run: [Cycle] = []
            for c in good {
                if let prev = run.last, c.start - prev.end > 2.5 * md { runs.append(run); run = [] }
                run.append(c)
            }
            if !run.isEmpty { runs.append(run) }
            guard let r = runs.max(by: { $0.count < $1.count }), !r.isEmpty else { continue }
            let score = Double(r.count) * median(r.map(\.amp))
            if score > bestScore { best = r; bestScore = score }
        }
        // Reps can't overlap: shared turning points can leave two cycles touching.
        return best
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}
