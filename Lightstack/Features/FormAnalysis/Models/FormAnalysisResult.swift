import Foundation

/// The complete analysis result for one exercise set.
struct FormAnalysisResult: Identifiable {
    let exerciseName: String
    let repCount: Int
    let repQualities: [RepQuality]
    var poses3D: [BodyPose3D] = []  // collected from VNDetectHumanBodyPose3DRequest (iOS 17+)
    var aiCoachText: String?        // filled in asynchronously by FormFeedbackService

    var id: String { exerciseName + String(repCount) }
    var goodRepCount: Int { repQualities.filter { $0.isGood }.count }

    /// Formats rep qualities as structured text for the AI prompt.
    func repSummaryForPrompt() -> String {
        guard !repQualities.isEmpty else { return "No reps detected." }
        return repQualities.map { rep in
            let flags = rep.flags.isEmpty ? "good form" : rep.flags.joined(separator: ", ")
            return "Rep \(rep.repNumber): ROM \(Int(rep.romPercent))%, symmetry \(Int(rep.symmetryScore))%, \(String(format: "%.1f", rep.durationSeconds))s, \(flags)"
        }.joined(separator: "\n")
    }
}
