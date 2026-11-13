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
    /// Which kind of signal carried the reps. Amplitudes are degrees for `.angle` and percent of a body
    /// length for `.displacement`.
    var kind: SignalKind = .angle

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
        let span = first...last

        func angleCandidates(for angle: JointAngle) -> [Candidate] {
            [BodySide.left, .right].map { side in
                var raw = [Double](repeating: .nan, count: frames.count)
                var visible = 0
                for i in span {
                    if let a = PoseGeometry.angle(in: frames[i], kind: angle, side: side, aspect: aspect) {
                        raw[i] = a
                        visible += 1
                    }
                }
                return analyzeSide(side, kind: .angle, raw: raw, visibility: Double(visible) / Double(span.count),
                                   times: times, minAmp: profile.minAmplitudeDegrees)
            }
        }

        var angle = profile.primary
        var angleCands = angleCandidates(for: angle)
        if !angleCands.contains(where: { $0.visibility >= usableVisibility }), let secondary = profile.secondary {
            let alt = angleCandidates(for: secondary)
            if alt.contains(where: { $0.visibility >= usableVisibility }) {
                angle = secondary
                angleCands = alt
            }
        }

        var dispCands: [Candidate] = []
        if let limb = profile.displacementLimb,
           let scale = DisplacementSignal.bodyScale(frames: frames, span: span, aspect: aspect) {
            dispCands = [BodySide.left, .right].map { side in
                let r = DisplacementSignal.compute(limb: limb, side: side, frames: frames, span: span,
                                                   aspect: aspect, scale: scale)
                return analyzeSide(side, kind: .displacement, raw: r.values, visibility: r.visibility,
                                   times: times, minAmp: nil)
            }
        }

        let bestAngle = best(angleCands)
        let bestDisp = best(dispCands)
        // Tracking quality for "couldn't see you" messages always refers to the angle's joints.
        let angleQuality = bestAngle?.visibility ?? angleCands.map(\.visibility).max() ?? 0
        guard let picked = pickKind(angle: bestAngle, displacement: bestDisp, order: profile.signalOrder) else {
            return .insufficient(angle: angle, quality: angleQuality)
        }
        let pool = picked.kind == .angle ? angleCands : dispCands
        let other = pool.first { $0.side != picked.side && $0.visibility >= usableVisibility }
        guard picked.reps.count >= minReps else {
            return .insufficient(angle: angle, quality: angleQuality)
        }
        var detection = RepDetection(
            reps: picked.reps, angle: angle, side: picked.side,
            trackingQuality: picked.visibility,
            status: picked.visibility >= goodVisibility ? .good : .partial,
            signal: picked.signal,
            otherSide: other.map { SideSummary(side: $0.side, reps: $0.reps, visibility: $0.visibility) })
        detection.kind = picked.kind
        return detection
    }

    // MARK: Signal choice

    private struct Candidate {
        let side: BodySide
        let kind: SignalKind
        let reps: [DetectedRep]
        let visibility: Double
        let signal: [SignalSample]
        /// Cycles found before any alternation merge, and whether they alternated in size or length.
        var rawCount = 0
        var rawAlternating = false
        var didMerge = false
        /// Fraction of cycles with a phase shorter than ~0.35 s (a symptom of a folded signal).
        var shortFraction = 0.0
        /// Regularity penalty of the final reps; lower is better.
        var score = Double.infinity
    }

    /// Best usable side of one signal kind (nil when neither side was visible enough).
    private static func best(_ cands: [Candidate]) -> Candidate? {
        let usable = cands.filter { $0.visibility >= usableVisibility }
        guard !usable.isEmpty else { return nil }
        return choose(usable)
    }

    /// Picks between the angle and displacement signals. They agree within one rep -> keep the angle
    /// (existing behaviour and degree wording). Otherwise the more regular one wins; a candidate with about
    /// double the other's count that shows the odd/even alternation of a folded signal loses.
    private static func pickKind(angle: Candidate?, displacement: Candidate?, order: [SignalKind]) -> Candidate? {
        let a = angle.flatMap { $0.reps.count >= minReps ? $0 : nil }
        let d = displacement.flatMap { $0.reps.count >= minReps ? $0 : nil }
        switch (a, d) {
        case (nil, nil): return angle ?? displacement
        case (let a?, nil): return a
        case (nil, let d?): return d
        case (let a?, let d?):
            let na = a.reps.count, nd = d.reps.count
            if abs(na - nd) <= 1 {
                return (a.didMerge && !d.didMerge && na != nd) ? d : a
            }
            let (hi, lo) = na > nd ? (a, d) : (d, a)
            let nHi = hi.reps.count, nLo = lo.reps.count
            // About double with the symptoms of a folded signal (odd/even alternation or very short phases).
            if abs(nHi - 2 * nLo) <= max(1, nLo / 4), hi.rawAlternating || hi.shortFraction >= 0.3 { return lo }
            // Otherwise the profile's preferred signal wins unless the other is clearly more regular.
            let (first, second) = (order.first ?? .angle) == .angle ? (a, d) : (d, a)
            return second.score + 0.25 < first.score ? second : first
        }
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

    /// `minAmp` nil = derive from the signal's own range (displacement units are percent of a body length).
    private static func analyzeSide(_ side: BodySide, kind: SignalKind, raw: [Double], visibility: Double,
                                    times: [Double], minAmp: Double?) -> Candidate {
        guard visibility >= usableVisibility else {
            return Candidate(side: side, kind: kind, reps: [], visibility: visibility, signal: [])
        }
        let smooth = prepare(raw, times: times)
        let threshold = minAmp ?? max(displacementMinAmplitude(smooth), 4 * residualNoise(raw, smooth))
        var cycles = findReps(smooth, times: times, minAmp: threshold)
        let rawCount = cycles.count
        let rawAlternating = isAlternating(cycles)
        var merged = false
        if let m = mergeAlternatingPairs(cycles) { cycles = m; merged = true }
        let reps = cycles.enumerated().map { i, c in
            DetectedRep(number: i + 1, start: c.start, peak: c.peak, end: c.end,
                        restAngle: c.rest, peakAngle: c.peakValue,
                        amplitudeDegrees: abs(c.peakValue - c.rest))
        }
        var signal: [SignalSample] = []
        signal.reserveCapacity(smooth.count)
        for (i, v) in smooth.enumerated() where !v.isNaN { signal.append(SignalSample(time: times[i], degrees: v)) }
        var cand = Candidate(side: side, kind: kind, reps: reps, visibility: visibility, signal: signal)
        cand.rawCount = rawCount
        cand.rawAlternating = rawAlternating
        cand.didMerge = merged
        cand.score = regularity(cycles)
        cand.shortFraction = shortPhaseFraction(cycles)
        return cand
    }

    /// 30% of the signal's 2.5-97.5 percentile range, never below 20 (percent of body length).
    private static func displacementMinAmplitude(_ smooth: [Double]) -> Double {
        let v = smooth.filter { !$0.isNaN }.sorted()
        guard v.count >= 10 else { return 20 }
        let lo = v[Int(Double(v.count - 1) * 0.025)], hi = v[Int(Double(v.count - 1) * 0.975)]
        return max(20, 0.3 * (hi - lo))
    }

    /// RMS of raw minus smoothed: the frame-to-frame jitter. A rep must stand well clear of it.
    private static func residualNoise(_ raw: [Double], _ smooth: [Double]) -> Double {
        var sum = 0.0, n = 0
        for (r, m) in zip(raw, smooth) where !r.isNaN && !m.isNaN {
            sum += (r - m) * (r - m)
            n += 1
        }
        return n > 0 ? sqrt(sum / Double(n)) : 0
    }

    // MARK: Regularity

    private static let shortPhase = 0.35

    private static func cv(_ xs: [Double]) -> Double {
        guard xs.count >= 2 else { return 0 }
        let m = xs.reduce(0, +) / Double(xs.count)
        guard m > 0 else { return 0 }
        let variance = xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)
        return sqrt(variance) / m
    }

    /// Period-2 alternation: consecutive differences flip sign in at least 75% of steps, scored by how
    /// large the typical odd/even difference is (0 when there is no systematic alternation).
    static func alternationStrength(_ xs: [Double]) -> Double {
        guard xs.count >= 4 else { return 0 }
        var diffs: [Double] = [], rel: [Double] = []
        for i in 0..<(xs.count - 1) {
            diffs.append(xs[i + 1] - xs[i])
            rel.append(abs(xs[i + 1] - xs[i]) / max(abs(xs[i]), abs(xs[i + 1]), 1e-9))
        }
        var flips = 0
        for i in 0..<(diffs.count - 1) where diffs[i] * diffs[i + 1] < 0 { flips += 1 }
        guard Double(flips) / Double(diffs.count - 1) >= 0.75 else { return 0 }
        return median(rel)
    }

    private static func isAlternating(_ cycles: [Cycle]) -> Bool {
        guard cycles.count >= 4 else { return false }
        return alternationStrength(cycles.map(\.amp)) > 0.25 || alternationStrength(cycles.map(\.duration)) > 0.35
    }

    private static func regularity(_ cycles: [Cycle]) -> Double {
        guard cycles.count >= 2 else { return .infinity }
        let amps = cycles.map(\.amp), durs = cycles.map(\.duration)
        return cv(amps) + cv(durs) + 1.5 * alternationStrength(amps) + alternationStrength(durs)
            + shortPhaseFraction(cycles)
    }

    private static func shortPhaseFraction(_ cycles: [Cycle]) -> Double {
        guard !cycles.isEmpty else { return 0 }
        let shorts = cycles.filter { min($0.peak - $0.start, $0.end - $0.peak) < shortPhase }.count
        return Double(shorts) / Double(cycles.count)
    }

    /// Safety net for a folded signal: when the accepted cycles alternate strongly in size or length and
    /// merging adjacent pairs gives consistent reps, merge them. Slow cycles (a median of 1.5 s or more) are
    /// full reps already and are never merged, so a genuinely alternating-effort set is left alone.
    private static func mergeAlternatingPairs(_ cycles: [Cycle]) -> [Cycle]? {
        guard cycles.count >= 4, isAlternating(cycles) else { return nil }
        guard median(cycles.map(\.duration)) < 1.5 else { return nil }
        let rawAmpCV = cv(cycles.map(\.amp))
        var bestMerge: [Cycle]?
        var bestScore = Double.infinity
        for offset in 0...1 {
            var out: [Cycle] = []
            var i = offset
            while i + 1 < cycles.count {
                let a = cycles[i], b = cycles[i + 1]
                guard b.start - a.end < 1.0 else { out = []; break }
                let big = a.amp >= b.amp ? a : b
                out.append(Cycle(start: a.start, peak: big.peak, end: b.end, amp: big.amp,
                                 rest: big.rest, peakValue: big.peakValue))
                i += 2
            }
            guard out.count >= 2 else { continue }
            let ampCV = cv(out.map(\.amp)), durCV = cv(out.map(\.duration))
            guard ampCV <= 0.2, durCV <= 0.3, ampCV <= 0.6 * rawAmpCV + 0.05 else { continue }
            // More merged reps first (the offset that leaves the fewest cycles unpaired), then the steadier one.
            let score = ampCV + durCV - 10 * Double(out.count)
            if score < bestScore { bestScore = score; bestMerge = out }
        }
        return bestMerge
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
