import Foundation
import simd

/// One authored 3D motion for every catalog exercise, plus name matching for free-typed exercises.
enum ExerciseMotionLibrary {

    static let all: [ExerciseGuideMotion] = {
        var out: [ExerciseGuideMotion] = []
        out.append(contentsOf: PressLibrary.all())
        out.append(contentsOf: PullLibrary.all())
        out.append(contentsOf: HingeLibrary.all())
        out.append(contentsOf: ArmLibrary.all())
        out.append(contentsOf: SquatLibrary.all())
        out.append(contentsOf: HipLegLibrary.all())
        out.append(contentsOf: CoreLibrary.all())
        out.append(contentsOf: CardioLibrary.all())
        return out
    }()

    private static let byLowercasedName: [String: ExerciseGuideMotion] = {
        Dictionary(all.map { ($0.exerciseName.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Exact catalog match, then the resolver / movement-profile based closest motion.
    /// nil only for names nothing sensible matches.
    static func motion(for exerciseName: String) -> ExerciseGuideMotion? {
        let typed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        if let exact = byLowercasedName[typed.lowercased()] { return exact }

        let stripped = ExerciseNameResolver.stripPerArm(typed).name
        if let exact = byLowercasedName[stripped.lowercased()] { return exact }

        // Whole-phrase aliases ("stair climber", "rdl", "ohp"...).
        let words = tokens(stripped)
        let joined = " " + words.joined(separator: " ") + " "
        for (phrase, target) in phraseAliases where joined.contains(" \(phrase) ") {
            if let hit = byLowercasedName[target.lowercased()] { return hit }
        }

        // Near-identical wording ("Seated Cable Rows", "Leg curl machine").
        let catalogNames = all.map(\.exerciseName)
        let queryEquipment = Set(words).intersection(equipmentWords)
        if let best = ExerciseNameResolver.suggestions(for: stripped, among: catalogNames).first,
           let hit = byLowercasedName[best.lowercased()],
           Set(tokens(hit.exerciseName)).intersection(equipmentWords).isSubset(of: queryEquipment) {
            return hit
        }

        // Closest motion of the same movement profile, scored on shared words and equipment.
        let profile = MovementProfileLibrary.profile(for: stripped)
        let specific = profile.id != "untracked" && profile.id != "generic"
        let candidates = specific ? all.filter { profileID(of: $0) == profile.id } : all
        var best: (ExerciseGuideMotion, Float)?
        for candidate in candidates {
            let score = similarityScore(queryWords: words, candidate: candidate)
            if best == nil || score > best!.1 { best = (candidate, score) }
        }
        guard let (winner, score) = best else { return nil }
        if specific { return winner }
        return score >= 1.0 ? winner : nil
    }

    // MARK: Matching helpers

    /// Movement profile of a library motion. Mostly the profile its name maps to, with the exceptions
    /// where the name alone would point at the wrong family.
    private static func profileID(of motion: ExerciseGuideMotion) -> String {
        if motion.exerciseName == "Cable Overhead Extension" { return "tricepsExtension" }
        return MovementProfileLibrary.profile(for: motion.exerciseName).id
    }

    /// How many motion names contain each word (rarer words say more about the exercise).
    private static let documentFrequency: [String: Int] = {
        var df: [String: Int] = [:]
        for m in all { for w in Set(tokens(m.exerciseName)) { df[w, default: 0] += 1 } }
        return df
    }()

    private static let phraseAliases: [(String, String)] = [
        ("stair climber", "Stairmaster"), ("stair master", "Stairmaster"), ("stair climb", "Stairmaster"),
        ("stepmill", "Stairmaster"), ("bike", "Cycling"), ("biking", "Cycling"), ("spin", "Cycling"),
        ("spinning", "Cycling"), ("stationary bike", "Cycling"), ("jogging", "Treadmill Run"),
        ("running", "Treadmill Run"), ("run", "Treadmill Run"), ("jog", "Treadmill Run"), ("treadmill", "Treadmill Run"),
        ("skipping", "Jump Rope"), ("skipping rope", "Jump Rope"), ("jump", "Jump Rope"),
        ("battle rope", "Battle Ropes"), ("cross trainer", "Elliptical"), ("crosstrainer", "Elliptical"),
        ("rowing", "Rowing Machine"), ("erg", "Rowing Machine"), ("row machine", "Rowing Machine"),
        ("ab roller", "Ab Wheel Rollout"), ("ab wheel", "Ab Wheel Rollout"), ("rollout", "Ab Wheel Rollout"),
        ("wood chop", "Woodchopper"), ("woodchop", "Woodchopper"), ("wood chopper", "Woodchopper"),
        ("rdl", "Romanian Deadlift"), ("ohp", "Overhead Press"), ("military press", "Overhead Press"),
        ("skullcrusher", "Skull Crusher"), ("skull crusher", "Skull Crusher"), ("pushup", "Push-Up"),
        ("push up", "Push-Up"), ("pullup", "Pull-Up"), ("pull up", "Pull-Up"), ("chinup", "Chin-Up"),
        ("chin up", "Chin-Up"), ("pulldown", "Lat Pulldown"), ("pull down", "Lat Pulldown"),
        ("hyper extension", "Hyperextension"), ("back extension", "Hyperextension"),
        ("glute bridge", "Glute Bridge"), ("hip thrust", "Hip Thrust"), ("nordic curl", "Nordic Hamstring Curl"),
        ("goblet squat", "Goblet Squat"), ("hack squat", "Hack Squat"), ("good morning", "Good Morning"),
        ("russian twist", "Russian Twist"), ("face pull", "Face Pull"), ("t bar row", "T-Bar Row"),
        ("tbar row", "T-Bar Row"), ("leg raise", "Hanging Leg Raise"), ("hanging leg raise", "Hanging Leg Raise")
    ]

    private static let equipmentWords: Set<String> = ["barbell", "dumbbell", "cable", "machine", "smith", "ez", "bodyweight"]

    private static func tokens(_ name: String) -> [String] {
        let abbreviations = ["db": "dumbbell", "dbs": "dumbbell", "bb": "barbell", "ez": "barbell", "tri": "tricep", "bi": "bicep"]
        var words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { word -> String in
                if let a = abbreviations[word] { return a }
                if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
                return word
            }
        // "over head" -> "overhead"
        var i = 0
        while i + 1 < words.count {
            if words[i] == "over", words[i + 1] == "head" {
                words.replaceSubrange(i...(i + 1), with: ["overhead"])
            }
            i += 1
        }
        return words.filter { !["bar", "the", "a", "of", "with", "on", "flat", "seated", "standing"].contains($0) }
    }

    private static func similarityScore(queryWords: [String], candidate: ExerciseGuideMotion) -> Float {
        let nameWords = tokens(candidate.exerciseName)
        let classification = ExerciseCatalog.exercises.first { $0.name == candidate.exerciseName }
        var score: Float = 0
        var matchedName = Set<String>()
        for q in queryWords {
            var best: Float = 0
            for n in nameWords {
                var w: Float = 0
                let rarity = 1 / Float(max(documentFrequency[n] ?? 1, 1))
                if q == n {
                    w = (equipmentWords.contains(q) ? 1.5 : 1.0) + rarity
                } else if q == "smith", n == "barbell" {
                    w = 1.5
                } else if q.count >= 3, n.hasPrefix(q) || (q.hasPrefix(n) && n.count >= 4) {
                    w = 0.8 + rarity * 0.5
                }
                if w > best { best = w; matchedName.insert(n) }
            }
            score += best
        }
        if let c = classification {
            if queryWords.contains(c.classification.lowercased()) && !nameWords.contains(c.classification.lowercased()) { score += 1.0 }
            for q in queryWords where tokens(c.primaryMuscle).contains(q) || tokens(c.muscleGroup).contains(q) { score += 0.5 }
        }
        score -= 0.1 * Float(nameWords.filter { !matchedName.contains($0) }.count)
        return score
    }
}
