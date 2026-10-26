import Foundation

/// The remote reads a restore needs. `SupabaseService` conforms; tests and UI tests
/// supply a fake. Reads never write anything.
protocol RemoteReading: Sendable {
    func fetchProfile(userId: UUID) async throws -> UserProfile?
    /// One page of the user's workouts (newest first) with exercises and sets embedded.
    func fetchWorkoutHistoryPage(userId: UUID, offset: Int, limit: Int) async throws -> [RemoteWorkoutRecord]
    func fetchContextSummaries(userId: UUID) async throws -> [AIContextSummary]
    func fetchActiveMonthPlan(userId: UUID) async throws -> MonthPlan?
    func fetchPlannedSessions(monthPlanId: UUID) async throws -> [PlannedSession]
    func fetchRestDays(userId: UUID) async throws -> [RestDay]
    /// Every tombstone for the user. Deliberately not "since a cursor": a tombstone keeps the
    /// device's deletion time, and a device that was offline uploads it days later.
    func fetchTombstones(userId: UUID) async throws -> [RemoteTombstone]
    func fetchNutritionTargets(userId: UUID) async throws -> [NutritionTarget]
    func fetchFoods(userId: UUID) async throws -> [NutritionFood]
    /// One page of diary entries (newest day first).
    func fetchFoodEntriesPage(userId: UUID, offset: Int, limit: Int) async throws -> [FoodEntry]
}

/// Nutrition reads default to "nothing in the cloud" so fakes that predate nutrition keep compiling.
extension RemoteReading {
    func fetchNutritionTargets(userId: UUID) async throws -> [NutritionTarget] { [] }
    func fetchFoods(userId: UUID) async throws -> [NutritionFood] { [] }
    func fetchFoodEntriesPage(userId: UUID, offset: Int, limit: Int) async throws -> [FoodEntry] { [] }
}

extension SupabaseService: RemoteReading {

    private static let readPageSize = 1000

    func fetchWorkoutHistoryPage(userId: UUID, offset: Int, limit: Int) async throws -> [RemoteWorkoutRecord] {
        // One embedded select: workouts -> exercises -> sets (FKs are declared in the schema).
        try await client
            .from("workouts")
            .select("*, exercises(*, sets(*))")
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .order("id", ascending: true)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
    }

    func fetchContextSummaries(userId: UUID) async throws -> [AIContextSummary] {
        try await client
            .from("ai_context_summaries")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
    }

    func fetchRestDays(userId: UUID) async throws -> [RestDay] {
        var all: [RestDay] = []
        var offset = 0
        while true {
            let page: [RestDay] = try await client
                .from("rest_days")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("date", ascending: false)
                .range(from: offset, to: offset + Self.readPageSize - 1)
                .execute()
                .value
            all.append(contentsOf: page)
            if page.count < Self.readPageSize { return all }
            offset += page.count
        }
    }

    func fetchTombstones(userId: UUID) async throws -> [RemoteTombstone] {
        var all: [RemoteTombstone] = []
        var offset = 0
        while true {
            let page: [RemoteTombstone] = try await client
                .from("sync_tombstones")
                .select("entity, record_id, deleted_at")
                .eq("user_id", value: userId.uuidString)
                .order("entity", ascending: true)
                .order("record_id", ascending: true)
                .range(from: offset, to: offset + Self.readPageSize - 1)
                .execute()
                .value
            all.append(contentsOf: page)
            if page.count < Self.readPageSize { return all }
            offset += page.count
        }
    }

    func fetchNutritionTargets(userId: UUID) async throws -> [NutritionTarget] {
        var all: [NutritionTarget] = []
        var offset = 0
        while true {
            let page: [NutritionTarget] = try await client
                .from("nutrition_targets")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("effective_date", ascending: false)
                .order("id", ascending: true)
                .range(from: offset, to: offset + Self.readPageSize - 1)
                .execute()
                .value
            all.append(contentsOf: page)
            if page.count < Self.readPageSize { return all }
            offset += page.count
        }
    }

    func fetchFoods(userId: UUID) async throws -> [NutritionFood] {
        var all: [NutritionFood] = []
        var offset = 0
        while true {
            let page: [NutritionFood] = try await client
                .from("foods")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .order("id", ascending: true)
                .range(from: offset, to: offset + Self.readPageSize - 1)
                .execute()
                .value
            all.append(contentsOf: page)
            if page.count < Self.readPageSize { return all }
            offset += page.count
        }
    }

    func fetchFoodEntriesPage(userId: UUID, offset: Int, limit: Int) async throws -> [FoodEntry] {
        try await client
            .from("food_entries")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .order("id", ascending: true)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
    }
}
