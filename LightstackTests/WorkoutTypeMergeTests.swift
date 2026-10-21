import XCTest
@testable import Lightstack

final class WorkoutTypeResolverTests: XCTestCase {

    func testGroupsSpellingVariantsAndKeepsPullSeparate() {
        let names = ["Push", "push", "Push Day", " push  ", "Pull"]
        let groups = WorkoutTypeResolver.duplicateGroups(among: names)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first, ["Push", "push", "Push Day", " push  "])
    }

    func testLegsAndLegDayShareAKey() {
        XCTAssertEqual(WorkoutTypeResolver.duplicateGroups(among: ["Legs", "Leg Day", "Pull"]).first, ["Legs", "Leg Day"])
    }

    func testDistinctNamesFormNoGroups() {
        XCTAssertTrue(WorkoutTypeResolver.duplicateGroups(among: ["Push", "Pull", "Legs"]).isEmpty)
    }
}

@MainActor
final class WorkoutTypeMergeServiceTests: XCTestCase {

    private var stack: OutboxTestStack!
    private var profileRepo: ProfileRepository!
    private var service: WorkoutTypeMergeService!
    private var userId: UUID { stack.userId }

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
        profileRepo = ProfileRepository(
            localStorage: stack.storage,
            supabaseService: SupabaseServiceFactory.unreachable(),
            offlineQueueManager: stack.queue
        )
        service = WorkoutTypeMergeService(
            localStorage: stack.storage, offlineQueueManager: stack.queue, profileRepository: profileRepo
        )
    }

    private func seedWorkout(_ type: String) -> Workout {
        let w = Workout.create(userId: userId, workoutType: type, energyLevel: nil, timeAvailableMinutes: nil)
        stack.storage.saveWorkout(w)
        stack.remote.seedWorkout(w)
        return w
    }

    private func seedSummary(_ type: String, sessions: Int, text: String, age: TimeInterval = 0) {
        let s = AIContextSummary(id: UUID(), userId: userId, workoutType: type, summaryText: text,
                                 sessionsCovered: sessions, lastUpdated: Date().addingTimeInterval(-age))
        stack.storage.saveContextSummary(s)
        stack.remote.seedSummary(s)
    }

    private func queuedTypes() async -> [QueuedOperationType] {
        await stack.queue.waitForSubmissions()
        return await stack.queue.queuedOperations().map(\.type)
    }

    func testWorkoutsAndPlannedSessionsRenamedLocallyAndQueued() async {
        let push = seedWorkout("Push"), lower = seedWorkout("push"), day = seedWorkout("Push Day"), legs = seedWorkout("Legs")
        let plan = MonthPlan.create(userId: userId, title: "P", targetGoal: nil, startDate: Date(),
                                    endDate: Date().addingTimeInterval(86_400), aiOverview: nil)
        stack.storage.saveMonthPlan(plan)
        let planned = PlannedSession.create(monthPlanId: plan.id, userId: userId, plannedDate: Date(),
                                            workoutType: "push", focusNote: nil, isRestDay: false)
        stack.storage.savePlannedSessions([planned], monthPlanId: plan.id)

        let changed = service.merge(userId: userId, names: ["Push", "push", "Push Day"], keep: "Push")
        XCTAssertEqual(changed, 3)   // two workouts + one planned session

        for id in [push.id, lower.id, day.id] {
            XCTAssertEqual(stack.storage.fetchWorkout(id: id)?.workoutType, "Push")
        }
        XCTAssertEqual(stack.storage.fetchWorkout(id: legs.id)?.workoutType, "Legs")
        XCTAssertEqual(stack.storage.fetchPlannedSessions(monthPlanId: plan.id).first?.workoutType, "Push")

        let types = await queuedTypes()
        XCTAssertEqual(types.filter { $0 == .updateWorkout }.count, 2)
        XCTAssertEqual(types.filter { $0 == .updatePlannedSession }.count, 1)
        XCTAssertTrue(stack.remote.calls.isEmpty, "nothing may reach the remote before a flush")

        await stack.flushAll()
        XCTAssertEqual(stack.remote.workouts[lower.id]?.workoutType, "Push")
        XCTAssertEqual(stack.remote.workouts[day.id]?.workoutType, "Push")
        XCTAssertEqual(stack.remote.plannedSessions[planned.id]?.workoutType, "Push")
    }

    func testSummaryWithMoreSessionsWinsAndOldTypesAreDeletedRemotely() async {
        seedSummary("Push", sessions: 2, text: "short")
        seedSummary("push", sessions: 7, text: "long history", age: 100)
        seedSummary("Push Day", sessions: 4, text: "mid")
        _ = seedWorkout("Push"); _ = seedWorkout("push"); _ = seedWorkout("Push Day")

        service.merge(userId: userId, names: ["Push", "push", "Push Day"], keep: "Push")

        let left = stack.storage.fetchAllContextSummaries(userId: userId)
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.workoutType, "Push")
        XCTAssertEqual(left.first?.sessionsCovered, 7)
        XCTAssertEqual(left.first?.summaryText, "long history")

        let types = await queuedTypes()
        XCTAssertEqual(types.filter { $0 == .upsertContextSummary }.count, 1)
        XCTAssertEqual(types.filter { $0 == .deleteContextSummaries }.count, 1)
        XCTAssertTrue(stack.remote.calls.isEmpty)

        await stack.flushAll()
        XCTAssertEqual(stack.remote.summaryDeletes.count, 1)
        XCTAssertEqual(Set(stack.remote.summaryDeletes.first ?? []), ["push", "Push Day"])
        let remoteRows = stack.remote.summaries.values.filter { $0.userId == userId }
        XCTAssertEqual(remoteRows.map(\.workoutType), ["Push"])
        XCTAssertEqual(remoteRows.first?.sessionsCovered, 7)
        // The delete runs after the upsert in the same flush.
        let calls = stack.remote.calls
        let upsert = calls.firstIndex { $0.hasPrefix("upsertContextSummary") }
        let delete = calls.firstIndex { $0.hasPrefix("deleteContextSummaries") }
        XCTAssertNotNil(upsert); XCTAssertNotNil(delete)
        if let upsert, let delete { XCTAssertLessThan(upsert, delete) }
    }

    func testPendingUpsertForMergedAwayTypeIsDropped() async {
        _ = seedWorkout("Push"); _ = seedWorkout("push")
        let stale = AIContextSummary.create(userId: userId, workoutType: "push", summaryText: "x", sessionsCovered: 1)
        stack.queue.submit(.upsertContextSummary, payload: stale, recordKey: "\(userId.uuidString)|push")
        await stack.queue.waitForSubmissions()

        service.merge(userId: userId, names: ["Push", "push"], keep: "Push")
        await stack.flushAll()

        XCTAssertFalse(stack.remote.summaries.values.contains { $0.workoutType == "push" })
        XCTAssertEqual(stack.remote.summaryDeletes.count, 1)
    }

    func testSplitDaysUpdatedAndDeduped() {
        profileRepo.saveProfile(UserProfile.create(
            userId: userId, displayName: "T", age: 30, heightInches: 70, weightLbs: 180, trainingAgeMonths: 24,
            primaryGoals: ["Strength"], splitDays: ["Push Day", "Pull", "push", "Legs"], avoidExercises: [],
            equipment: [:], customEquipment: nil, notesToCoach: nil
        ))
        _ = seedWorkout("Push Day"); _ = seedWorkout("Push")

        service.merge(userId: userId, names: ["Push Day", "Push", "push"], keep: "Push")
        XCTAssertEqual(profileRepo.fetchProfileSync(userId: userId)?.splitDays, ["Push", "Pull", "Legs"])
    }

    func testSplitDaysUntouchedWhenNothingChanges() async {
        profileRepo.saveProfile(UserProfile.create(
            userId: userId, displayName: "T", age: 30, heightInches: 70, weightLbs: 180, trainingAgeMonths: 24,
            primaryGoals: ["Strength"], splitDays: ["Pull", "Legs"], avoidExercises: [],
            equipment: [:], customEquipment: nil, notesToCoach: nil
        ))
        await stack.queue.waitForSubmissions()
        let before = await stack.queue.queuedOperations().filter { $0.type == .upsertProfile }.first?.sequence
        _ = seedWorkout("Push"); _ = seedWorkout("push")
        service.merge(userId: userId, names: ["Push", "push"], keep: "Push")
        let after = await queuedTypes()
        XCTAssertEqual(after.filter { $0 == .upsertProfile }.count, 1)
        let afterSeq = await stack.queue.queuedOperations().filter { $0.type == .upsertProfile }.first?.sequence
        XCTAssertEqual(before, afterSeq)
    }

    func testHistoryAvailableTypesDedupesAndShowsMostCommonSpelling() {
        func w(_ t: String) -> Workout { Workout.create(userId: userId, workoutType: t, energyLevel: nil, timeAvailableMinutes: nil) }
        let types = HistoryViewModel.availableTypes(in: [w("push"), w("Push"), w("Push"), w(" Legs "), w("legs")])
        XCTAssertEqual(types, ["Legs", "Push"])
    }

    func testFetchContextSummaryIsCaseInsensitivePreferringExact() {
        seedSummary("push", sessions: 1, text: "lower")
        XCTAssertEqual(stack.storage.fetchContextSummary(userId: userId, workoutType: " Push ")?.summaryText, "lower")
        seedSummary("Push", sessions: 2, text: "exact")
        XCTAssertEqual(stack.storage.fetchContextSummary(userId: userId, workoutType: "Push")?.summaryText, "exact")
    }
}
