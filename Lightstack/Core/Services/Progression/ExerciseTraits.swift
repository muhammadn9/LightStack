import Foundation

/// Name-based facts about an exercise: its class, plate/stack step and default rep range.
enum ExerciseTraits {

    private static let isolationWords = [
        "fly", "flye", "raise", "curl", "extension", "kickback", "pushdown", "push down",
        "crunch", "calf", "shrug", "face pull", "pullover", "pec deck", "abduction", "adduction",
        "wrist", "tricep", "bicep"
    ]
    private static let heavyWords = [
        "bench", "squat", "deadlift", "overhead press", "shoulder press", "military", "ohp",
        "row", "pulldown", "pull down", "pull-down", "rdl", "romanian", "leg press",
        "hip thrust", "chest press", "incline press", "decline press", "hack", "good morning"
    ]
    private static let compoundWords = ["dip", "pull up", "pull-up", "pullup", "chin", "lunge", "press", "push up", "push-up"]

    static func classify(_ name: String) -> ExerciseClass {
        let n = name.lowercased()
        if isolationWords.contains(where: { n.contains($0) }) { return .isolation }
        if heavyWords.contains(where: { n.contains($0) }) { return .heavyCompound }
        if compoundWords.contains(where: { n.contains($0) }) { return .compound }
        return .isolation
    }

    /// Rounding step for weights: 2.5 for dumbbells and cables, 5 for barbell/Smith/machine.
    static func roundingStep(_ name: String) -> Double {
        let n = name.lowercased()
        let isDumbbell = n.contains("dumbbell") || n.contains("dumbell")
            || n.split(whereSeparator: { !$0.isLetter }).contains { $0 == "db" || $0 == "dbs" }
        if isDumbbell { return 2.5 }
        if n.contains("machine") || n.contains("smith") || n.contains("barbell") || n.contains("leg press") { return 5 }
        if n.contains("cable") { return 2.5 }
        if n.contains("raise") || n.contains("curl") || n.contains("fly") || n.contains("flye") { return 2.5 }
        return 5
    }

    /// Smallest sensible load increase: the rounding step (2.5 per dumbbell/cable, 5 otherwise).
    static func increment(_ name: String) -> Double { roundingStep(name) }

    static func round(_ value: Double, step: Double) -> Double {
        guard value > 0 else { return step }
        return max(step, (value / step).rounded() * step)
    }

    static func floorStep(_ value: Double, step: Double) -> Double {
        max(step, (value / step).rounded(.down) * step)
    }

    static func defaultRange(for cls: ExerciseClass) -> RepRange {
        switch cls {
        case .heavyCompound: return RepRange(lower: 5, upper: 8)
        case .compound: return RepRange(lower: 6, upper: 10)
        case .isolation: return RepRange(lower: 8, upper: 12)
        }
    }

    // MARK: - Muscles

    private struct MuscleRule {
        let keywords: [String]
        let primary: [String]
        let secondary: [String]
    }

    /// Ordered keyword table: the first rule that matches wins, so specific names come before generic ones.
    private static let muscleRules: [MuscleRule] = [
        MuscleRule(keywords: ["rear delt", "reverse fly", "reverse flye", "rear fly", "face pull"],
                   primary: ["rear delts"], secondary: ["mid back"]),
        MuscleRule(keywords: ["lateral raise", "side raise", "side delt", "upright row"],
                   primary: ["side delts"], secondary: ["traps"]),
        MuscleRule(keywords: ["front raise"], primary: ["front delts"], secondary: []),
        MuscleRule(keywords: ["tricep", "pushdown", "push down", "skull", "overhead extension", "close grip bench", "close-grip bench", "jm press"],
                   primary: ["triceps"], secondary: []),
        MuscleRule(keywords: ["leg extension"], primary: ["quads"], secondary: []),
        MuscleRule(keywords: ["leg curl", "hamstring curl", "nordic"], primary: ["hamstrings"], secondary: []),
        MuscleRule(keywords: ["wrist curl", "forearm", "farmer"], primary: ["forearms"], secondary: []),
        MuscleRule(keywords: ["bicep", "curl"], primary: ["biceps"], secondary: ["forearms"]),
        MuscleRule(keywords: ["calf", "calves"], primary: ["calves"], secondary: []),
        MuscleRule(keywords: ["hip thrust", "glute", "abduction"], primary: ["glutes"], secondary: ["hamstrings"]),
        MuscleRule(keywords: ["adduction"], primary: ["adductors"], secondary: []),
        MuscleRule(keywords: ["back extension", "hyperextension", "hyper extension"],
                   primary: ["lower back"], secondary: ["glutes", "hamstrings"]),
        MuscleRule(keywords: ["rdl", "romanian", "stiff leg", "stiff-leg", "good morning", "deadlift"],
                   primary: ["hamstrings", "glutes"], secondary: ["lower back"]),
        MuscleRule(keywords: ["squat", "leg press", "lunge", "step up", "step-up", "sissy"],
                   primary: ["quads"], secondary: ["glutes"]),
        MuscleRule(keywords: ["pullover"], primary: ["lats"], secondary: ["chest"]),
        MuscleRule(keywords: ["pulldown", "pull down", "pull-down", "pull up", "pull-up", "pullup", "chin up", "chin-up", "chinup"],
                   primary: ["lats"], secondary: ["biceps"]),
        MuscleRule(keywords: ["row"], primary: ["mid back", "lats"], secondary: ["rear delts", "biceps"]),
        MuscleRule(keywords: ["shrug"], primary: ["traps"], secondary: []),
        MuscleRule(keywords: ["crunch", "sit-up", "sit up", "situp", "plank", "leg raise", "ab wheel", "woodchop"],
                   primary: ["core"], secondary: []),
        MuscleRule(keywords: ["decline", "dip"], primary: ["lower chest"], secondary: ["triceps"]),
        MuscleRule(keywords: ["incline fly", "incline flye"], primary: ["upper chest"], secondary: []),
        MuscleRule(keywords: ["incline"], primary: ["upper chest"], secondary: ["front delts", "triceps"]),
        MuscleRule(keywords: ["fly", "flye", "pec deck", "crossover", "cable cross"], primary: ["chest"], secondary: []),
        MuscleRule(keywords: ["overhead press", "shoulder press", "military", "ohp", "arnold", "push press"],
                   primary: ["front delts"], secondary: ["triceps"]),
        MuscleRule(keywords: ["chest press", "bench", "push up", "push-up", "pushup", "press"],
                   primary: ["mid chest"], secondary: ["front delts", "triceps"])
    ]

    /// Sub-muscles an exercise works, from its name; falls back to the canonical muscle group.
    /// Short keywords ("row", "dip", "fly", "ohp", "rdl") must match a whole word so "narrow" is not a row.
    static func muscles(forExercise name: String, muscleGroup: String) -> (primary: [String], secondary: [String]) {
        let n = name.lowercased()
        let words = n.split(whereSeparator: { !$0.isLetter }).map(String.init)
        func matches(_ keyword: String) -> Bool {
            if keyword.count <= 3 { return words.contains(keyword) || words.contains(keyword + "s") }
            return n.contains(keyword)
        }
        if let rule = muscleRules.first(where: { $0.keywords.contains(where: matches) }) {
            return (rule.primary, rule.secondary)
        }
        return ([MuscleGroups.canonical(forExercise: name, muscleGroup: muscleGroup)], [])
    }
}
