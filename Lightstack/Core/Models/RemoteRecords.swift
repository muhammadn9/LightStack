import Foundation

/// Decoding of rows as Supabase returns them for a restore.
///
/// The Supabase client's JSON decoder only accepts full ISO timestamps, but several
/// columns are `DATE` (`workouts.date`, `month_plans.start_date/end_date`,
/// `planned_sessions.planned_date`) and come back as `"2026-10-15"`. The app models
/// decode strictly, so restore decodes through these wrappers instead.
enum RemoteDate {

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// `yyyy-MM-dd` of the device-local calendar day: how every DATE column is written.
    static func dayString(_ date: Date) -> String { dayFormatter().string(from: date) }

    /// Start of the user's calendar day for a `yyyy-MM-dd` string; nil for any other text.
    static func localDay(_ text: String) -> Date? {
        guard text.count == 10 else { return nil }
        return dayFormatter().date(from: text)
    }

    /// A DATE column (or a full timestamp, if the column type ever changes).
    static func decodeDay<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Date {
        if let text = try? c.decode(String.self, forKey: key), let day = localDay(text) { return day }
        return try c.decode(Date.self, forKey: key)
    }

    /// `workouts.date`. Rows written by current builds hold the device-local day. Legacy rows were
    /// uploaded as a full instant, so Postgres kept the UTC day (an evening workout west of UTC sits
    /// under the next day). When `createdAt` falls on the stored UTC day the row is read as legacy and
    /// the original instant is that `createdAt`; otherwise the stored day at local noon, which stays
    /// inside the right local day whatever the zone. (A past-dated import whose UTC created day happens
    /// to equal its stored day is indistinguishable from a legacy row and gets `createdAt`.)
    static func decodeWorkoutDate<K: CodingKey>(
        _ c: KeyedDecodingContainer<K>, _ key: K, createdAt: Date
    ) throws -> Date {
        guard let text = try? c.decode(String.self, forKey: key), let day = localDay(text) else {
            return try c.decode(Date.self, forKey: key)
        }
        if DateFormatter.dateOnly.string(from: createdAt) == text { return createdAt }
        return Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? day
    }
}

/// One `sets` row inside an embedded exercise, kept as the app model.
struct RemoteExerciseRecord: Decodable {
    let exercise: Exercise
    let sets: [WorkoutSet]

    private enum Extra: String, CodingKey { case sets }

    init(from decoder: Decoder) throws {
        exercise = try Exercise(from: decoder)
        let extra = try decoder.container(keyedBy: Extra.self)
        sets = (try extra.decodeIfPresent([WorkoutSet].self, forKey: .sets) ?? [])
            .sorted { $0.setNumber < $1.setNumber }
    }
}

/// A `workouts` row with its embedded `exercises(*, sets(*))`.
struct RemoteWorkoutRecord: Decodable {
    let workout: Workout
    let exercises: [RemoteExerciseRecord]

    private enum Extra: String, CodingKey { case exercises }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Workout.CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let userId = try c.decode(UUID.self, forKey: .userId)
        let createdAtValue = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        let date = try RemoteDate.decodeWorkoutDate(c, .date, createdAt: createdAtValue ?? Date())
        workout = Workout(
            id: id,
            userId: userId,
            localId: try c.decodeIfPresent(String.self, forKey: .localId),
            date: date,
            workoutType: try c.decode(String.self, forKey: .workoutType),
            durationMinutes: try c.decodeIfPresent(Int.self, forKey: .durationMinutes),
            energyLevel: try c.decodeIfPresent(Int.self, forKey: .energyLevel),
            timeAvailableMinutes: try c.decodeIfPresent(Int.self, forKey: .timeAvailableMinutes),
            userNote: try c.decodeIfPresent(String.self, forKey: .userNote),
            setupNote: try c.decodeIfPresent(String.self, forKey: .setupNote),
            aiProgressionNote: try c.decodeIfPresent(String.self, forKey: .aiProgressionNote),
            plannedSessionId: try c.decodeIfPresent(UUID.self, forKey: .plannedSessionId),
            syncStatus: .synced,
            createdAt: createdAtValue ?? date
        )
        let extra = try decoder.container(keyedBy: Extra.self)
        exercises = (try extra.decodeIfPresent([RemoteExerciseRecord].self, forKey: .exercises) ?? [])
            .sorted { $0.exercise.orderIndex < $1.exercise.orderIndex }
    }

    /// Builds a record directly (fakes and tests).
    init(workout: Workout, exercises: [(Exercise, [WorkoutSet])]) {
        self.workout = workout
        self.exercises = exercises.map { RemoteExerciseRecord(exercise: $0.0, sets: $0.1) }
    }
}

extension RemoteExerciseRecord {
    init(exercise: Exercise, sets: [WorkoutSet]) {
        self.exercise = exercise
        self.sets = sets
    }
}

/// A `month_plans` row (its DATE columns decoded leniently).
struct RemoteMonthPlan: Decodable {
    let plan: MonthPlan

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MonthPlan.CodingKeys.self)
        plan = MonthPlan(
            id: try c.decode(UUID.self, forKey: .id),
            userId: try c.decode(UUID.self, forKey: .userId),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            targetGoal: try c.decodeIfPresent(String.self, forKey: .targetGoal),
            startDate: try RemoteDate.decodeDay(c, .startDate),
            endDate: try RemoteDate.decodeDay(c, .endDate),
            aiOverview: try c.decodeIfPresent(String.self, forKey: .aiOverview),
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        )
    }
}

/// A `planned_sessions` row (its DATE column decoded leniently).
struct RemotePlannedSession: Decodable {
    let session: PlannedSession

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PlannedSession.CodingKeys.self)
        session = PlannedSession(
            id: try c.decode(UUID.self, forKey: .id),
            monthPlanId: try c.decode(UUID.self, forKey: .monthPlanId),
            userId: try c.decode(UUID.self, forKey: .userId),
            plannedDate: try RemoteDate.decodeDay(c, .plannedDate),
            workoutType: try c.decode(String.self, forKey: .workoutType),
            focusNote: try c.decodeIfPresent(String.self, forKey: .focusNote),
            isRestDay: try c.decodeIfPresent(Bool.self, forKey: .isRestDay) ?? false,
            completed: try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false,
            workoutId: try c.decodeIfPresent(UUID.self, forKey: .workoutId)
        )
    }
}

/// A `sync_tombstones` row: this record was deleted on some device.
struct RemoteTombstone: Decodable, Equatable {
    let entity: String
    let recordId: UUID
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case entity
        case recordId = "record_id"
        case deletedAt = "deleted_at"
    }

    init(entity: String, recordId: UUID, deletedAt: Date? = nil) {
        self.entity = entity
        self.recordId = recordId
        self.deletedAt = deletedAt
    }

    init(entity: TombstoneEntity, recordId: UUID) {
        self.init(entity: entity.rawValue, recordId: recordId)
    }
}
