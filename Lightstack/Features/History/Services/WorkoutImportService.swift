import Foundation

struct ImportPreview: Equatable {
    let toImport: [ImportedWorkout]
    let duplicateCount: Int
    let skipped: [ImportSkipReason]
}

/// Turns parsed import results into saved workouts.
final class WorkoutImportService {

    private let workoutRepository: WorkoutRepository
    private let prRepository: PRRepository
    private let userId: UUID

    init(workoutRepository: WorkoutRepository, prRepository: PRRepository, userId: UUID) {
        self.workoutRepository = workoutRepository
        self.prRepository = prRepository
        self.userId = userId
    }

    // MARK: - Dedupe

    /// A workout is a duplicate when an existing (or earlier incoming) workout falls on the
    /// same calendar day with the same trimmed, case-insensitive name. First one wins.
    static func dedupe(
        _ incoming: [ImportedWorkout],
        existing: [(date: Date, name: String)]
    ) -> (toImport: [ImportedWorkout], duplicates: Int) {
        let calendar = Calendar.current
        func key(_ date: Date, _ name: String) -> String {
            let day = calendar.startOfDay(for: date).timeIntervalSince1970
            return "\(day)|\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }
        var seen = Set(existing.map { key($0.date, $0.name) })
        var toImport: [ImportedWorkout] = []
        var duplicates = 0
        for workout in incoming {
            if seen.insert(key(workout.date, workout.name)).inserted {
                toImport.append(workout)
            } else {
                duplicates += 1
            }
        }
        return (toImport, duplicates)
    }

    // MARK: - Preview

    func preview(_ result: WorkoutImportParseResult) -> ImportPreview {
        let existing = workoutRepository
            .fetchRecentWorkouts(userId: userId, limit: 10_000)
            .map { (date: $0.date, name: $0.workoutType) }
        let deduped = Self.dedupe(result.workouts, existing: existing)
        return ImportPreview(toImport: deduped.toImport, duplicateCount: deduped.duplicates, skipped: result.skipped)
    }

    // MARK: - Superset grouping

    /// Assigns one fresh group id per superset label within a workout. Members are pulled
    /// adjacent to the first member; groups are capped at 4 (extra members stay ungrouped)
    /// and labels with a single member are ignored.
    static func assignGroups(_ exercises: [ImportedExercise]) -> [(exercise: ImportedExercise, groupId: UUID?)] {
        func key(_ e: ImportedExercise) -> String? {
            guard let l = e.supersetLabel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !l.isEmpty else { return nil }
            return l
        }
        var members: [String: [Int]] = [:]
        for (i, e) in exercises.enumerated() { if let k = key(e) { members[k, default: []].append(i) } }
        var groupIds: [String: UUID] = [:]
        var result: [(exercise: ImportedExercise, groupId: UUID?)] = []
        var placed = Set<Int>()
        for (i, e) in exercises.enumerated() where !placed.contains(i) {
            guard let k = key(e), let idxs = members[k], idxs.count >= SupersetGroup.minMembers else {
                result.append((e, nil))
                placed.insert(i)
                continue
            }
            let gid = groupIds[k] ?? UUID()
            groupIds[k] = gid
            for (n, idx) in idxs.enumerated() {
                result.append((exercises[idx], n < SupersetGroup.maxMembers ? gid : nil))
                placed.insert(idx)
            }
        }
        return result
    }

    // MARK: - Import

    func importWorkouts(_ workouts: [ImportedWorkout]) {
        var exerciseNames = Set<String>()
        for imported in workouts {
            let workout = Workout(
                id: UUID(), userId: userId, localId: UUID().uuidString,
                date: imported.date, workoutType: imported.name,
                durationMinutes: nil, energyLevel: nil, timeAvailableMinutes: nil,
                userNote: imported.notes, setupNote: nil, aiProgressionNote: nil,
                plannedSessionId: nil, syncStatus: .pending, createdAt: Date()
            )
            var exercises: [Exercise] = []
            var setsByExercise: [UUID: [WorkoutSet]] = [:]
            for (index, assigned) in Self.assignGroups(imported.exercises).enumerated() {
                let ie = assigned.exercise
                let exercise = Exercise.create(
                    workoutId: workout.id, name: ie.name, muscleGroup: ie.muscleGroup,
                    orderIndex: index, targetSets: ie.sets.count,
                    targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: ie.notes,
                    supersetGroupId: assigned.groupId
                )
                exercises.append(exercise)
                setsByExercise[exercise.id] = ie.sets.enumerated().map { offset, s in
                    WorkoutSet(
                        id: UUID(), exerciseId: exercise.id, localId: UUID().uuidString,
                        setNumber: offset + 1, weightLbs: s.weightLbs, reps: s.reps, rir: s.rir,
                        userFeedback: nil, isPR: false, syncStatus: .pending,
                        recordedAt: imported.date
                    )
                }
                exerciseNames.insert(ie.name)
            }
            workoutRepository.importWorkout(workout, exercises: exercises, sets: setsByExercise)
        }
        for name in exerciseNames {
            prRepository.recalculatePR(userId: userId, exerciseName: name)
        }
    }
}
