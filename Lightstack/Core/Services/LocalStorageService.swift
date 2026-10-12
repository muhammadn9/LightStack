import Foundation
import CoreData
import os

/// Core Data CRUD operations.
/// Single responsibility: read/write entities to the local Core Data store.
/// Does not know about Supabase — that's SupabaseService's job.
final class LocalStorageService {

    let container: NSPersistentContainer
    private let logger = Logger(subsystem: "org.lightstack.app", category: "LocalStorageService")

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Lightstack")
        if let description = container.persistentStoreDescriptions.first {
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
            #if DEBUG
            if !inMemory && UITestMode.isActive {
                UITestMode.prepareStore()
                description.url = UITestMode.storeURL
            }
            #endif
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

    /// Every exercise the user has logged, most recent workout first (duplicates included).
    func fetchExerciseHistory(userId: UUID) -> [(name: String, muscleGroup: String)] {
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        request.predicate = NSPredicate(format: "workout.userId == %@", userId as CVarArg)
        request.sortDescriptors = [
            NSSortDescriptor(key: "workout.date", ascending: false),
            NSSortDescriptor(key: "orderIndex", ascending: true)
        ]
        let entities = (try? context.fetch(request)) ?? []
        return entities.map { ($0.name ?? "", $0.muscleGroup ?? "") }
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
            // Upsert by id: saving the same exercise twice must not duplicate it.
            let entity = fetchExerciseEntity(id: exercise.id) ?? CDExercise(context: context)
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

    /// How often one exercise name appears in the user's history.
    struct ExerciseNameStat: Equatable, Identifiable {
        let name: String
        let setCount: Int
        let workoutCount: Int
        var id: String { name }
    }

    /// Every distinct exercise name (exact spelling) with its set and workout counts,
    /// most-logged first.
    func fetchExerciseNameStats(userId: UUID) -> [ExerciseNameStat] {
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        request.predicate = NSPredicate(format: "workout.userId == %@", userId as CVarArg)
        let entities = (try? context.fetch(request)) ?? []
        var sets: [String: Int] = [:]
        var workouts: [String: Set<UUID>] = [:]
        for entity in entities {
            let name = (entity.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            sets[name, default: 0] += entity.sets?.count ?? 0
            if let id = entity.workout?.id { workouts[name, default: []].insert(id) }
        }
        return sets.keys.map {
            ExerciseNameStat(name: $0, setCount: sets[$0] ?? 0, workoutCount: workouts[$0]?.count ?? 0)
        }.sorted {
            if $0.setCount != $1.setCount { return $0.setCount > $1.setCount }
            if $0.workoutCount != $1.workoutCount { return $0.workoutCount > $1.workoutCount }
            return $0.name < $1.name
        }
    }

    /// Renames every historical exercise whose name is in `oldNames` to `newName`.
    /// Returns the ids of the exercises that actually changed (for syncing).
    @discardableResult
    func renameExercises(userId: UUID, from oldNames: [String], to newName: String) -> [UUID] {
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = oldNames.filter { $0 != target }
        guard !target.isEmpty, !sources.isEmpty else { return [] }
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        request.predicate = NSPredicate(
            format: "workout.userId == %@ AND name IN %@", userId as CVarArg, sources
        )
        let entities = (try? context.fetch(request)) ?? []
        var ids: [UUID] = []
        for entity in entities {
            entity.name = target
            if let id = entity.id { ids.append(id) }
        }
        save()
        return ids
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

        // Upsert by id: saving the same set twice must not duplicate it.
        let setRequest: NSFetchRequest<CDWorkoutSet> = CDWorkoutSet.fetchRequest()
        setRequest.predicate = NSPredicate(format: "id == %@", workoutSet.id as CVarArg)
        setRequest.fetchLimit = 1
        let entity = (try? context.fetch(setRequest).first) ?? CDWorkoutSet(context: context)
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

    func deleteSet(setId: UUID) {
        let request: NSFetchRequest<CDWorkoutSet> = CDWorkoutSet.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", setId as CVarArg)
        request.fetchLimit = 1
        guard let entity = try? context.fetch(request).first else { return }
        context.delete(entity)
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

    /// Distinct exercise names that have at least one set across a user's workouts.
    func fetchExerciseNamesWithSets(userId: UUID) -> Set<String> {
        let request: NSFetchRequest<CDWorkoutSet> = CDWorkoutSet.fetchRequest()
        request.predicate = NSPredicate(format: "exercise.workout.userId == %@", userId as CVarArg)
        let sets = (try? context.fetch(request)) ?? []
        return Set(sets.compactMap { $0.exercise?.name })
    }

    // MARK: - Streak

    /// Consecutive days ending today or yesterday where each day has a workout OR a rest day.
    func countConsecutiveWorkoutDays(userId: UUID) -> Int {
        let request: NSFetchRequest<CDWorkout> = CDWorkout.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        let workouts = (try? context.fetch(request)) ?? []
        let restDays = fetchRestDays(userId: userId)

        let calendar = Calendar.current
        var days = Set<Date>()
        for w in workouts {
            if let d = w.date { days.insert(calendar.startOfDay(for: d)) }
        }
        for r in restDays {
            if let d = r.date { days.insert(calendar.startOfDay(for: d)) }
        }
        return Self.streak(days: days, now: Date(), calendar: calendar)
    }

    /// Streak over a set of active days (start-of-day dates). The most recent day
    /// must be today or yesterday.
    static func streak(days: Set<Date>, now: Date, calendar: Calendar) -> Int {
        let sorted = days.map { calendar.startOfDay(for: $0) }.sorted(by: >)
        guard let mostRecent = sorted.first else { return 0 }
        let today = calendar.startOfDay(for: now)
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

    // MARK: - Rest days
    // Local-only for now: rest days are not synced to Supabase.

    /// Rest days for a user, optionally limited to an inclusive start-of-day range.
    func fetchRestDays(userId: UUID, in range: ClosedRange<Date>? = nil) -> [CDRestDay] {
        let request: NSFetchRequest<CDRestDay> = CDRestDay.fetchRequest()
        if let range {
            request.predicate = NSPredicate(
                format: "userId == %@ AND date >= %@ AND date <= %@",
                userId as CVarArg, range.lowerBound.startOfDay as CVarArg, range.upperBound.startOfDay as CVarArg
            )
        } else {
            request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func isRestDay(userId: UUID, date: Date) -> Bool {
        let day = date.startOfDay
        return !fetchRestDays(userId: userId, in: day...day).isEmpty
    }

    /// Marks a day as a rest day. Idempotent per day.
    func addRestDay(userId: UUID, date: Date) {
        let day = date.startOfDay
        guard fetchRestDays(userId: userId, in: day...day).isEmpty else { return }
        let entity = CDRestDay(context: context)
        entity.id = UUID()
        entity.userId = userId
        entity.date = day
        entity.createdAt = Date()
        save()
    }

    func removeRestDay(userId: UUID, date: Date) {
        let day = date.startOfDay
        let found = fetchRestDays(userId: userId, in: day...day)
        guard !found.isEmpty else { return }
        found.forEach { context.delete($0) }
        save()
    }

    // MARK: - Private

    private func fetchExerciseEntity(id: UUID) -> CDExercise? {
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// One-off repair for copies created before saves were upserts: merges
    /// exercises (and sets) that share an id, keeping one of each.
    /// Returns the number of duplicate exercises removed.
    @discardableResult
    func removeDuplicateExercises() -> Int {
        let request: NSFetchRequest<CDExercise> = CDExercise.fetchRequest()
        guard let all = try? context.fetch(request) else { return 0 }
        var keeperById: [UUID: CDExercise] = [:]
        var removed = 0
        for entity in all {
            guard let id = entity.id else { continue }
            guard let keeper = keeperById[id] else {
                keeperById[id] = entity
                continue
            }
            let keptSetIds = Set((keeper.sets as? Set<CDWorkoutSet> ?? []).compactMap(\.id))
            for set in entity.sets as? Set<CDWorkoutSet> ?? [] {
                if let setId = set.id, keptSetIds.contains(setId) {
                    context.delete(set)
                } else {
                    set.exercise = keeper
                }
            }
            context.delete(entity)
            removed += 1
        }
        if removed > 0 { save() }
        return removed
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Core Data save error: \(error.localizedDescription)")
        }
    }
}
