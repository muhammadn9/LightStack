import Foundation

/// Quality assessment for a single rep within a set.
struct RepQuality {
    let repNumber: Int
    let romPercent: Double        // 0-100: how much of expected range of motion was achieved
    let symmetryScore: Double     // 0-100: left/right symmetry (100 = perfect)
    let durationSeconds: Double   // time to complete the rep
    let flags: [String]           // human-readable issues, e.g. "Shallow depth", "Too fast"

    var isGood: Bool { flags.isEmpty && romPercent >= 70 }
}
