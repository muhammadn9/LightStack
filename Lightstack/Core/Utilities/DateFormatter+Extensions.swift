import Foundation

extension DateFormatter {

    /// Format: "Mar 25, 2026"
    static let workoutDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Format: "3/25/26"
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    /// ISO 8601: "2026-03-25T14:30:00Z"
    static let iso8601Date: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Date only: "2026-03-25"
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Day abbreviation: "Mon", "Tue", etc.
    static let dayAbbreviation: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Day number: "1", "25", etc.
    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
}

extension Date {

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
