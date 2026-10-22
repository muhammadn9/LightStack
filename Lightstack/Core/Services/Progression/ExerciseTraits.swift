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
}
