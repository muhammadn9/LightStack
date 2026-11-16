import Foundation

struct FormFix: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let why: String
    let cue: String
    let reps: [Int]
    /// Label of the key frame the coach saw this in ("Rep 6 peak"), used to seek the replay.
    var frame: String? = nil
}

struct FormFeedback: Equatable, Codable {
    let verdict: String          // one sentence overall
    let positives: [String]      // 0-2 short things done well
    let fixes: [FormFix]         // 0-3, most important first
    let estimatedReps: Int?      // only when the tracker could not count
}

/// What asking the coach produced: feedback, or the reason there is none.
enum FormFeedbackResult: Equatable {
    case success(FormFeedback)
    case failure(AIFailureReason)

    var feedback: FormFeedback? {
        if case .success(let f) = self { return f }
        return nil
    }
}

/// Anything that can produce coach feedback for a recorded set (lets the results screen be tested).
protocol FormFeedbackProviding {
    func feedback(for result: FormSessionResult) async -> FormFeedbackResult
}

/// Sends the rep table and a contact sheet of the recorded set to the AI and turns the reply into short,
/// specific feedback. Never throws: any failure is `.failure(reason)` and the screen shows measurements only.
final class FormFeedbackService: FormFeedbackProviding {

    private let aiServiceManager: AIServiceManager

    init(aiServiceManager: AIServiceManager) {
        self.aiServiceManager = aiServiceManager
    }

    func feedback(for result: FormSessionResult) async -> FormFeedbackResult {
        let sheet = await FormKeyFrameSheet.makeSheet(for: result)
        guard !Task.isCancelled else { return .failure(.other) }
        let prompt = Self.buildUserPrompt(analysis: result.analysis, hasImage: sheet != nil,
                                          frameLabels: sheet?.moments.map(\.label) ?? [])
        let message = ChatMessage(role: .user, content: prompt, imageJPEG: sheet?.data)
        var options = AIRequestOptions.forTask(.formFeedback)
        options.schema = Self.responseSchema

        let reply: Result<String, Error> = await withCheckedContinuation { continuation in
            aiServiceManager.generateChat(systemPrompt: Self.systemPrompt, messages: [message],
                                          expectsJSON: true, options: options) { reply in
                continuation.resume(returning: reply)
            }
        }
        switch reply {
        case .failure(let error):
            return .failure(AIFailureReason.classify(error))
        case .success(let text):
            guard let feedback = Self.parse(text) else { return .failure(.other) }
            return .success(feedback)
        }
    }

    // MARK: Prompt

    static let measuredNote = "The lifter already sees the measured range, tempo, left/right and sway results on screen. "
        + "Do NOT restate them or anything derivable from the table. Your job is what the numbers cannot show."

    static let systemPrompt = """
    You are an experienced strength coach looking at frames from ONE recorded set of a named exercise. The \
    lifter reads your notes between sets. Your only job is to say what the numbers cannot: what your eyes \
    see in the frames.

    You are given:
    1. A short MEASUREMENT summary from on-device body tracking: the rep count, a per-rep table, and which \
    reps the tracker flagged. The lifter already sees the measured range, tempo, left/right and sway results \
    on screen. Do NOT restate them or anything derivable from the table (rep count, range, timing, "reps got \
    shorter", "rushed", "uneven sides"). The flagged reps only tell you where to look.
    2. An IMAGE: one grid of frames in up to 3 columns by 2 rows, all cropped the same way around the lifter \
    so they can be compared. Each frame is labelled ("Rep 3 start", "Rep 3 peak", or a time such as "0:07"). \
    A thin, semi-transparent skeleton from the tracker is drawn on each (green lines are the joints that \
    drive this exercise).
    3. WHAT TO LOOK FOR on this movement: the visual checks only eyes can make.

    How to judge:
    - Judge only what is visible from this camera angle. If a joint, the bar or the weight is hidden, do not \
    guess about it. The skeleton is a hint, not the truth: trust your own eyes where they disagree.
    - Compare the same joint across frames (first rep against the worst and the last).
    - Every fix must cite the frame it was seen in. Set "frame" to that frame's exact label (for example \
    "Rep 6 peak") and start "why" with the label and a colon, for example "Rep 6 peak: the elbow flares wide \
    of the ribs." Never cite a frame that is not in the image.
    - No generic advice. Do not repeat a cue the lifter is already doing correctly. Never invent a problem.
    - If you see nothing worth changing beyond what the measurements already show, return NO fixes and a \
    short honest verdict such as "Nothing extra to fix from this angle". You may add what camera angle \
    would let you judge more.

    Rules:
    - Never contradict the measured rep count when the tracking status is good or partial.
    - When the tracking status is insufficient, or the exercise is not tracked, estimate the number of reps \
    from the frames only if you can actually see it. Otherwise set estimatedReps to null. When the tracking \
    status is good or partial, always set estimatedReps to null.
    - At most 3 fixes, most important first. Only include a fix you can point to in a frame.
    - Each fix has: "title" (6 words or fewer, plain language), "why" (one sentence: the frame label, then \
    what you saw), "cue" (one short instruction the lifter can think about on the next set, 12 words or \
    fewer), "reps" (the rep numbers it applies to, or an empty list when it applies to all reps or you \
    cannot tell) and "frame" (the label of the frame it was seen in).
    - "verdict" is one sentence of 20 words or fewer summarising what you saw.
    - "positives" has 0 to 2 items of 10 words or fewer each: things you can see the lifter doing well.
    - No medical claims or injury diagnoses. No jargon without a plain explanation. No hedging filler such \
    as "it seems" or "maybe". No markdown. No em dashes.
    - If the image is missing, or the lifter cannot be seen in it, say so in the verdict and return no fixes.

    Reply with ONE JSON object and nothing else, exactly this shape:
    {"verdict": string, "positives": [string], "fixes": [{"title": string, "why": string, "cue": string, \
    "reps": [integer], "frame": string}], "estimatedReps": integer or null}
    """

    static func buildUserPrompt(analysis: FormAnalysis, hasImage: Bool, frameLabels: [String] = []) -> String {
        var lines: [String] = []
        lines.append("Exercise: \(analysis.exerciseName)")
        lines.append("Tracking status: \(analysis.detection.status.rawValue)")
        if analysis.profile.isTracked {
            if analysis.reps.isEmpty {
                lines.append("The tracker could not count reps for this set.")
            } else {
                lines.append("Measured rep count: \(analysis.repCount). Do not contradict it.")
            }
        } else {
            lines.append("This exercise is not tracked, so there is no measured rep count.")
        }
        lines.append("")
        lines.append(measuredNote)
        lines.append("")
        lines.append("PER-REP TABLE (on-device 2D body tracking, one camera angle):")
        lines.append(analysis.summaryForPrompt(includeFindings: false))
        let flagged = analysis.reps.filter { !$0.isClean }.map(\.rep.number)
        if !analysis.reps.isEmpty {
            lines.append(flagged.isEmpty
                ? "The tracker flagged no reps."
                : "The tracker flagged \(FormAnalyzer.repLabel(flagged)). Look at those frames first, but do not restate why.")
        }
        lines.append("")
        lines.append("WHAT TO LOOK FOR on this movement (judge each from the frames, skip any you cannot see):")
        for check in analysis.profile.visualChecks { lines.append("- \(check)") }
        lines.append("")
        if hasImage {
            var text = "IMAGE: attached. A grid of frames from the video, each labelled and cropped to the lifter, "
                + "with the tracked skeleton drawn thinly on."
            if !frameLabels.isEmpty { text += " Frame labels: " + frameLabels.joined(separator: ", ") + "." }
            lines.append(text)
        } else {
            lines.append("IMAGE: none. No video frames are available, so you cannot see the set: say so in the verdict "
                         + "and return no fixes.")
        }
        lines.append("")
        lines.append("Return the JSON now.")
        return lines.joined(separator: "\n")
    }

    static let responseSchema: AIResponseSchema = {
        let string: [String: Any] = ["type": "STRING"]
        let fix: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "title": string, "why": string, "cue": string, "frame": string,
                "reps": ["type": "ARRAY", "items": ["type": "INTEGER"]] as [String: Any]
            ] as [String: Any],
            "required": ["title", "why", "cue", "reps"]
        ]
        return AIResponseSchema([
            "type": "OBJECT",
            "properties": [
                "verdict": string,
                "positives": ["type": "ARRAY", "items": string] as [String: Any],
                "fixes": ["type": "ARRAY", "items": fix] as [String: Any],
                "estimatedReps": ["type": "INTEGER", "nullable": true] as [String: Any]
            ] as [String: Any],
            "required": ["verdict", "positives", "fixes"]
        ])
    }()

    // MARK: Parsing

    static let maxFixes = 3
    static let maxPositives = 2

    /// Lenient: fenced or wrapped JSON, unknown keys, too many items, stray whitespace. nil for anything that
    /// is not recognisably feedback.
    static func parse(_ text: String) -> FormFeedback? {
        guard let json = NutritionAIParser.firstJSONObject(in: text),
              let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        let verdict = clean(root["verdict"])
        let positives = ((root["positives"] as? [Any]) ?? [])
            .compactMap(clean)
            .filter { !$0.isEmpty }
            .prefix(maxPositives)
        var fixes: [FormFix] = []
        for case let raw as [String: Any] in (root["fixes"] as? [Any]) ?? [] {
            let title = clean(raw["title"]), why = clean(raw["why"]), cue = clean(raw["cue"])
            guard !title.isEmpty, !(why.isEmpty && cue.isEmpty) else { continue }
            let reps = Array(Set(((raw["reps"] as? [Any]) ?? []).compactMap(int))).filter { $0 > 0 }.sorted()
            let frame = clean(raw["frame"])
            fixes.append(FormFix(id: "fix-\(fixes.count + 1)", title: title, why: why, cue: cue, reps: reps,
                                 frame: frame.isEmpty ? nil : frame))
            if fixes.count == maxFixes { break }
        }
        guard !verdict.isEmpty || !fixes.isEmpty else { return nil }
        let estimate = (root["estimatedReps"] ?? root["estimated_reps"]).flatMap(int).flatMap { (1...200).contains($0) ? $0 : nil }
        return FormFeedback(verdict: verdict, positives: Array(positives), fixes: fixes, estimatedReps: estimate)
    }

    private static func clean(_ value: Any?) -> String {
        guard let s = value as? String else { return "" }
        return s.replacingOccurrences(of: " \u{2014} ", with: ", ")
            .replacingOccurrences(of: "\u{2014}", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func int(_ value: Any) -> Int? {
        if let n = value as? Int { return n }
        if let d = value as? Double, d.isFinite { return Int(d.rounded()) }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}
