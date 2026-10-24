import AppIntents
import Foundation

/// Where the intents deliver actions. A `LiveActivityIntent` runs in the app's own
/// process (even when it is backgrounded), where `LightstackApp` installs the handler.
/// In the widget extension the handler is never set; the intent is only rendered there.
enum LiveActivityActionRouter {
    @MainActor static var handler: ((LiveActivityAction, String) async -> Void)?
}

/// One intent for every Live Activity button: no typing, just tap.
struct WorkoutActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Workout Action"
    static var description = IntentDescription("Adjusts or logs the current set of the active workout.")

    @Parameter(title: "Action")
    var actionRaw: String

    @Parameter(title: "Set")
    var setKey: String

    init() {
        actionRaw = ""
        setKey = ""
    }

    init(_ action: LiveActivityAction, setKey: String) {
        self.actionRaw = action.rawValue
        self.setKey = setKey
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let action = LiveActivityAction(rawValue: actionRaw) {
            await LiveActivityActionRouter.handler?(action, setKey)
        }
        return .result()
    }
}
