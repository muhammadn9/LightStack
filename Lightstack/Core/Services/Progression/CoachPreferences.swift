import Foundation

/// What the athlete is training for. Drives rep ranges and rest in `ProgressionEngine`.
enum CoachFocus: String, Codable, CaseIterable, Equatable {
    case hypertrophy, strength, maintenance

    var title: String {
        switch self {
        case .hypertrophy: return "Muscle"
        case .strength: return "Strength"
        case .maintenance: return "Maintain"
        }
    }
}

/// Coach settings kept in UserDefaults (no schema change). Hands-off by default:
/// nothing here has to be set for the coach to work.
enum CoachPreferences {
    static let focusKey = "coach.focus"
    /// Neutral energy used when the athlete does not say how they feel.
    static let neutralEnergy = 6
    /// Session length used when there is no history and no profile default.
    static let fallbackMinutes = 45

    static let aiSetsWeightsKey = "coach.aiSetsWeights"

    /// Rollback switch for coach v3. true (default): the AI coach writes every weight, rep, RIR and rest
    /// and the app only enforces safety rails. false: the v2 path, where the rule-based engine computes
    /// the numbers and the AI only reviews the structure.
    static var aiSetsWeights: Bool {
        get { aiSetsWeights(in: .standard) }
        set { UserDefaults.standard.set(newValue, forKey: aiSetsWeightsKey) }
    }

    static func aiSetsWeights(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: aiSetsWeightsKey) as? Bool ?? true
    }

    /// The explicitly chosen focus, if any.
    static func storedFocus(in defaults: UserDefaults = .standard) -> CoachFocus? {
        defaults.string(forKey: focusKey).flatMap(CoachFocus.init(rawValue:))
    }

    /// Hypertrophy unless the athlete picked something else.
    static var focus: CoachFocus {
        get { storedFocus() ?? .hypertrophy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: focusKey) }
    }

    static func setFocus(_ focus: CoachFocus?, in defaults: UserDefaults = .standard) {
        if let focus { defaults.set(focus.rawValue, forKey: focusKey) } else { defaults.removeObject(forKey: focusKey) }
    }

    /// Request override > stored preference > hypertrophy. Never inferred from profile text.
    static func resolvedFocus(override: CoachFocus? = nil, in defaults: UserDefaults = .standard) -> CoachFocus {
        override ?? storedFocus(in: defaults) ?? .hypertrophy
    }
}

// MARK: - Goals

/// One step on the way to a goal, as the athlete agreed it in chat.
struct CoachGoalStep: Codable, Equatable, Identifiable {
    var id = UUID()
    /// "YYYY-MM-DD" when the coach gave a date.
    var date: String?
    var text: String
    var weight: Double?
    var reps: Int?
    /// True for the step that is the attempt itself.
    var attempt: Bool = false
}

/// A lift target the athlete agreed with the coach ("225x1 on Barbell Bench Press").
struct CoachGoal: Codable, Identifiable, Equatable {
    enum Status: String, Codable, Equatable { case active, achieved, dropped }

    var id = UUID()
    var exerciseName: String
    var targetWeight: Double
    var targetReps: Int
    var deadline: Date?
    var createdAt = Date()
    var status: Status = .active
    var steps: [CoachGoalStep] = []
    /// The app's numbers at the time ("APP CHECK" line), kept for reference.
    var assessment: String?

    /// "225x1"
    var targetText: String { "\(String(format: "%g", targetWeight))x\(targetReps)" }

    /// "Barbell Bench Press 225x1, by Dec 1"
    var summary: String {
        var text = "\(exerciseName) \(targetText)"
        if let deadline { text += ", by \(deadline.formatted(.dateTime.month(.abbreviated).day()))" }
        return text
    }

    /// "2026-12-01" -> a date at noon local time (nil when it does not parse).
    static func parseDay(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: String(text.prefix(10))) else { return nil }
        return Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? day
    }
}

/// The athlete's goals, kept in UserDefaults as JSON per user (no schema change).
final class CoachGoalStore {
    static let shared = CoachGoalStore()
    /// Oldest goals beyond this many are dropped.
    static let maxGoals = 50

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(for userId: UUID) -> String { "coach.goals.\(userId.uuidString)" }

    /// Every goal, oldest first.
    func goals(for userId: UUID) -> [CoachGoal] {
        guard let data = defaults.data(forKey: Self.key(for: userId)),
              let goals = try? JSONDecoder().decode([CoachGoal].self, from: data) else { return [] }
        return goals
    }

    func activeGoals(for userId: UUID) -> [CoachGoal] {
        goals(for: userId).filter { $0.status == .active }
    }

    /// Adds the goal (or replaces the one with the same id).
    func add(_ goal: CoachGoal, for userId: UUID) {
        var all = goals(for: userId)
        if let index = all.firstIndex(where: { $0.id == goal.id }) {
            all[index] = goal
        } else {
            all.append(goal)
        }
        save(all, for: userId)
    }

    /// Replaces the goal with the same id. Unknown ids are ignored.
    func update(_ goal: CoachGoal, for userId: UUID) {
        var all = goals(for: userId)
        guard let index = all.firstIndex(where: { $0.id == goal.id }) else { return }
        all[index] = goal
        save(all, for: userId)
    }

    func setStatus(_ status: CoachGoal.Status, goalId: UUID, for userId: UUID) {
        guard var goal = goals(for: userId).first(where: { $0.id == goalId }) else { return }
        goal.status = status
        update(goal, for: userId)
    }

    private func save(_ goals: [CoachGoal], for userId: UUID) {
        let kept = Array(goals.suffix(Self.maxGoals))
        guard let data = try? JSONEncoder().encode(kept) else { return }
        defaults.set(data, forKey: Self.key(for: userId))
    }
}

// MARK: - Goals in the plan

/// One active goal with the app's numbers and the step that applies to today's workout.
struct GoalPlanItem: Equatable {
    var goal: CoachGoal
    var assessment: GoalAssessor.Assessment?
    var step: CoachGoalStep?
    /// True when the step is undated or dated today (false for a later dated step).
    var stepIsToday: Bool

    /// Today's step is the attempt itself and the app judges the goal within reach now.
    var attemptToday: Bool {
        guard stepIsToday, step?.attempt == true, let a = assessment else { return false }
        return a.verdict == .realisticNow
    }
}

/// Turns active goals into plan-prompt items, rail allowances and "achieved" checks. Pure, so it is testable.
enum GoalPlanner {
    /// At most this many goals go into one plan prompt.
    static let maxGoalsInPrompt = 3

    /// The step dated today, else the first undated step, else the nearest future dated step.
    static func todayStep(of goal: CoachGoal, now: Date = Date()) -> (step: CoachGoalStep, isToday: Bool)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var dated: [(step: CoachGoalStep, day: Date)] = []
        var undated: [CoachGoalStep] = []
        for step in goal.steps {
            if let parsed = CoachGoal.parseDay(step.date) {
                let day = calendar.startOfDay(for: parsed)
                if day >= today { dated.append((step: step, day: day)) }
            } else {
                undated.append(step)
            }
        }
        dated.sort { $0.day < $1.day }
        if let first = dated.first, first.day == today { return (step: first.step, isToday: true) }
        if let first = undated.first { return (step: first, isToday: true) }
        if let first = dated.first { return (step: first.step, isToday: false) }
        return nil
    }

    /// Active goals with their assessment and today's step.
    static func items(goals: [CoachGoal], history: (String) -> [GoalAssessor.Point], now: Date = Date()) -> [GoalPlanItem] {
        goals.filter { $0.status == .active }.map { goal in
            let assessment = GoalAssessor.assess(
                exercise: goal.exerciseName, targetWeight: goal.targetWeight, targetReps: goal.targetReps,
                history: history(goal.exerciseName), now: now)
            let found = todayStep(of: goal, now: now)
            return GoalPlanItem(goal: goal, assessment: assessment, step: found?.step, stepIsToday: found?.isToday ?? false)
        }
    }

    /// Goals worth showing for this workout: the lift is in the baseline, or its muscle is trained today.
    /// With no baseline at all nothing can be ruled out, so every goal stays.
    static func relevant(_ items: [GoalPlanItem], lifts: [CoachLiftRef]) -> [GoalPlanItem] {
        guard !lifts.isEmpty else { return items }
        let muscles = Set(lifts.map { MuscleGroups.canonical(forExercise: $0.name, muscleGroup: $0.muscle) })
        return items.filter { item in
            lifts.contains { ExerciseNameResolver.isMatch($0.name, item.goal.exerciseName) }
                || muscles.contains(MuscleGroups.canonical(forExercise: item.goal.exerciseName, muscleGroup: ""))
        }
    }

    /// Rail allowances for goal attempts due today.
    static func allowances(_ items: [GoalPlanItem]) -> [GoalAllowance] {
        items.filter(\.attemptToday).map {
            GoalAllowance(name: $0.goal.exerciseName, weight: $0.goal.targetWeight, reps: $0.goal.targetReps)
        }
    }

    /// Active goals met by a logged set: weight and reps both at or above the target on a matching lift.
    static func achieved(goals: [CoachGoal], exercises: [Exercise], sets: [UUID: [WorkoutSet]]) -> [CoachGoal] {
        goals.filter { goal in
            guard goal.status == .active else { return false }
            return exercises.contains { exercise in
                ExerciseNameResolver.isMatch(exercise.name, goal.exerciseName)
                    && (sets[exercise.id] ?? []).contains { $0.weightLbs >= goal.targetWeight && $0.reps >= goal.targetReps }
            }
        }
    }

    /// "Goal hit: Bench Press 225x1."
    static func goalHitText(_ goals: [CoachGoal]) -> String {
        "Goal hit: " + goals.map { "\($0.exerciseName) \($0.targetText)" }.joined(separator: "; ") + "."
    }

    /// The overall read with "Goal hit: ..." appended for any achieved goal the model did not mention.
    static func read(_ read: String, withAchieved goals: [CoachGoal]) -> String {
        let lower = read.lowercased()
        let missing = goals.filter { !lower.contains("goal hit") && !lower.contains($0.targetText.lowercased()) }
        guard !missing.isEmpty else { return read }
        let base = read.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? goalHitText(missing) : base + " " + goalHitText(missing)
    }
}
