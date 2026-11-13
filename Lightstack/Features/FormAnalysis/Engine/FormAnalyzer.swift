import Foundation

enum FindingSeverity: String, Codable { case good, minor, major }

struct FormFinding: Identifiable, Equatable, Codable {
    let id: String
    let kind: FormCheckKind
    let severity: FindingSeverity
    let title: String
    let detail: String
    let cue: String
    let reps: [Int]
    let time: TimeInterval?
}

struct RepSummary: Identifiable, Equatable, Codable {
    let rep: DetectedRep
    let rangePercent: Double
    let flags: [FormCheckKind]
    var id: Int { rep.number }
    var isClean: Bool { flags.isEmpty }
}

struct FormAnalysis: Equatable {
    let exerciseName: String
    let profile: MovementProfile
    let detection: RepDetection
    let reps: [RepSummary]
    let findings: [FormFinding]
    let score: Int?
    var repCount: Int { reps.count }

    /// Compact plain-text block for the AI prompt.
    func summaryForPrompt() -> String {
        var lines: [String] = []
        lines.append("Exercise: \(exerciseName)")
        let quality = Int((detection.trackingQuality * 100).rounded())
        lines.append("Tracking: \(detection.status.rawValue) (\(quality)% of frames visible, \(detection.angle.rawValue) angle"
                     + (detection.side.map { ", \($0.rawValue) side" } ?? "") + ")")
        if reps.isEmpty {
            lines.append("Reps detected: none")
        } else {
            lines.append("Reps detected: \(reps.count)" + (score.map { ", form score \($0)/100" } ?? ""))
            lines.append("Rep | start s | peak s | end s | range deg | % of best | flags")
            for r in reps {
                let flags = r.flags.isEmpty ? "clean" : r.flags.map(\.rawValue).joined(separator: ",")
                lines.append("\(r.rep.number) | \(fmt(r.rep.start)) | \(fmt(r.rep.peak)) | \(fmt(r.rep.end)) | "
                             + "\(Int(r.rep.amplitudeDegrees.rounded())) | \(Int(r.rangePercent.rounded()))% | \(flags)")
            }
        }
        if !findings.isEmpty {
            lines.append("Findings:")
            for f in findings { lines.append("- [\(f.severity.rawValue)] \(f.title): \(f.detail)") }
        }
        return lines.joined(separator: "\n")
    }

    private func fmt(_ x: Double) -> String { String(format: "%.1f", x) }
}

enum FormAnalyzer {

    static func analyze(track: PoseTrack, exerciseName: String) -> FormAnalysis {
        let profile = MovementProfileLibrary.profile(for: exerciseName)
        let detection = RepDetector.detect(track: track, profile: profile)

        guard detection.status != .insufficient, !detection.reps.isEmpty else {
            return FormAnalysis(exerciseName: exerciseName, profile: profile, detection: detection, reps: [],
                                findings: [cantTrackFinding(profile: profile, detection: detection)], score: nil)
        }

        let reps = detection.reps
        let amps = reps.map(\.amplitudeDegrees)
        let best = RepDetector.median(Array(amps.sorted(by: >).prefix(3)))
        var flags: [Int: Set<FormCheckKind>] = [:]
        var findings: [FormFinding] = []

        func flag(_ numbers: [Int], _ kind: FormCheckKind) { for n in numbers { flags[n, default: []].insert(kind) } }
        func time(of number: Int) -> TimeInterval? { reps.first { $0.number == number }?.peak }
        let checks = profile.checks

        // Range consistency and fatigue drift.
        let n = reps.count
        let short = reps.filter { best > 0 && $0.amplitudeDegrees < 0.8 * best }
        var fatigueReps: [Int] = []
        if checks.contains(.fatigueDrift), n >= 6 {
            let third = n / 3
            let first = reps.prefix(third).map(\.amplitudeDegrees)
            let lastReps = reps.suffix(third)
            let mean = { (xs: [Double]) in xs.reduce(0, +) / Double(max(1, xs.count)) }
            let firstMean = mean(first), lastMean = mean(lastReps.map(\.amplitudeDegrees))
            if firstMean > 0, lastMean < 0.85 * firstMean {
                let ratio = lastMean / firstMean
                let lateShort = lastReps.filter { $0.amplitudeDegrees < 0.8 * best }.map(\.number)
                fatigueReps = lateShort.isEmpty ? lastReps.map(\.number) : lateShort
                flag(fatigueReps, .fatigueDrift)
                findings.append(FormFinding(
                    id: "fatigueDrift", kind: .fatigueDrift, severity: ratio < 0.7 ? .major : .minor,
                    title: "Range shrank late in set",
                    detail: "\(repLabel(fatigueReps)) moved about \(Int(((1 - ratio) * 100).rounded()))% less than your first reps, "
                        + "so your range dropped as you got tired.",
                    cue: "Stop the set when your range starts to shrink, or rest longer between sets.",
                    reps: fatigueReps, time: fatigueReps.first.flatMap(time(of:))))
            }
        }
        if checks.contains(.rangeConsistency) {
            // Don't double-report reps already explained by fatigue.
            let remaining = short.map(\.number).filter { !fatigueReps.contains($0) }
            if !remaining.isEmpty {
                let worst = short.filter { remaining.contains($0.number) }.map(\.amplitudeDegrees).min() ?? best
                let major = remaining.count >= 2 || worst < 0.65 * best
                flag(remaining, .rangeConsistency)
                findings.append(FormFinding(
                    id: "rangeConsistency", kind: .rangeConsistency, severity: major ? .major : .minor,
                    title: "\(shortLabel(remaining)) cut short",
                    detail: "\(repLabel(remaining)) only reached \(Int((worst / best * 100).rounded()))% of your best range "
                        + "(\(Int(worst.rounded())) vs \(Int(best.rounded())) degrees).",
                    cue: "Go through the same full range on every rep.",
                    reps: remaining, time: remaining.first.flatMap(time(of:))))
            } else if fatigueReps.isEmpty {
                findings.append(FormFinding(
                    id: "goodRange", kind: .rangeConsistency, severity: .good,
                    title: "Consistent range",
                    detail: "Consistent range on all \(n) reps.",
                    cue: "Keep it up.", reps: [], time: nil))
            }
        }

        // Tempo.
        if checks.contains(.tempoControl) {
            let rushed = reps.filter { min($0.outPhase, $0.returnPhase) < 0.45 || $0.duration < 1.0 }.map(\.number)
            if !rushed.isEmpty {
                flag(rushed, .tempoControl)
                let fastest = reps.filter { rushed.contains($0.number) }.map { min($0.outPhase, $0.returnPhase) }.min() ?? 0
                findings.append(FormFinding(
                    id: "tempoControl", kind: .tempoControl,
                    severity: rushed.count * 2 >= n ? .major : .minor,
                    title: "\(shortLabel(rushed)) rushed",
                    detail: "\(repLabel(rushed)) had a phase of only \(String(format: "%.1f", fastest)) seconds, so the weight was moving too fast to control.",
                    cue: "Take about two seconds to lower the weight.",
                    reps: rushed, time: rushed.first.flatMap(time(of:))))
            }
        }

        // Left vs right.
        if checks.contains(.sideImbalance), let used = detection.side, let other = detection.otherSide,
           detection.trackingQuality >= 0.75, other.visibility >= 0.75,
           other.reps.count >= max(2, n / 2) {
            let usedMean = amps.reduce(0, +) / Double(n)
            let otherMean = other.reps.map(\.amplitudeDegrees).reduce(0, +) / Double(other.reps.count)
            let bigger = max(usedMean, otherMean)
            if bigger > 0 {
                let diff = abs(usedMean - otherMean) / bigger
                if diff > 0.15 {
                    let weaker = usedMean < otherMean ? used : other.side
                    findings.append(FormFinding(
                        id: "sideImbalance", kind: .sideImbalance, severity: diff > 0.25 ? .major : .minor,
                        title: "\(weaker.rawValue.capitalized) side moves less",
                        detail: "Your \(weaker.rawValue) side moved about \(Int((diff * 100).rounded()))% less than your \(weaker.other.rawValue) side.",
                        cue: "Focus on matching both sides, and start with the weaker side.",
                        reps: [], time: reps.first?.peak))
                }
            }
        }

        // Torso sway.
        if checks.contains(.torsoSway) {
            var swings: [(rep: Int, degrees: Double)] = []
            for r in reps {
                if let d = torsoSwing(in: track, from: r.start, to: r.end) { swings.append((r.number, d)) }
            }
            let minor = swings.filter { $0.degrees > 12 }
            let major = swings.filter { $0.degrees > 20 }
            if !swings.isEmpty, minor.count * 3 >= swings.count {
                let numbers = minor.map(\.rep)
                flag(numbers, .torsoSway)
                let worst = swings.map(\.degrees).max() ?? 0
                findings.append(FormFinding(
                    id: "torsoSway", kind: .torsoSway,
                    severity: major.count * 3 >= swings.count ? .major : .minor,
                    title: "Body swinging on reps",
                    detail: "Your torso swung up to \(Int(worst.rounded())) degrees during \(repLabel(numbers)), which means momentum is doing some of the work.",
                    cue: "Stand tight and lower the weight so you can lift without swinging.",
                    reps: numbers, time: numbers.first.flatMap(time(of:))))
            }
        }

        // Lockout / return to start.
        if checks.contains(.lockout), n >= 3 {
            let medRest = RepDetector.median(reps.map(\.restAngle))
            let medPeak = RepDetector.median(reps.map(\.peakAngle))
            let sign: Double = medPeak >= medRest ? 1 : -1
            let incomplete = reps.filter { sign * ($0.restAngle - medRest) > 15 }
            if !incomplete.isEmpty {
                let numbers = incomplete.map(\.number)
                flag(numbers, .lockout)
                let worst = incomplete.map { sign * ($0.restAngle - medRest) }.max() ?? 0
                findings.append(FormFinding(
                    id: "lockout", kind: .lockout,
                    severity: numbers.count * 3 >= n ? .major : .minor,
                    title: "\(shortLabel(numbers)) not fully reset",
                    detail: "\(repLabel(numbers)) did not return to the start position, finishing up to \(Int(worst.rounded())) degrees short.",
                    cue: "Return all the way to the start before the next rep.",
                    reps: numbers, time: numbers.first.flatMap(time(of:))))
            }
        }

        let rank: [FindingSeverity: Int] = [.major: 0, .minor: 1, .good: 2]
        findings = findings.enumerated()
            .sorted { (rank[$0.element.severity] ?? 3, $0.offset) < (rank[$1.element.severity] ?? 3, $1.offset) }
            .map(\.element)

        let summaries = reps.map { rep in
            RepSummary(rep: rep,
                       rangePercent: best > 0 ? min(100, rep.amplitudeDegrees / best * 100) : 100,
                       flags: FormCheckKind.allCases.filter { flags[rep.number]?.contains($0) == true })
        }
        let flaggedCount = summaries.filter { !$0.isClean }.count
        var score = 100
        for f in findings {
            if f.severity == .minor { score -= 6 } else if f.severity == .major { score -= 15 }
        }
        score -= min(20, flaggedCount * 2)
        score = min(100, max(40, score))

        return FormAnalysis(exerciseName: exerciseName, profile: profile, detection: detection,
                            reps: summaries, findings: findings, score: score)
    }

    // MARK: Torso sway

    /// Peak-to-peak change of the shoulder-mid to hip-mid line (degrees from vertical) within a rep.
    private static func torsoSwing(in track: PoseTrack, from start: TimeInterval, to end: TimeInterval) -> Double? {
        let aspect = track.aspectRatio > 0 ? track.aspectRatio : 1
        var angles: [Double] = []
        for f in track.frames where f.time >= start && f.time <= end {
            let shoulders = [BodyJoint.leftShoulder, .rightShoulder].compactMap { PoseGeometry.point(f, $0) }
            let hips = [BodyJoint.leftHip, .rightHip].compactMap { PoseGeometry.point(f, $0) }
            guard !shoulders.isEmpty, !hips.isEmpty else { continue }
            let sx = shoulders.map(\.x).reduce(0, +) / Double(shoulders.count)
            let sy = shoulders.map(\.y).reduce(0, +) / Double(shoulders.count)
            let hx = hips.map(\.x).reduce(0, +) / Double(hips.count)
            let hy = hips.map(\.y).reduce(0, +) / Double(hips.count)
            angles.append(atan2((sx - hx) * aspect, hy - sy) * 180 / .pi)
        }
        guard angles.count >= 5 else { return nil }
        var med = angles
        for i in 1..<(angles.count - 1) { med[i] = RepDetector.median([angles[i - 1], angles[i], angles[i + 1]]) }
        guard let lo = med.min(), let hi = med.max() else { return nil }
        return hi - lo
    }

    // MARK: Not trackable

    private static func cantTrackFinding(profile: MovementProfile, detection: RepDetection) -> FormFinding {
        if !profile.isTracked {
            return FormFinding(id: "untracked", kind: .rangeConsistency, severity: .minor,
                               title: "Rep tracking unavailable",
                               detail: "Rep tracking isn't available for this exercise.",
                               cue: "Log your sets as usual.", reps: [], time: nil)
        }
        if detection.trackingQuality < 0.5 {
            let part = detection.angle.visibleBodyPart
            return FormFinding(id: "cantTrack", kind: .rangeConsistency, severity: .major,
                               title: "Couldn't see your \(part)",
                               detail: "The camera couldn't see your \(part) well enough to count reps. \(profile.cameraTip)",
                               cue: "Record again with your \(part) in view.", reps: [], time: nil)
        }
        return FormFinding(id: "noReps", kind: .rangeConsistency, severity: .major,
                           title: "No clear reps found",
                           detail: "I could see you but didn't find a steady set of reps. Record the whole set, starting and ending at rest. \(profile.cameraTip)",
                           cue: "Record the full set in one take.", reps: [], time: nil)
    }

    // MARK: Wording

    private static func runs(_ numbers: [Int]) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for n in numbers.sorted() {
            if let last = out.last, n == last.1 + 1 { out[out.count - 1].1 = n } else { out.append((n, n)) }
        }
        return out
    }

    /// "Rep 3", "Reps 7–9", "Reps 2, 5–6 and 9".
    static func repLabel(_ numbers: [Int]) -> String {
        let parts = runs(numbers).map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0)–\($0.1)" }
        let prefix = numbers.count == 1 ? "Rep" : "Reps"
        switch parts.count {
        case 0: return ""
        case 1: return "\(prefix) \(parts[0])"
        default: return "\(prefix) \(parts.dropLast().joined(separator: ", ")) and \(parts[parts.count - 1])"
        }
    }

    /// Short form for titles: falls back to a count when the list is long.
    private static func shortLabel(_ numbers: [Int]) -> String {
        runs(numbers).count <= 2 ? repLabel(numbers).replacingOccurrences(of: " and ", with: ", ") : "\(numbers.count) reps"
    }
}

// MARK: - Setup check

struct SetupStatus: Equatable {
    let isReady: Bool
    let missing: [String]
    let message: String
}

enum SetupCheck {
    /// Evaluates the most recent ~1 s of frames: ready when the joints for the profile's primary
    /// angle are visible (confidence >= 0.3) on at least one side in >= 70% of them.
    static func evaluate(recent: [PoseFrame], profile: MovementProfile) -> SetupStatus {
        guard profile.isTracked else {
            return SetupStatus(isReady: false, missing: [], message: profile.cameraTip)
        }
        let part = profile.primary.visibleBodyPart
        guard let latest = recent.last?.time else {
            return SetupStatus(isReady: false, missing: [part], message: "I can't see your \(part). \(profile.cameraTip)")
        }
        let window = recent.filter { $0.time >= latest - 1.0 }
        var ok = 0
        for f in window {
            let seen = [BodySide.left, .right].contains { side in
                let (a, b, c) = profile.primary.joints(side)
                return [a, b, c].allSatisfy { PoseGeometry.point(f, $0, minConfidence: 0.3) != nil }
            }
            if seen { ok += 1 }
        }
        if !window.isEmpty, Double(ok) / Double(window.count) >= 0.7 {
            return SetupStatus(isReady: true, missing: [], message: "Ready, I can see your \(part)")
        }
        return SetupStatus(isReady: false, missing: [part], message: "I can't see your \(part). \(profile.cameraTip)")
    }
}
