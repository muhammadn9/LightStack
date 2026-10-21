import Foundation

/// Which feature an AI call belongs to. Drives output caps and the DEBUG usage counter.
enum AITask: String, CaseIterable {
    case plan, chat, postWorkout, monthPlan, formFeedback, other

    var label: String {
        switch self {
        case .plan: return "Plan"
        case .chat: return "Chat"
        case .postWorkout: return "Post-workout"
        case .monthPlan: return "Month plan"
        case .formFeedback: return "Form feedback"
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

    /// The ai-proxy only accepts thinkingBudget 0...1024 or thinkingLevel minimal/low.
    enum ThinkingEffort: Equatable {
        case modelDefault
        /// As little as possible (saves tokens and latency).
        case minimal
        /// A small real budget (1024 tokens on Gemini 2.5, level "low" on Gemini 3.x).
        case low
    }

    /// True when any thinking field is sent.
    var sendsThinking: Bool { thinking != .modelDefault }

    static let `default` = AIRequestOptions()

    /// Caps are the largest realistic output for each task, plus headroom.
    static func forTask(_ task: AITask) -> AIRequestOptions {
        switch task {
        case .plan: return AIRequestOptions(task: task, maxOutputTokens: 6144, thinking: .low)
        case .chat: return AIRequestOptions(task: task, maxOutputTokens: 1000, thinking: .minimal)
        case .postWorkout: return AIRequestOptions(task: task, maxOutputTokens: 800, thinking: .minimal)
        case .monthPlan: return AIRequestOptions(task: task, maxOutputTokens: 4000, thinking: .minimal)
        case .formFeedback: return AIRequestOptions(task: task, maxOutputTokens: 600, thinking: .minimal)
        case .other: return .default
        }
    }
}
