import Foundation
import Vision

/// Converts a sequence of BodyPose frames into a FormAnalysisResult.
/// Uses joint-angle oscillation detection to count reps and assess quality.
final class RepCounterService {

    // MARK: - Exercise Configuration

    private struct JointTriple {
        let a: VNHumanBodyPoseObservation.JointName
        let b: VNHumanBodyPoseObservation.JointName   // vertex
        let c: VNHumanBodyPoseObservation.JointName
        let startAngle: Double      // expected angle at top of movement
        let endAngle: Double        // expected angle at bottom of movement
        let shallowThreshold: Double
    }

    private static let squat = JointTriple(
        a: .leftHip, b: .leftKnee, c: .leftAnkle,
        startAngle: 155, endAngle: 90, shallowThreshold: 120
    )
    private static let deadlift = JointTriple(
        a: .leftShoulder, b: .leftHip, c: .leftKnee,
        startAngle: 170, endAngle: 90, shallowThreshold: 130
    )
    private static let upperPush = JointTriple(
        a: .leftShoulder, b: .leftElbow, c: .leftWrist,
        startAngle: 160, endAngle: 60, shallowThreshold: 90
    )
    private static let upperPull = JointTriple(
        a: .leftShoulder, b: .leftElbow, c: .leftWrist,
        startAngle: 160, endAngle: 60, shallowThreshold: 100
    )

    // MARK: - Public

    func analyze(poses: [BodyPose], exerciseName: String) -> FormAnalysisResult {
        let config = jointConfig(for: exerciseName)
        let angles = extractAngles(from: poses, config: config)
        let reps = detectReps(in: angles, config: config, poses: poses)
        return FormAnalysisResult(
            exerciseName: exerciseName,
            repCount: reps.count,
            repQualities: reps,
            aiCoachText: nil
        )
    }

    // MARK: - Private

    private func jointConfig(for exerciseName: String) -> JointTriple {
        let lower = exerciseName.lowercased()
        if lower.contains("squat") || lower.contains("lunge") || lower.contains("leg press") {
            return Self.squat
        } else if lower.contains("deadlift") || lower.contains("rdl") || lower.contains("hip hinge") {
            return Self.deadlift
        } else if lower.contains("row") || lower.contains("pull") || lower.contains("curl") || lower.contains("chin") {
            return Self.upperPull
        } else {
            return Self.upperPush
        }
    }

    private func extractAngles(from poses: [BodyPose], config: JointTriple) -> [(TimeInterval, Double)] {
        poses.compactMap { pose in
            guard let angle = pose.angle(from: config.a, through: config.b, to: config.c)
            else { return nil }
            return (pose.timestamp, angle)
        }
    }

    private func detectReps(
        in angles: [(TimeInterval, Double)],
        config: JointTriple,
        poses: [BodyPose]
    ) -> [RepQuality] {
        guard angles.count >= 5 else { return [] }

        let smoothed = smooth(angles.map { $0.1 }, windowSize: 5)
        let timestamps = angles.map { $0.0 }

        let threshold = (config.startAngle + config.endAngle) / 2.0

        var reps: [RepQuality] = []
        var inRep = false
        var repStartIdx = 0
        var minAngleInRep = config.startAngle
        var repNumber = 1

        for i in 1..<smoothed.count {
            let angle = smoothed[i]

            if !inRep && angle < threshold {
                inRep = true
                repStartIdx = i
                minAngleInRep = angle
            } else if inRep {
                minAngleInRep = min(minAngleInRep, angle)

                if angle > (config.startAngle - 15) {
                    let duration = timestamps[i] - timestamps[repStartIdx]
                    let rom = max(0, min(100,
                        (config.startAngle - minAngleInRep) /
                        (config.startAngle - config.endAngle) * 100
                    ))

                    var flags: [String] = []
                    if minAngleInRep > config.shallowThreshold { flags.append("Shallow depth") }
                    if duration < 0.8 { flags.append("Too fast") }
                    if duration > 6.0 { flags.append("Very slow pace") }

                    let repPoses = poses[repStartIdx..<min(i, poses.count)]
                    let symmetry = symmetryScore(poses: Array(repPoses))

                    reps.append(RepQuality(
                        repNumber: repNumber,
                        romPercent: rom,
                        symmetryScore: symmetry,
                        durationSeconds: duration,
                        flags: flags
                    ))
                    repNumber += 1
                    inRep = false
                }
            }
        }

        return reps
    }

    private func smooth(_ values: [Double], windowSize: Int) -> [Double] {
        values.enumerated().map { i, _ in
            let start = max(0, i - windowSize / 2)
            let end = min(values.count, i + windowSize / 2 + 1)
            let window = values[start..<end]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    private func symmetryScore(poses: [BodyPose]) -> Double {
        let diffs: [Double] = poses.compactMap { pose in
            guard
                let ls = pose.joints[.leftShoulder],
                let rs = pose.joints[.rightShoulder],
                let le = pose.joints[.leftElbow],
                let re = pose.joints[.rightElbow],
                (pose.confidences[.leftElbow] ?? 0) > 0.3,
                (pose.confidences[.rightElbow] ?? 0) > 0.3
            else { return nil }
            let leftH = abs(ls.y - le.y)
            let rightH = abs(rs.y - re.y)
            let maxH = max(leftH, rightH)
            guard maxH > 0 else { return 0 }
            return abs(leftH - rightH) / maxH
        }
        guard !diffs.isEmpty else { return 80.0 }
        let avgDiff = diffs.reduce(0, +) / Double(diffs.count)
        return max(0, min(100, (1 - avgDiff) * 100))
    }
}
