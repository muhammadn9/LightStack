import ActivityKit
import Combine
import Foundation
import os

/// Owns the workout Live Activity: starts it with the session, keeps it in step with the
/// on-screen state, runs the button actions, and ends it when the session ends.
@MainActor
final class LiveActivityController {

    static let shared = LiveActivityController()
    static let settingKey = "liveActivityEnabled"

    private let logger = Logger(subsystem: "org.lightstack.app", category: "LiveActivity")
    private weak var active: ActiveWorkoutViewModel?
    private weak var today: TodayViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var lastState: LightstackWorkoutAttributes.ContentState?

    private init() {}

    /// The "Live Activity on lock screen" setting (default on).
    static var isSettingEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// Whether the system lets this app show Live Activities (user can disable them in Settings).
    static var isSystemAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var isAllowed: Bool {
        #if DEBUG
        if UITestMode.isActive { return false }
        #endif
        return Self.isSettingEnabled && Self.isSystemAvailable
    }

    // MARK: - Lifecycle

    /// Called when the active workout screen appears (new workout or restored session).
    func attach(active: ActiveWorkoutViewModel, today: TodayViewModel) {
        guard self.active !== active || self.today !== today else {
            refresh()
            return
        }
        self.active = active
        self.today = today
        cancellables.removeAll()

        let changes: [AnyPublisher<Void, Never>] = [
            active.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            active.clock.$isPaused.map { _ in () }.eraseToAnyPublisher(),
            today.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    /// Ends every workout Live Activity (workout finished, discarded, or setting turned off).
    func end() {
        cancellables.removeAll()
        lastState = nil
        let final = Activity<LightstackWorkoutAttributes>.activities
        for activity in final {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// App launch: a Live Activity left over from a session that no longer exists must go.
    func endIfNoSession(phase: TodayPhase) {
        if phase != .active { end() }
    }

    func settingChanged() {
        if Self.isSettingEnabled {
            refresh()
        } else {
            end()
        }
    }

    // MARK: - Updating

    private func currentState() -> LightstackWorkoutAttributes.ContentState? {
        guard let active, let today, today.phase == .active else { return nil }
        active.syncElapsed()
        let unit = UserDefaults.standard.string(forKey: "weightUnit") == "kg" ? "kg" : "lb"
        return LiveActivityMapper.contentState(
            exercises: today.exercises,
            loggedSets: active.loggedSets,
            pendingSets: active.pendingSets,
            setTargets: today.setTargets,
            activeRestExerciseId: active.activeRestExerciseId,
            restTargetDates: active.restTimerTargetDates,
            elapsedSeconds: active.elapsedSeconds,
            isPaused: active.isPaused,
            unit: unit
        )
    }

    func refresh() {
        Task { await refreshAndWait() }
    }

    func refreshAndWait() async {
        guard isAllowed, let today else { return }
        guard today.phase == .active, var state = currentState() else {
            if today.phase != .active { end() }
            return
        }
        // Ignore clock jitter so a tick alone does not cost an update.
        if let last = lastState, abs(last.elapsedAnchor.timeIntervalSince(state.elapsedAnchor)) < 2 {
            state.elapsedAnchor = last.elapsedAnchor
        }
        guard state != lastState else { return }
        lastState = state

        let content = ActivityContent(state: state, staleDate: nil)
        if let existing = Activity<LightstackWorkoutAttributes>.activities.first {
            // Drop duplicates (e.g. after a crash) so only one stays on the lock screen.
            for extra in Activity<LightstackWorkoutAttributes>.activities.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            await existing.update(content)
        } else {
            let name = today.sessionService.currentWorkoutType ?? "Workout"
            do {
                _ = try Activity.request(
                    attributes: LightstackWorkoutAttributes(workoutName: name),
                    content: content,
                    pushType: nil
                )
            } catch {
                logger.error("Could not start Live Activity: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Button actions

    /// Runs on the main actor inside the app process, including while backgrounded.
    func handle(_ action: LiveActivityAction, setKey: String) async {
        guard let active, let today, today.phase == .active else { return }
        let changed = LiveActivityActions.apply(action, setKey: setKey, active: active, today: today)
        if changed { active.persistSession(to: today) }
        // Skip the debounce: the lock screen should answer the tap right away, and the
        // intent waits on this so the process is not suspended mid-update.
        await refreshAndWait()
    }
}
