import Foundation
import Supabase

/// Remote CRUD operations against Supabase.
/// Single responsibility: execute queries against the Supabase REST API.
/// Repositories coordinate between this and LocalStorageService.
final class SupabaseService {

    private let client: SupabaseClient

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
            .insert(workout.toSupabase())
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
            .insert(rows)
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
            .insert(workoutSet.toSupabase())
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
            .insert(plan)
            .execute()
    }

    func fetchActiveMonthPlan(userId: UUID) async throws -> MonthPlan? {
        let today = Date()
        let response: [MonthPlan] = try await client
            .from("month_plans")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("end_date", value: DateFormatter.dateOnly.string(from: today))
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return response.first
    }

    // MARK: - Planned Sessions

    func insertPlannedSessions(_ sessions: [PlannedSession]) async throws {
        try await client
            .from("planned_sessions")
            .insert(sessions)
            .execute()
    }

    func fetchPlannedSessions(monthPlanId: UUID) async throws -> [PlannedSession] {
        let response: [PlannedSession] = try await client
            .from("planned_sessions")
            .select()
            .eq("month_plan_id", value: monthPlanId.uuidString)
            .order("planned_date", ascending: true)
            .execute()
            .value
        return response
    }

    func updatePlannedSession(_ session: PlannedSession) async throws {
        try await client
            .from("planned_sessions")
            .update(session)
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

    // MARK: - Personal Records

    func insertPersonalRecord(_ record: PersonalRecord) async throws {
        try await client
            .from("personal_records")
            .insert(record)
            .execute()
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

    // MARK: - Rate Limit

    func checkRateLimit(userId: UUID) async throws -> Bool {
        struct RateLimitResult: Decodable {
            let allowed: Bool
        }
        let result: RateLimitResult = try await client
            .rpc("check_rate_limit", params: ["p_user_id": userId.uuidString])
            .execute()
            .value
        return result.allowed
    }
}
