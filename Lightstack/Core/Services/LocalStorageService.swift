import Foundation
import CoreData
import os

/// Core Data CRUD operations.
/// Single responsibility: read/write entities to the local Core Data store.
/// Does not know about Supabase — that's SupabaseService's job.
final class LocalStorageService {

    let container: NSPersistentContainer
    private let logger = Logger(subsystem: "org.lightstack.app", category: "LocalStorageService")

    init() {
        container = NSPersistentContainer(name: "Lightstack")
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var context: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Profile

    func fetchProfile(userId: UUID) -> CDUserProfile? {
        let request: NSFetchRequest<CDUserProfile> = CDUserProfile.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func saveProfile(_ profile: UserProfile) {
        logger.debug("Saving profile with split days: \(profile.splitDays)")
        let existing = fetchProfile(userId: profile.userId)
        let entity = existing ?? CDUserProfile(context: context)
        profile.applyToCoreData(entity)
        logger.debug("After applyToCoreData, entity.splitDays: \(entity.splitDays ?? [])")
        save()
    }

    // MARK: - Workout

    func fetchWorkout(id: UUID) -> CDWorkout? {
        let request: NSFetchRequest<CDWorkout> = CDWorkout.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchWorkoutsForDate(userId: UUID, date: Date) -> [CDWorkout] {
        let start = date.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let request: NSFetchRequest<CDWorkout> = CDWorkout.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND date >= %@ AND date < %@",
            userId as CVarArg, start as CVarArg, end as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchRecentWorkouts(userId: UUID, limit: Int) -> [CDWorkout] {
        let request: NSFetchRequest<CDWorkout> = CDWorkout.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }

    func saveWorkout(_ workout: Workout) {
        let entity = CDWorkout(context: context)
        workout.applyToCoreData(entity)
        save()
    }

    func updateWorkout(_ workout: Workout) {
        guard let entity = fetchWorkout(id: workout.id) else { return }
        workout.applyToCoreData(entity)
        save()
    }

    func deleteWorkout(workoutId: UUID) {
        guard let entity = fetchWorkout(id: workoutId) else { return }
        context.delete(entity)
        // Core Data cascade delete rules will automatically delete related exercises and sets
        save()
    }

    // MARK: - Exercise

    func fetchExercises(workoutId: UUID) -> [CDExercise] {
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        request.predicate = NSPredicate(format: "workout.id == %@", workoutId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func saveExercises(_ exercises: [Exercise], workoutId: UUID) {
        guard let workoutEntity = fetchWorkout(id: workoutId) else { return }
        for exercise in exercises {
            let entity = CDExercise(context: context)
            exercise.applyToCoreData(entity)
            entity.workout = workoutEntity
        }
        save()
    }

    func deleteExercise(exerciseId: UUID) {
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", exerciseId as CVarArg)
        guard let entity = (try? context.fetch(request))?.first else { return }
        context.delete(entity)
        save()
    }

    func deleteExercises(workoutId: UUID) {
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        request.predicate = NSPredicate(format: "workout.id == %@", workoutId as CVarArg)
        let entities = (try? context.fetch(request)) ?? []
        entities.forEach { context.delete($0) }
        save()
    }

    // MARK: - Set

    func fetchSets(exerciseId: UUID) -> [CDWorkoutSet] {
        let request: NSFetchRequest<CDWorkoutSet> = CDWorkoutSet.fetchRequest()
        request.predicate = NSPredicate(format: "exercise.id == %@", exerciseId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "setNumber", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func saveSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", exerciseId as CVarArg)
        request.fetchLimit = 1
        guard let exerciseEntity = try? context.fetch(request).first else { return }

        let entity = CDWorkoutSet(context: context)
        workoutSet.applyToCoreData(entity)
        entity.exercise = exerciseEntity
        save()
    }

    func updateSet(_ workoutSet: WorkoutSet) {
        let request: NSFetchRequest<CDWorkoutSet> = CDWorkoutSet.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", workoutSet.id as CVarArg)
        request.fetchLimit = 1
        guard let entity = try? context.fetch(request).first else { return }
        workoutSet.applyToCoreData(entity)
        save()
    }

    // MARK: - Month Plan

    func fetchMonthPlan(id: UUID) -> CDMonthPlan? {
        let request: NSFetchRequest<CDMonthPlan> = CDMonthPlan.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchActiveMonthPlan(userId: UUID) -> CDMonthPlan? {
        let today = Calendar.current.startOfDay(for: Date())
        let request: NSFetchRequest<CDMonthPlan> = CDMonthPlan.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND endDate >= %@",
            userId as CVarArg, today as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchActiveMonthPlans(userId: UUID) -> [CDMonthPlan] {
        let today = Calendar.current.startOfDay(for: Date())
        let request: NSFetchRequest<CDMonthPlan> = CDMonthPlan.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND endDate >= %@",
            userId as CVarArg, today as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 5
        return (try? context.fetch(request)) ?? []
    }

    func deleteMonthPlan(id: UUID) {
        guard let entity = fetchMonthPlan(id: id) else { return }
        context.delete(entity)
        save()
    }

    func saveMonthPlan(_ plan: MonthPlan) {
        let existing = fetchMonthPlan(id: plan.id)
        let entity = existing ?? CDMonthPlan(context: context)
        plan.applyToCoreData(entity)
        save()
    }

    // MARK: - Planned Session

    func fetchPlannedSessions(monthPlanId: UUID) -> [CDPlannedSession] {
        let request: NSFetchRequest<CDPlannedSession> = CDPlannedSession.fetchRequest()
        request.predicate = NSPredicate(format: "monthPlan.id == %@", monthPlanId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "plannedDate", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func savePlannedSessions(_ sessions: [PlannedSession], monthPlanId: UUID) {
        guard let planEntity = fetchMonthPlan(id: monthPlanId) else { return }
        for session in sessions {
            let entity = CDPlannedSession(context: context)
            session.applyToCoreData(entity)
            entity.monthPlan = planEntity
        }
        save()
    }

    func updatePlannedSession(_ session: PlannedSession) {
        let request: NSFetchRequest<CDPlannedSession> = CDPlannedSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", session.id as CVarArg)
        request.fetchLimit = 1
        guard let entity = try? context.fetch(request).first else { return }
        session.applyToCoreData(entity)
        save()
    }

    // MARK: - AI Context Summary

    func fetchContextSummary(userId: UUID, workoutType: String) -> CDAIContextSummary? {
        let request: NSFetchRequest<CDAIContextSummary> = CDAIContextSummary.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND workoutType == %@",
            userId as CVarArg, workoutType
        )
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func saveContextSummary(_ summary: AIContextSummary) {
        let existing = fetchContextSummary(userId: summary.userId, workoutType: summary.workoutType)
        let entity = existing ?? CDAIContextSummary(context: context)
        summary.applyToCoreData(entity)
        save()
    }

    // MARK: - Personal Records

    func fetchPersonalRecords(userId: UUID) -> [CDPersonalRecord] {
        let request: NSFetchRequest<CDPersonalRecord> = CDPersonalRecord.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "dateAchieved", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchPersonalRecord(userId: UUID, exerciseName: String) -> CDPersonalRecord? {
        let request: NSFetchRequest<CDPersonalRecord> = CDPersonalRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND exerciseName == %@",
            userId as CVarArg, exerciseName
        )
        request.sortDescriptors = [NSSortDescriptor(key: "weightLbs", ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func savePersonalRecord(_ record: PersonalRecord) {
        let entity = CDPersonalRecord(context: context)
        record.applyToCoreData(entity)
        save()
    }

    func deletePersonalRecord(userId: UUID, exerciseName: String) {
        let request: NSFetchRequest<CDPersonalRecord> = CDPersonalRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND exerciseName == %@",
            userId as CVarArg, exerciseName
        )
        if let entities = try? context.fetch(request) {
            entities.forEach { context.delete($0) }
            save()
        }
    }

    /// Returns all sets for a given exercise name across all workouts for a user,
    /// used to recalculate PRs after a workout is deleted.
    func fetchAllSetsForExerciseName(userId: UUID, exerciseName: String) -> [CDWorkoutSet] {
        let request: NSFetchRequest<CDWorkoutSet> = CDWorkoutSet.fetchRequest()
        request.predicate = NSPredicate(
            format: "exercise.name == %@ AND exercise.workout.userId == %@",
            exerciseName, userId as CVarArg
        )
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - Streak

    func countConsecutiveWorkoutDays(userId: UUID) -> Int {
        let request: NSFetchRequest<CDWorkout> = CDWorkout.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        guard let workouts = try? context.fetch(request), !workouts.isEmpty else {
            return 0
        }

        let calendar = Calendar.current
        var dates = Set<Date>()
        for w in workouts {
            if let d = w.date {
                dates.insert(calendar.startOfDay(for: d))
            }
        }

        let sorted = dates.sorted(by: >)
        guard let mostRecent = sorted.first else { return 0 }

        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        guard mostRecent >= yesterday else { return 0 }

        var streak = 0
        var checkDate = mostRecent
        for date in sorted {
            if date == checkDate {
                streak += 1
                guard let next = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = next
            } else if date < checkDate {
                break
            }
        }

        return streak
    }

    // MARK: - Private

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Core Data save error: \(error.localizedDescription)")
        }
    }
}
