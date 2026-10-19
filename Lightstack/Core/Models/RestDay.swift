import Foundation

/// Local representation of the rest_days table (one row per user per calendar day).
struct RestDay: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    /// Start of the user's calendar day.
    var date: Date
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case createdAt = "created_at"
    }

    /// Calendar day in the user's own time zone (rest days are "that day for me",
    /// unlike the UTC `DateFormatter.dateOnly`).
    private static func localDayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// `yyyy-MM-dd` of the user's calendar day, as stored in the DATE column.
    static func dayString(_ date: Date) -> String { RemoteDate.dayString(date) }

    init(id: UUID, userId: UUID, date: Date, createdAt: Date) {
        self.id = id
        self.userId = userId
        self.date = date
        self.createdAt = createdAt
    }

    init(from cdEntity: CDRestDay) {
        self.id = cdEntity.id ?? UUID()
        self.userId = cdEntity.userId ?? UUID()
        self.date = cdEntity.date ?? Date()
        self.createdAt = cdEntity.createdAt ?? Date()
    }

    /// Decodes both the queue's own encoding (numeric dates) and Supabase rows
    /// (`yyyy-MM-dd` date, ISO timestamp).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userId = try c.decode(UUID.self, forKey: .userId)
        if let text = try? c.decode(String.self, forKey: .date),
           let parsed = Self.localDayFormatter().date(from: text) {
            date = parsed
        } else {
            date = try c.decode(Date.self, forKey: .date)
        }
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// Queue encoding: plain dates, round-trips through the queue's default coder.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(date, forKey: .date)
        try c.encode(createdAt, forKey: .createdAt)
    }

    /// Row sent to Supabase: `date` is a DATE column, so it is sent as `yyyy-MM-dd`.
    func toSupabase() -> SupabaseRestDay {
        SupabaseRestDay(
            id: id,
            userId: userId,
            date: Self.dayString(date),
            createdAt: createdAt
        )
    }
}

struct SupabaseRestDay: Encodable {
    let id: UUID
    let userId: UUID
    let date: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case createdAt = "created_at"
    }
}
