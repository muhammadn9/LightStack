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
    /// Ask the model to think as little as possible (saves tokens and latency).
    var minimalThinking: Bool = false

    static let `default` = AIRequestOptions()

    /// Caps are the largest realistic output for each task, plus headroom.
    static func forTask(_ task: AITask) -> AIRequestOptions {
        switch task {
        case .plan: return AIRequestOptions(task: task, maxOutputTokens: 3000, minimalThinking: true)
        case .chat: return AIRequestOptions(task: task, maxOutputTokens: 1000, minimalThinking: true)
        case .postWorkout: return AIRequestOptions(task: task, maxOutputTokens: 800, minimalThinking: true)
        case .monthPlan: return AIRequestOptions(task: task, maxOutputTokens: 4000, minimalThinking: true)
        case .formFeedback: return AIRequestOptions(task: task, maxOutputTokens: 600, minimalThinking: true)
        case .other: return .default
        }
    }
}
