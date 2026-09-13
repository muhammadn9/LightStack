import Foundation

/// Utilities for parsing and formatting cardio set fields (duration, distance, pace).
enum CardioFormatting {

    // MARK: - Duration Parsing

    /// Parses a user-entered duration string into total seconds.
    ///
    /// Accepted formats:
    /// - `"28"` → 1680 seconds (plain minutes)
    /// - `"28:30"` → 1710 seconds (mm:ss)
    /// - `"1:28:30"` → 5310 seconds (h:mm:ss)
    ///
    /// Returns nil if the string is empty or cannot be parsed.
    static func parseDuration(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.components(separatedBy: ":")
        switch parts.count {
        case 1:
            // Plain number → treat as whole minutes
            guard let minutes = Int(parts[0]), minutes >= 0 else { return nil }
            return minutes * 60
        case 2:
            guard let minutes = Int(parts[0]), minutes >= 0,
                  let seconds = Int(parts[1]), seconds >= 0, seconds < 60 else { return nil }
            return minutes * 60 + seconds
        case 3:
            guard let hours = Int(parts[0]), hours >= 0,
                  let minutes = Int(parts[1]), minutes >= 0, minutes < 60,
                  let seconds = Int(parts[2]), seconds >= 0, seconds < 60 else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        default:
            return nil
        }
    }

    // MARK: - Duration Formatting

    /// Formats total seconds to a human-readable `mm:ss` or `h:mm:ss` string.
    static func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Pace Calculation

    /// Returns a pace string `"mm:ss /mi"` given total seconds and distance in miles.
    /// Returns nil if distance is zero or either argument is nil.
    static func pace(durationSeconds: Int?, distanceMiles: Double?) -> String? {
        guard let secs = durationSeconds, secs > 0,
              let miles = distanceMiles, miles > 0 else { return nil }
        let secsPerMile = Int((Double(secs) / miles).rounded())
        let paceMin = secsPerMile / 60
        let paceSec = secsPerMile % 60
        return String(format: "%d:%02d /mi", paceMin, paceSec)
    }

    // MARK: - Logged Set Summary

    /// Builds the compact one-line description shown in a logged cardio set row,
    /// e.g. `"28:00 · 2.4 mi · 3.0% · 11:40 /mi"`.
    static func loggedSummary(durationSeconds: Int?, distanceMiles: Double?, inclineLevel: Double?) -> String {
        var parts: [String] = []
        if let secs = durationSeconds {
            parts.append(formatDuration(secs))
        }
        if let miles = distanceMiles {
            parts.append(String(format: "%g mi", miles))
        }
        if let incline = inclineLevel {
            parts.append(String(format: "%g%%", incline))
        }
        if let paceStr = pace(durationSeconds: durationSeconds, distanceMiles: distanceMiles) {
            parts.append(paceStr)
        }
        return parts.joined(separator: " · ")
    }
}
