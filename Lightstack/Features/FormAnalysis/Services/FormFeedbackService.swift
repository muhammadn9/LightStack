import Foundation

struct FormFix: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let why: String
    let cue: String
    let reps: [Int]
}

struct FormFeedback: Equatable, Codable {
    let verdict: String          // one sentence overall
    let positives: [String]      // 0-2 short things done well
    let fixes: [FormFix]         // 0-3, most important first
    let estimatedReps: Int?      // only when the tracker could not count
}

/// Anything that can produce coach feedback for a recorded set (lets the results screen be tested).
protocol FormFeedbackProviding {
    func feedback(for result: FormSessionResult) async -> FormFeedback?
}

/// Sends the measurements and a contact sheet of the recorded set to the AI and turns the reply into
/// short, specific feedback. Never throws: any failure is `nil` and the screen shows measurements only.
final class FormFeedbackService: FormFeedbackProviding {

    private let aiServiceManager: AIServiceManager

    init(aiServiceManager: AIServiceManager) {
        self.aiServiceManager = aiServiceManager
    }

    func feedback(for result: FormSessionResult) async -> FormFeedback? {
        let image = await FormKeyFrameSheet.sheet(for: result)
        guard !Task.isCancelled else { return nil }
        let prompt = Self.buildUserPrompt(analysis: result.analysis, hasImage: image != nil)
        let message = ChatMessage(role: .user, content: prompt, imageJPEG: image)
        var options = AIRequestOptions.forTask(.formFeedback)
        options.schema = Self.responseSchema

        let text: String? = await withCheckedContinuation { continuation in
            aiServiceManager.generateChat(systemPrompt: Self.systemPrompt, messages: [message],
                                          expectsJSON: true, options: options) { reply in
                continuation.resume(returning: try? reply.get())
            }
        }
        guard let text else { return nil }
        return Self.parse(text)
    }

    // MARK: Prompt

    static let systemPrompt = """
    You are an experienced strength coach reviewing ONE recorded set of a named exercise for a lifter who \
    will read your feedback between sets. Be specific, short and easy to act on.

    You are given two things:
    1. MEASUREMENTS from on-device body tracking of the video. They come from 2D tracking of a single camera \
    angle. They are reliable for rep count, range of motion and tempo. They are weaker for anything that \
    depends on depth or the other side of the body.
    2. An IMAGE: one grid of frames from the video, in time order. Each frame is labelled ("Rep 3 start", \
    "Rep 3 peak", or a timestamp such as "0:07") and has the tracked skeleton drawn on it (green lines are \
    the joints that drive this exercise).

    Use the frames for what numbers cannot show: joint positions, bar or dumbbell path, torso angle, \
    elbow, knee and wrist alignment, range at the peak, bracing and setup. Judge only what is actually \
    visible from this camera angle. If a joint or the weight is hidden, do not guess about it. Treat the \
    skeleton as a hint, not as the truth: trust your own eyes where they disagree.

    The REFERENCE STANDARD in the user message lists what good form looks like on this movement. Compare \
    what you see against it.

    Rules:
    - Never contradict the measured rep count when the tracking status is good or partial.
    - When the tracking status is insufficient, or the exercise is not tracked, estimate the number of reps \
    from the frames only if you can actually see it. Otherwise set estimatedReps to null. When the tracking \
    status is good or partial, always set estimatedReps to null.
    - Never invent a problem. If the form looks good, return no fixes and say so in the verdict.
    - At most 3 fixes, most important first. Only include a fix you can point to in the frames or the \
    measurements.
    - Each fix has: "title" (6 words or fewer, plain language), "why" (one sentence saying what you saw and on \
    which reps), "cue" (one short instruction the lifter can think about on the next set, 12 words or \
    fewer), and "reps" (the rep numbers it applies to, or an empty list when it applies to all reps or you \
    cannot tell).
    - "verdict" is one sentence of 20 words or fewer summarising the set.
    - "positives" has 0 to 2 items of 10 words or fewer each: things the lifter did well.
    - No medical claims or injury diagnoses. No jargon without a plain explanation. No hedging filler such \
    as "it seems" or "maybe". No markdown. No em dashes.
    - If the image is missing, or the lifter cannot be seen in it, say so in the verdict and base the fixes \
    only on the measurements.

    Reply with ONE JSON object and nothing else, exactly this shape:
    {"verdict": string, "positives": [string], "fixes": [{"title": string, "why": string, "cue": string, \
    "reps": [integer]}], "estimatedReps": integer or null}
    """

    static func buildUserPrompt(analysis: FormAnalysis, hasImage: Bool) -> String {
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
        lines.append("MEASUREMENTS (on-device 2D body tracking, one camera angle):")
        lines.append(analysis.summaryForPrompt())
        lines.append("")
        lines.append("REFERENCE STANDARD for good form on this movement:")
        if analysis.profile.isTracked {
            for cue in analysis.profile.cues { lines.append("- \(cue)") }
        } else {
            lines.append("- None on file for this exercise. Use general good technique for it.")
        }
        lines.append("")
        if hasImage {
            lines.append("IMAGE: attached. It is a grid of frames from the video in time order, each labelled, "
                         + "with the tracked skeleton drawn on.")
        } else {
            lines.append("IMAGE: none. No video frames are available, so base your fixes only on the measurements "
                         + "and say in the verdict that you could not see the set.")
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
                "title": string, "why": string, "cue": string,
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
            fixes.append(FormFix(id: "fix-\(fixes.count + 1)", title: title, why: why, cue: cue, reps: reps))
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
