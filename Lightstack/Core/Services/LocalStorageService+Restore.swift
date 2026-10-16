import Foundation
import CoreData

/// Bulk Core Data operations used by `SyncRestoreService`.
///
/// Everything here is local-only: restore applies cloud data without queueing a single
/// upload. Writes look rows up in batches by id (instead of one fetch per row) and are
/// upserts, so applying the same data twice changes nothing.
extension LocalStorageService {

    /// One restored workout: header, its exercises, and each exercise's sets.
    typealias RestoredWorkout = (workout: Workout, exercises: [(exercise: Exercise, sets: [WorkoutSet])])

    private static let lookupChunk = 300

    // MARK: - Lookups by id

    private func chunks(_ ids: [UUID]) -> [[UUID]] {
        stride(from: 0, to: ids.count, by: Self.lookupChunk).map {
            Array(ids[$0..<min($0 + Self.lookupChunk, ids.count)])
        }
    }

    func workoutEntities(ids: [UUID]) -> [UUID: CDWorkout] {
        var found: [UUID: CDWorkout] = [:]
        for chunk in chunks(ids) {
            let request: NSFetchRequest<CDWorkout> = CDWorkout.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", chunk)
            for entity in (try? context.fetch(request)) ?? [] {
                if let id = entity.id { found[id] = entity }
            }
        }
        return found
    }

    func exerciseEntities(ids: [UUID]) -> [UUID: CDExercise] {
        var found: [UUID: CDExercise] = [:]
        for chunk in chunks(ids) {
            let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", chunk)
            for entity in (try? context.fetch(request)) ?? [] {
                if let id = entity.id { found[id] = entity }
            }
        }
        return found
    }

    func setEntities(ids: [UUID]) -> [UUID: CDWorkoutSet] {
        var found: [UUID: CDWorkoutSet] = [:]
        for chunk in chunks(ids) {
            let request: NSFetchRequest<CDWorkoutSet> = CDWorkoutSet.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", chunk)
            for entity in (try? context.fetch(request)) ?? [] {
                if let id = entity.id { found[id] = entity }
            }
        }
        return found
    }

    /// Every workout of a user (any order).
    func fetchAllWorkouts(userId: UUID) -> [CDWorkout] {
        let request: NSFetchRequest<CDWorkout> = CDWorkout.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - Upserts

    /// Upserts workouts with their exercises and sets, by id, in one save.
    func restoreWorkouts(_ items: [RestoredWorkout]) {
        guard !items.isEmpty else { return }
        performBatch {
            let workouts = workoutEntities(ids: items.map(\.workout.id))
            let exerciseList = items.flatMap { $0.exercises.map(\.exercise) }
            let exercises = exerciseEntities(ids: exerciseList.map(\.id))
            let sets = setEntities(ids: items.flatMap { $0.exercises.flatMap { $0.sets.map(\.id) } })
            for item in items {
                let workoutEntity = workouts[item.workout.id] ?? CDWorkout(context: context)
                item.workout.applyToCoreData(workoutEntity)
                for pair in item.exercises {
                    let exerciseEntity = exercises[pair.exercise.id] ?? CDExercise(context: context)
                    pair.exercise.applyToCoreData(exerciseEntity)
                    exerciseEntity.workout = workoutEntity
                    for set in pair.sets {
                        let setEntity = sets[set.id] ?? CDWorkoutSet(context: context)
                        set.applyToCoreData(setEntity)
                        setEntity.exercise = exerciseEntity
                    }
                }
            }
        }
    }

    /// Upserts rest days. A day is one row per user, so a local row for the same day is
    /// updated in place (it adopts the cloud row's id) instead of creating a second one.
    func restoreRestDays(_ days: [RestDay]) {
        guard !days.isEmpty else { return }
        performBatch {
            for day in days {
                let start = day.date.startOfDay
                let sameDay = fetchRestDays(userId: day.userId, in: start...start)
                let entity = sameDay.first ?? CDRestDay(context: context)
                entity.id = day.id
                entity.userId = day.userId
                entity.date = start
                entity.createdAt = day.createdAt
                sameDay.dropFirst().forEach { context.delete($0) }
            }
        }
    }

    // MARK: - Deletes (tombstones)

    @discardableResult
    func deleteWorkouts(ids: Set<UUID>) -> Int {
        let found = workoutEntities(ids: Array(ids))
        found.values.forEach { context.delete($0) }
        save()
        return found.count
    }

    @discardableResult
    func deleteExercises(ids: Set<UUID>) -> Int {
        let found = exerciseEntities(ids: Array(ids))
        found.values.forEach { context.delete($0) }
        save()
        return found.count
    }

    @discardableResult
    func deleteSets(ids: Set<UUID>) -> Int {
        let found = setEntities(ids: Array(ids))
        found.values.forEach { context.delete($0) }
        save()
        return found.count
    }

    @discardableResult
    func deleteMonthPlans(ids: Set<UUID>) -> Int {
        var count = 0
        for id in ids {
            guard let entity = fetchMonthPlan(id: id) else { continue }
            context.delete(entity)
            count += 1
        }
        save()
        return count
    }

    @discardableResult
    func deletePlannedSessions(ids: Set<UUID>) -> Int {
        var count = 0
        for id in ids {
            let request: NSFetchRequest<CDPlannedSession> = CDPlannedSession.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = (try? context.fetch(request))?.first else { continue }
            context.delete(entity)
            count += 1
        }
        save()
        return count
    }

    /// Deletes local rest days by id; returns the days (start of day) that were removed.
    @discardableResult
    func deleteRestDays(ids: Set<UUID>, userId: UUID) -> [Date] {
        var days: [Date] = []
        for entity in fetchRestDays(userId: userId) {
            guard let id = entity.id, ids.contains(id) else { continue }
            if let date = entity.date { days.append(date.startOfDay) }
            context.delete(entity)
        }
        save()
        return days
    }
}
