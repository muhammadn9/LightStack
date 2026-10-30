import Foundation
import Supabase

/// Remote CRUD operations against Supabase.
/// Single responsibility: execute queries against the Supabase REST API.
/// Repositories coordinate between this and LocalStorageService.
final class SupabaseService {

    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Profile

    func fetchProfile(userId: UUID) async throws -> UserProfile? {
        let response: [UserProfile] = try await client
            .from("profiles")
            .select()
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return response.first
    }

    func upsertProfile(_ profile: UserProfile) async throws {
        try await client
            .from("profiles")
            .upsert(profile, onConflict: "user_id")
            .execute()
    }

    // MARK: - Workouts

    func insertWorkout(_ workout: Workout) async throws {
        try await client
            .from("workouts")
            .upsert(workout.toSupabase(), onConflict: "id")
            .execute()
    }

    func updateWorkout(_ workout: Workout) async throws {
        try await client
            .from("workouts")
            .update(workout.toSupabase())
            .eq("id", value: workout.id.uuidString)
            .execute()
    }

    func deleteWorkout(workoutId: UUID) async throws {
        try await client
            .from("workouts")
            .delete()
            .eq("id", value: workoutId.uuidString)
            .execute()
        // Postgres cascade delete will automatically remove related exercises and sets
    }

    func deleteSet(setId: UUID) async throws {
        try await client
            .from("sets")
            .delete()
            .eq("id", value: setId.uuidString)
            .execute()
    }

    func deleteExercise(id: UUID) async throws {
        try await client
            .from("exercises")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
        // Postgres cascade delete will automatically remove the exercise's sets
    }

    func fetchWorkoutsForUser(userId: UUID, limit: Int) async throws -> [Workout] {
        let response: [Workout] = try await client
            .from("workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .limit(limit)
            .execute()
            .value
        return response
    }

    // MARK: - Exercises

    func insertExercises(_ exercises: [Exercise]) async throws {
        let rows = exercises.map { $0.toSupabase() }
        try await client
            .from("exercises")
            .upsert(rows, onConflict: "id")
            .execute()
    }

    /// Sets `exercises.name` for the given rows (used when merging duplicate exercise names).
    func updateExerciseNames(ids: [UUID], name: String) async throws {
        let chunkSize = 50
        var start = 0
        while start < ids.count {
            let chunk = ids[start..<min(start + chunkSize, ids.count)].map(\.uuidString)
            try await client
                .from("exercises")
                .update(["name": name])
                .in("id", values: chunk)
                .execute()
            start += chunkSize
        }
    }

    func deleteExercises(workoutId: UUID) async throws {
        try await client
            .from("exercises")
            .delete()
            .eq("workout_id", value: workoutId.uuidString)
            .execute()
    }

    func fetchExercises(workoutId: UUID) async throws -> [Exercise] {
        let response: [Exercise] = try await client
            .from("exercises")
            .select()
            .eq("workout_id", value: workoutId.uuidString)
            .order("order_index", ascending: true)
            .execute()
            .value
        return response
    }

    // MARK: - Sets

    func insertSet(_ workoutSet: WorkoutSet) async throws {
        try await client
            .from("sets")
            .upsert(workoutSet.toSupabase(), onConflict: "id")
            .execute()
    }

    func fetchSets(exerciseId: UUID) async throws -> [WorkoutSet] {
        let response: [WorkoutSet] = try await client
            .from("sets")
            .select()
            .eq("exercise_id", value: exerciseId.uuidString)
            .order("set_number", ascending: true)
            .execute()
            .value
        return response
    }

    // MARK: - Streak

    func fetchCurrentStreak(userId: UUID) async throws -> Int {
        struct StreakResult: Decodable {
            let currentStreak: Int

            enum CodingKeys: String, CodingKey {
                case currentStreak = "current_streak"
            }
        }
        let response: [StreakResult] = try await client
            .from("user_streaks")
            .select()
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return response.first?.currentStreak ?? 0
    }

    // MARK: - Month Plans

    func insertMonthPlan(_ plan: MonthPlan) async throws {
        try await client
            .from("month_plans")
            .upsert(plan.toSupabase(), onConflict: "id")
            .execute()
    }

    func deleteMonthPlan(planId: UUID) async throws {
        try await client
            .from("month_plans")
            .delete()
            .eq("id", value: planId.uuidString)
            .execute()
        // Postgres cascade delete removes the plan's planned sessions
    }

    func fetchActiveMonthPlan(userId: UUID) async throws -> MonthPlan? {
        let today = Date()
        // start_date/end_date are DATE columns: decode through the lenient wrapper.
        let response: [RemoteMonthPlan] = try await client
            .from("month_plans")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("end_date", value: RemoteDate.dayString(today))
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return response.first?.plan
    }

    // MARK: - Planned Sessions

    func insertPlannedSessions(_ sessions: [PlannedSession]) async throws {
        try await client
            .from("planned_sessions")
            .upsert(sessions.map { $0.toSupabase() }, onConflict: "id")
            .execute()
    }

    func fetchPlannedSessions(monthPlanId: UUID) async throws -> [PlannedSession] {
        let response: [RemotePlannedSession] = try await client
            .from("planned_sessions")
            .select()
            .eq("month_plan_id", value: monthPlanId.uuidString)
            .order("planned_date", ascending: true)
            .execute()
            .value
        return response.map(\.session)
    }

    func updatePlannedSession(_ session: PlannedSession) async throws {
        try await client
            .from("planned_sessions")
            .update(session.toSupabase())
            .eq("id", value: session.id.uuidString)
            .execute()
    }

    // MARK: - AI Context Summaries

    func upsertContextSummary(_ summary: AIContextSummary) async throws {
        try await client
            .from("ai_context_summaries")
            .upsert(summary, onConflict: "user_id,workout_type")
            .execute()
    }

    func deleteContextSummaries(userId: UUID, workoutTypes: [String]) async throws {
        guard !workoutTypes.isEmpty else { return }
        try await client
            .from("ai_context_summaries")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .in("workout_type", values: workoutTypes)
            .execute()
    }

    func fetchContextSummary(userId: UUID, workoutType: String) async throws -> AIContextSummary? {
        let response: [AIContextSummary] = try await client
            .from("ai_context_summaries")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("workout_type", value: workoutType)
            .limit(1)
            .execute()
            .value
        return response.first
    }

    // MARK: - Rest Days

    func upsertRestDay(_ restDay: RestDay) async throws {
        try await client
            .from("rest_days")
            .upsert(restDay.toSupabase(), onConflict: "user_id,date")
            .execute()
    }

    /// Deleted by (user, day), not id: the same day may carry another id on another device.
    func deleteRestDay(userId: UUID, date: Date) async throws {
        try await client
            .from("rest_days")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("date", value: RestDay.dayString(date))
            .execute()
    }

    // MARK: - Nutrition
    // Rows are written through `cloudRow()`, which always sends every column (nil as null).

    func upsertNutritionTarget(_ target: NutritionTarget) async throws {
        try await client.from("nutrition_targets").upsert(target.cloudRow()).execute()
    }

    func deleteNutritionTarget(id: UUID) async throws {
        try await client.from("nutrition_targets").delete().eq("id", value: id.uuidString).execute()
    }

    func upsertFood(_ food: NutritionFood) async throws {
        try await client.from("foods").upsert(food.cloudRow()).execute()
    }

    func deleteFood(id: UUID) async throws {
        try await client.from("foods").delete().eq("id", value: id.uuidString).execute()
    }

    func upsertFoodEntry(_ entry: FoodEntry) async throws {
        try await client.from("food_entries").upsert(entry.cloudRow()).execute()
    }

    func deleteFoodEntry(id: UUID) async throws {
        try await client.from("food_entries").delete().eq("id", value: id.uuidString).execute()
    }

    func upsertMealSlot(_ slot: MealSlot) async throws {
        try await client.from("meal_slots").upsert(slot.cloudRow()).execute()
    }

    func upsertWaterEntry(_ entry: WaterEntry) async throws {
        try await client.from("water_entries").upsert(entry.cloudRow()).execute()
    }

    func deleteWaterEntry(id: UUID) async throws {
        try await client.from("water_entries").delete().eq("id", value: id.uuidString).execute()
    }

    func upsertDayNote(_ note: DayNote) async throws {
        try await client.from("day_notes").upsert(note.cloudRow()).execute()
    }

    // MARK: - Tombstones

    /// Records that these rows were deleted on this device, so other devices
    /// (and a restore) do not resurrect them. Duplicates are ignored.
    func insertTombstones(userId: UUID, entity: String, recordIds: [UUID], deletedAt: Date) async throws {
        guard !recordIds.isEmpty else { return }
        let rows = recordIds.map {
            SupabaseTombstone(userId: userId, entity: entity, recordId: $0, deletedAt: deletedAt)
        }
        try await client
            .from("sync_tombstones")
            .upsert(rows, onConflict: "user_id,entity,record_id", ignoreDuplicates: true)
            .execute()
    }

    // MARK: - Personal Records

    func insertPersonalRecord(_ record: PersonalRecord) async throws {
        try await client
            .from("personal_records")
            .upsert(record.toSupabase(), onConflict: "id")
            .execute()
    }

    /// Removes the cloud PR rows of one exercise (except `keepId`) created on or before the cutoff.
    func deletePersonalRecords(userId: UUID, exerciseName: String, keepId: UUID?, createdOnOrBefore: Date) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var query = client
            .from("personal_records")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("exercise_name", value: exerciseName)
            .lte("created_at", value: formatter.string(from: createdOnOrBefore))
        if let keepId { query = query.neq("id", value: keepId.uuidString) }
        try await query.execute()
    }

    func fetchPersonalRecords(userId: UUID) async throws -> [PersonalRecord] {
        let response: [PersonalRecord] = try await client
            .from("personal_records")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date_achieved", ascending: false)
            .execute()
            .value
        return response
    }

}

/// Row of the `sync_tombstones` table.
struct SupabaseTombstone: Encodable {
    let userId: UUID
    let entity: String
    let recordId: UUID
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case entity
        case recordId = "record_id"
        case deletedAt = "deleted_at"
    }
}
