import Foundation

/// Editable, string-backed copy of a logged workout. Pure value type: no storage access.
struct WorkoutEditDraft {
    struct DraftSet: Identifiable {
        let id: UUID
        var weight: String
        var reps: String
        var rir: String
        /// Source set for items that existed before editing; nil for added sets.
        var original: WorkoutSet?

        init(id: UUID = UUID(), weight: String = "", reps: String = "", rir: String = "",
             original: WorkoutSet? = nil) {
            self.original = original
            self.id = id
            self.weight = weight
            self.reps = reps
            self.rir = rir
        }
    }

    struct DraftExercise: Identifiable {
        let id: UUID
        var name: String
        var muscleGroup: String
        var sets: [DraftSet]
        /// Source exercise for items that existed before editing; nil for added exercises.
        var original: Exercise? = nil
    }

    enum Field { case weight, reps, rir }

    struct DraftFieldError: Equatable {
        let exerciseId: UUID
        let setId: UUID
        let field: Field
    }

    var name: String
    var date: Date
    var notes: String
    var exercises: [DraftExercise]

    init(workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]]) {
        name = workout.workoutType
        date = workout.date
        notes = workout.userNote ?? ""
        self.exercises = exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { ex in
                let draftSets = (sets[ex.id] ?? [])
                    .sorted { $0.setNumber < $1.setNumber }
                    .map { s in
                        DraftSet(
                            weight: s.weightLbs == 0 ? "BW" : String(format: "%g", s.weightLbs),
                            reps: String(s.reps),
                            rir: s.rir.map(String.init) ?? "",
                            original: s
                        )
                    }
                return DraftExercise(id: ex.id, name: ex.name, muscleGroup: ex.muscleGroup, sets: draftSets, original: ex)
            }
    }

    var isEmpty: Bool { !exercises.contains { !$0.sets.isEmpty } }

    // MARK: - Mutations

    mutating func addSet(to exerciseId: UUID) {
        guard let i = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        if let last = exercises[i].sets.last {
            exercises[i].sets.append(DraftSet(weight: last.weight, reps: last.reps, rir: last.rir))
        } else {
            exercises[i].sets.append(DraftSet())
        }
    }

    mutating func removeSet(exerciseId: UUID, setId: UUID) {
        guard let i = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        exercises[i].sets.removeAll { $0.id == setId }
    }

    mutating func addExercise(name: String, muscleGroup: String) {
        exercises.append(DraftExercise(id: UUID(), name: name, muscleGroup: muscleGroup, sets: [DraftSet()]))
    }

    mutating func removeExercise(_ exerciseId: UUID) {
        exercises.removeAll { $0.id == exerciseId }
    }

    // MARK: - Parsing

    private static func parseWeight(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.uppercased() == "BW" { return 0 }
        guard let v = Double(t), v.isFinite, v >= 0 else { return nil }
        return v
    }

    private static func parseReps(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Int(t), v >= 0 else { return nil }
        return v
    }

    /// Returns .some(nil) for blank (unknown), .some(n) for valid, nil for invalid.
    private static func parseRir(_ text: String) -> Int?? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .some(nil) }
        guard let v = Int(t), (0...10).contains(v) else { return nil }
        return .some(v)
    }

    // MARK: - Validation

    func validate() -> [DraftFieldError] {
        var errors: [DraftFieldError] = []
        for ex in exercises {
            for s in ex.sets {
                if Self.parseWeight(s.weight) == nil {
                    errors.append(DraftFieldError(exerciseId: ex.id, setId: s.id, field: .weight))
                }
                if Self.parseReps(s.reps) == nil {
                    errors.append(DraftFieldError(exerciseId: ex.id, setId: s.id, field: .reps))
                }
                if Self.parseRir(s.rir) == nil {
                    errors.append(DraftFieldError(exerciseId: ex.id, setId: s.id, field: .rir))
                }
            }
        }
        return errors
    }

    // MARK: - Build

    func build(for original: Workout) -> (workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]])? {
        guard validate().isEmpty else { return nil }

        var workout = original
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.workoutType = trimmedName.isEmpty ? "Workout" : trimmedName
        workout.date = date
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.userNote = trimmedNotes.isEmpty ? nil : trimmedNotes

        var builtExercises: [Exercise] = []
        var builtSets: [UUID: [WorkoutSet]] = [:]

        for ex in exercises where !ex.sets.isEmpty {
            let exercise = Exercise.create(
                workoutId: original.id,
                name: ex.name,
                muscleGroup: ex.muscleGroup,
                orderIndex: builtExercises.count,
                targetSets: ex.sets.count,
                targetReps: ex.original?.targetReps,
                targetRir: ex.original?.targetRir,
                restSeconds: ex.original?.restSeconds,
                coachNote: ex.original?.coachNote
            )
            var sets: [WorkoutSet] = []
            for (n, s) in ex.sets.enumerated() {
                guard let weight = Self.parseWeight(s.weight),
                      let reps = Self.parseReps(s.reps),
                      let rir = Self.parseRir(s.rir) else { return nil }
                var set = WorkoutSet.create(
                    exerciseId: exercise.id, setNumber: n + 1,
                    weightLbs: weight, reps: reps, rir: rir,
                    userFeedback: s.original?.userFeedback,
                    durationSeconds: s.original?.durationSeconds,
                    distanceMiles: s.original?.distanceMiles,
                    inclineLevel: s.original?.inclineLevel
                )
                set.recordedAt = date
                set.isPR = false
                sets.append(set)
            }
            builtExercises.append(exercise)
            builtSets[exercise.id] = sets
        }
        return (workout, builtExercises, builtSets)
    }
}
