import Foundation

/// A coach-chat request the app can fulfil without calling the AI.
struct LocalChatCommand {
    let modifications: [WorkoutModification]
    /// One short line shown as the coach's reply.
    let reply: String
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
