import Foundation

/// A coach-chat request the app can fulfil without calling the AI.
struct LocalChatCommand {
    let modifications: [WorkoutModification]
    /// One short line shown as the coach's reply.
    let reply: String
}

/// A lift target found in chat, e.g. 225 x 1 on the bench press.
struct GoalIntent: Equatable {
    let exerciseName: String
    let weight: Double
    let reps: Int
}

/// Recognises a few unambiguous chat commands ("remove X", "add a set to X",
/// "swap X with Y", "rest 90 sec on X") and turns them into the same
/// `WorkoutModification`s the AI path produces, so they reuse the confirmation sheet.
/// Anything not clearly matched returns nil and goes to the AI as before.
enum LocalChatCommandParser {

    /// - Parameters:
    ///   - exercises: the current workout's exercises.
    ///   - knownNames: exercise names the athlete could swap in (history + catalog).
    static func parse(_ rawText: String, exercises: [Exercise], knownNames: [String]) -> LocalChatCommand? {
        let text = normalize(rawText)
        guard !text.isEmpty, !exercises.isEmpty else { return nil }

        return parseRemove(text, exercises)
            ?? parseAddSets(text, exercises)
            ?? parseSwap(text, exercises, knownNames)
            ?? parseRest(text, exercises)
    }

    // MARK: - Commands

    private static func parseRemove(_ text: String, _ exercises: [Exercise]) -> LocalChatCommand? {
        guard let g = match(#"^(?:remove|delete|drop|skip|get rid of)\s+(.+)$"#, text),
              let exercise = resolve(g[1], in: exercises) else { return nil }
        return LocalChatCommand(modifications: [.removeExercise(name: exercise.name)],
                                reply: "Removing \(exercise.name).")
    }

    private static func parseAddSets(_ text: String, _ exercises: [Exercise]) -> LocalChatCommand? {
        guard let g = match(#"^add\s+(a|an|one|two|three|\d+)\s+(?:more\s+|extra\s+|another\s+)?sets?\s+(?:to|on|for)\s+(.+)$"#, text),
              let count = number(g[1]), (1...5).contains(count),
              let exercise = resolve(g[2], in: exercises),
              let current = exercise.targetSets else { return nil }
        let mod = WorkoutModification.modifyExercise(
            name: exercise.name, newTargetSets: current + count, newTargetReps: nil, newTargetRir: nil,
            newRest: nil, newTargetWeight: nil, note: nil
        )
        let noun = count == 1 ? "a set" : "\(count) sets"
        return LocalChatCommand(modifications: [mod], reply: "Adding \(noun) to \(exercise.name).")
    }

    private static func parseSwap(_ text: String, _ exercises: [Exercise], _ knownNames: [String]) -> LocalChatCommand? {
        guard let g = match(#"^(?:swap|replace|switch|change)\s+(.+?)\s+(?:with|for|to|by)\s+(.+)$"#, text),
              let old = resolve(g[1], in: exercises),
              let newName = resolveKnown(g[2], in: knownNames),
              newName.lowercased() != old.name.lowercased() else { return nil }
        let group = ExerciseCatalog.exercises.first { $0.name.lowercased() == newName.lowercased() }?.muscleGroup
            ?? old.muscleGroup
        let mod = WorkoutModification.replaceExercise(
            oldName: old.name, newName: newName, muscleGroup: group,
            targetSets: old.targetSets ?? 3, targetReps: old.targetReps, targetRir: old.targetRir,
            restSeconds: old.restSeconds, targetWeight: nil, note: nil
        )
        return LocalChatCommand(modifications: [mod], reply: "Swapping \(old.name) for \(newName).")
    }

    private static func parseRest(_ text: String, _ exercises: [Exercise]) -> LocalChatCommand? {
        let unit = #"(min|mins|minutes?|m|sec|secs|seconds?|s)?"#
        var seconds: Int?
        var target: String?
        if let g = match(#"^rest\s+(\d+(?:\.\d+)?)\s*"# + unit + #"\s+(?:on|for|after)\s+(.+)$"#, text) {
            seconds = restSeconds(value: g[1], unit: g[2]); target = g[3]
        } else if let g = match(#"^set\s+(?:the\s+)?rest(?:\s+time|\s+timer)?\s+(?:to|at)\s+(\d+(?:\.\d+)?)\s*"# + unit + #"(?:\s+(?:on|for)\s+(.+))?$"#, text) {
            seconds = restSeconds(value: g[1], unit: g[2]); target = g.count > 3 && !g[3].isEmpty ? g[3] : nil
        }
        guard let seconds else { return nil }

        let label = seconds % 60 == 0 && seconds >= 60 ? "\(seconds / 60) min" : "\(seconds)s"
        if let target {
            guard let exercise = resolve(target, in: exercises) else { return nil }
            return LocalChatCommand(modifications: [rest(exercise.name, seconds)],
                                    reply: "Setting rest to \(label) on \(exercise.name).")
        }
        return LocalChatCommand(modifications: exercises.map { rest($0.name, seconds) },
                                reply: "Setting rest to \(label) for every exercise.")
    }

    // MARK: - Lift goals

    /// A lift target the athlete asked about: "225x1 bench", "hit 225 on bench", "how do I get to 225 bench".
    /// Reps default to 1. The lift is matched against `knownNames` (history names win over the catalog).
    /// nil when no lift can be resolved, so ordinary chat is never mistaken for a goal.
    static func parseGoal(_ rawText: String, knownNames: [String], preferredNames: [String] = []) -> GoalIntent? {
        var text = normalize(rawText).trimmingCharacters(in: CharacterSet(charactersIn: "?.! "))
        for prefix in ["i want to ", "i wanna ", "my goal is to ", "my goal is ", "new goal: ", "goal: ",
                       "set a goal to ", "i need to ", "can i ", "could i "] {
            while text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        guard !text.isEmpty else { return nil }

        let num: String = #"(\d+(?:\.\d+)?)"#
        let lbs: String = #"(?:\s*(?:lbs?|pounds?))?"#
        let repsPart: String = #"(?:\s*(?:x|×)\s*(\d+))?"#
        let on: String = #"(?:(?:on|for|in|at)\s+)?(?:my\s+|the\s+)?"#
        let verbs: String = #"^(?:hit|get to|get|reach|lift|do|pr|go to|max out at)\s+"#
        let howTo: String = #"^how\s+(?:do|can|should|would)\s+i\s+(?:get|go|work|build|train)\s+(?:up\s+)?to\s+"#
        let howMy: String = #"^how\s+(?:do|can|should)\s+i\s+(?:get|take|bring|raise|increase)\s+my\s+(.+?)\s+(?:up\s+)?to\s+"#
        let sets: String = #"\s*(?:x|×|by)\s*(\d+)\s+"#
        let gap: String = #"\s+"#
        let tail: String = "(.+)$"

        let patternX: String = ["^", num, sets, on, tail].joined()
        let patternVerb: String = [verbs, num, lbs, repsPart, gap, on, tail].joined()
        let patternHow: String = [howTo, num, lbs, repsPart, gap, on, tail].joined()
        let patternMy: String = [howMy, num, lbs, repsPart, "$"].joined()

        var weight: String?
        var reps = ""
        var phrase: String?
        if let g = match(patternX, text) {
            weight = g[1]; reps = g[2]; phrase = g[3]
        } else if let g = match(patternVerb, text) {
            weight = g[1]; reps = g[2]; phrase = g[3]
        } else if let g = match(patternHow, text) {
            weight = g[1]; reps = g[2]; phrase = g[3]
        } else if let g = match(patternMy, text) {
            phrase = g[1]; weight = g[2]; reps = g[3]
        }
        guard let weightText = weight, let value = Double(weightText), (10...1500).contains(value),
              let rawPhrase = phrase else { return nil }
        let repCount = Int(reps) ?? 1
        guard (1...20).contains(repCount) else { return nil }

        // "bench press by december" / "bench this week": drop the timing words.
        var lift = rawPhrase
        if let range = lift.range(of: #"\s+(?:by|before|this|next|within|in|today|tomorrow|soon)\b.*$"#, options: .regularExpression) {
            lift.removeSubrange(range)
        }
        lift = stripArticle(lift)
        guard isPlainName(lift),
              let name = resolveGoalLift(lift, known: knownNames, preferred: preferredNames) else { return nil }
        return GoalIntent(exerciseName: name, weight: value, reps: repCount)
    }

    /// The known lift the phrase most plausibly names: exact name, else names holding every word
    /// (logged lifts first, then barbell, then the shortest), else `ExerciseNameResolver`'s suggestion.
    private static func resolveGoalLift(_ phrase: String, known: [String], preferred: [String]) -> String? {
        let wanted = phrase.lowercased().trimmingCharacters(in: .whitespaces)
        var seen = Set<String>()
        let pool = (preferred + known).filter { seen.insert($0.lowercased()).inserted }
        if let exact = pool.first(where: { $0.lowercased() == wanted }) { return exact }

        func words(_ text: String) -> [String] {
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        func singular(_ word: String) -> String {
            word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
        }
        let wantedWords = words(wanted)
        guard !wantedWords.isEmpty else { return nil }
        let preferredKeys = Set(preferred.map { $0.lowercased() })

        for attempt in [wantedWords, wantedWords.map(singular)] {
            let holding = pool.filter { name in
                let have = Set(words(name).flatMap { [$0, singular($0)] })
                return attempt.allSatisfy { have.contains($0) }
            }
            let ranked = holding.sorted { a, b in
                let ap = preferredKeys.contains(a.lowercased()), bp = preferredKeys.contains(b.lowercased())
                if ap != bp { return ap }
                let ab = a.lowercased().contains("barbell"), bb = b.lowercased().contains("barbell")
                if ab != bb { return ab }
                if a.count != b.count { return a.count < b.count }
                return a < b
            }
            if let best = ranked.first { return best }
        }
        return ExerciseNameResolver.suggestions(for: phrase, among: pool).first
    }

    // MARK: - Helpers

    private static func rest(_ name: String, _ seconds: Int) -> WorkoutModification {
        .modifyExercise(name: name, newTargetSets: nil, newTargetReps: nil, newTargetRir: nil,
                        newRest: seconds, newTargetWeight: nil, note: nil)
    }

    private static func restSeconds(value: String, unit: String) -> Int? {
        guard let n = Double(value), n > 0 else { return nil }
        let u = unit.lowercased()
        let seconds: Double
        if u.hasPrefix("m") { seconds = n * 60 }
        else if u.hasPrefix("s") { seconds = n }
        else { seconds = n <= 10 ? n * 60 : n }   // "rest 2 on X" = minutes, "rest 90 on X" = seconds
        let rounded = Int(seconds.rounded())
        return (15...600).contains(rounded) ? rounded : nil
    }

    private static func number(_ word: String) -> Int? {
        switch word {
        case "a", "an", "one": return 1
        case "two": return 2
        case "three": return 3
        default: return Int(word)
        }
    }

    /// Lowercased, politeness and trailing context removed.
    private static func normalize(_ raw: String) -> String {
        var t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        for prefix in ["please ", "can you ", "could you ", "can we ", "let's ", "lets ", "i want to ", "i'd like to ", "i would like to ", "go ahead and "] {
            while t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        }
        for suffix in [" please", " from the workout", " from my workout", " from today", " from this workout", " today"] {
            if t.hasSuffix(suffix) { t = String(t.dropLast(suffix.count)) }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Words that mean the user is asking for something more specific than the command.
    private static let blockers = [" set ", " sets ", " rep", " weight", " and ", " then ", ",", "?", " but ", " except ", " if "]

    /// The one current-workout exercise the phrase clearly names, else nil.
    private static func resolve(_ phrase: String, in exercises: [Exercise]) -> Exercise? {
        let name = stripArticle(phrase)
        guard isPlainName(name),
              let index = TodayViewModel.exerciseIndex(named: name, in: exercises) else { return nil }
        return exercises[index]
    }

    /// An exact name, else the single known name containing the phrase.
    private static func resolveKnown(_ phrase: String, in names: [String]) -> String? {
        let wanted = stripArticle(phrase)
        guard isPlainName(wanted) else { return nil }
        if let exact = names.first(where: { $0.lowercased() == wanted }) { return exact }
        let unique = Array(Set(names.filter { $0.lowercased().contains(wanted) }))
        return unique.count == 1 ? unique[0] : nil
    }

    private static func isPlainName(_ name: String) -> Bool {
        guard name.count >= 3 else { return false }
        let padded = " \(name) "
        return !blockers.contains { padded.contains($0) }
    }

    private static func stripArticle(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        for article in ["the ", "my ", "a "] where t.hasPrefix(article) { t = String(t.dropFirst(article.count)) }
        return t
    }

    /// Capture groups (index 0 = whole match); nil when the pattern doesn't match.
    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
