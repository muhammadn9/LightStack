import Foundation

/// Which feature an AI call belongs to. Drives output caps and the DEBUG usage counter.
enum AITask: String, CaseIterable {
    case plan, chat, postWorkout, monthPlan, formFeedback, nutrition, other

    var label: String {
        switch self {
        case .plan: return "Plan"
        case .chat: return "Chat"
        case .postWorkout: return "Post-workout"
        case .monthPlan: return "Month plan"
        case .formFeedback: return "Form feedback"
        case .nutrition: return "Nutrition"
        case .other: return "Other"
        }
    }
}

/// Per-call generation settings. Defaults reproduce the old behaviour
/// (8192 tokens, default thinking) so existing callers and tests keep working.
struct AIRequestOptions: Equatable {
    var task: AITask = .other
    var maxOutputTokens: Int = 8192
    var temperature: Double = 0.7
    /// How much the model may think before answering. `.modelDefault` sends no thinking field.
    var thinking: ThinkingEffort = .modelDefault
    /// Turns on Gemini's Google Search tool (`tools: [{"google_search":{}}]`). The ai-proxy accepts only that
    /// exact tool, and drops JSON mode when it is on, so callers ask for JSON in the prompt and parse leniently.
    var googleSearch: Bool = false
    /// Optional Gemini response schema. Only sent when the call expects JSON, and not sent when googleSearch is on.
    var schema: AIResponseSchema?

    /// The ai-proxy accepts thinkingBudget 0...4096 or thinkingLevel minimal/low/medium.
    enum ThinkingEffort: Equatable {
        case modelDefault
        /// As little as possible (saves tokens and latency).
        case minimal
        /// A small real budget (1024 tokens on Gemini 2.5, level "low" on Gemini 3.x).
        case low
        /// Deeper reasoning (4096 tokens on Gemini 2.5, level "medium" on Gemini 3.x).
        /// Thinking tokens count toward maxOutputTokens.
        case medium
    }

    /// True when any thinking field is sent.
    var sendsThinking: Bool { thinking != .modelDefault }

    static let `default` = AIRequestOptions()

    /// Caps are the largest realistic output for each task, plus headroom.
    static func forTask(_ task: AITask) -> AIRequestOptions {
        switch task {
        case .plan: return AIRequestOptions(task: task, maxOutputTokens: 8192, thinking: .medium)
        case .chat: return AIRequestOptions(task: task, maxOutputTokens: 1000, thinking: .minimal)
        case .postWorkout: return AIRequestOptions(task: task, maxOutputTokens: 800, thinking: .minimal)
        case .monthPlan: return AIRequestOptions(task: task, maxOutputTokens: 4000, thinking: .minimal)
        case .formFeedback: return AIRequestOptions(task: task, maxOutputTokens: 1200, temperature: 0.3, thinking: .minimal)
        case .nutrition: return AIRequestOptions(task: task, maxOutputTokens: 3000, temperature: 0.2, thinking: .low)
        case .other: return .default
        }
    }
}

/// A Gemini `responseSchema`, held as a JSON-like dictionary so options stay Equatable.
struct AIResponseSchema: Equatable {
    let definition: [String: Any]

    init(_ definition: [String: Any]) { self.definition = definition }

    static func == (lhs: AIResponseSchema, rhs: AIResponseSchema) -> Bool {
        NSDictionary(dictionary: lhs.definition).isEqual(to: rhs.definition)
    }
}
