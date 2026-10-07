import Foundation

/// Maps an exercise name to the equipment it uses.
///
/// Rules, in order, on the lowercased name (punctuation becomes spaces):
/// 1. "smith" -> machine.
/// 2. cable, pulldown / pull down, pushdown / push down, face pull -> cable
///    (checked before barbell so "cable ez bar pushdown" is a cable lift).
/// 3. machine, leg press / extension / curl, pec deck, adductor / abductor,
///    hack squat -> machine.
/// 4. kettlebell, kb -> kettlebell.
/// 5. dumbbell, dumbell, db(s) -> dumbbells.
/// 6. barbell, bb, ez bar, trap bar, t bar -> barbell.
/// 7. pull-up, chin-up, push-up, dip, plank, crunch, sit-up, lunge, burpee,
///    bulgarian split squat, hyperextension, leg raise -> bodyweight.
/// 8. Otherwise the catalog classification (Barbell, Dumbbell, Cable, Machine,
///    Bodyweight; Cardio is ignored), looked up by exact name when not supplied.
/// 9. Otherwise a few implement-less classics (bench press, overhead press,
///    deadlift, squat) are barbell lifts. Anything else is unknown and excluded.
///
/// Bench is equipment used together with the primary kind. It is added when the
/// name has bench, incline, decline, preacher, skull crusher, step-up, bulgarian,
/// hip thrust or lying. So "Incline Smith Machine Press" is {machine, bench} and
/// "Bulgarian split squats" is {bodyweight, bench}.
enum EquipmentClassifier {

    static func kinds(forName name: String, catalogClassification: String? = nil) -> Set<EquipmentKind> {
        var result = Set<EquipmentKind>()
        if let primary = primaryKind(forName: name, catalogClassification: catalogClassification) {
            result.insert(primary)
        }
        if usesBench(name) { result.insert(.bench) }
        return result
    }

    static func primaryKind(forName name: String, catalogClassification: String? = nil) -> EquipmentKind? {
        let n = normalize(name)
        if has(n, "smith") { return .machine }
        if has(n, "cable", "pulldown", "pull down", "pushdown", "push down", "face pull") { return .cable }
        if has(n, "machine", "leg press", "leg extension", "leg curl", "pec deck",
               "adductor", "abductor", "hack squat") { return .machine }
        if hasWord(n, "kb") || has(n, "kettlebell") { return .kettlebell }
        if hasWord(n, "db") || hasWord(n, "dbs") || has(n, "dumbbell", "dumbell") { return .dumbbells }
        if hasWord(n, "bb") || has(n, "barbell", "ez bar", "trap bar", " t bar") { return .barbell }
        if has(n, "pull up", "pullup", "chin up", "chinup", "push up", "pushup", "plank", "crunch",
               "sit up", "situp", "lunge", "burpee", "bulgarian", "hyperextension", "leg raise",
               "mountain climber") || hasWord(n, "dip") || hasWord(n, "dips") {
            return .bodyweight
        }
        let catalog = catalogClassification
            ?? ExerciseCatalog.exercises.first { normalize($0.name) == n }?.classification
        if let kind = kind(fromClassification: catalog) { return kind }
        if has(n, "bench press", "overhead press", "military press", "deadlift", "squat") { return .barbell }
        return nil
    }

    static func usesBench(_ name: String) -> Bool {
        has(normalize(name), "bench", "incline", "decline", "preacher", "skull", "step up",
            "stepup", "bulgarian", "hip thrust", "lying")
    }

    static func kind(fromClassification value: String?) -> EquipmentKind? {
        switch value?.lowercased() {
        case "barbell": return .barbell
        case "dumbbell", "dumbbells": return .dumbbells
        case "kettlebell": return .kettlebell
        case "cable": return .cable
        case "machine": return .machine
        case "bodyweight": return .bodyweight
        default: return nil
        }
    }

    // MARK: - Matching

    private static func normalize(_ name: String) -> String {
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return " " + words.joined(separator: " ") + " "
    }

    private static func has(_ normalized: String, _ needles: String...) -> Bool {
        needles.contains { normalized.contains($0) }
    }

    private static func hasWord(_ normalized: String, _ word: String) -> Bool {
        normalized.contains(" \(word) ")
    }
}
