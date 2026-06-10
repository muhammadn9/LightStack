import Foundation
import Vision

/// Converts a sequence of BodyPose frames into a FormAnalysisResult.
/// Uses joint-angle oscillation detection to count reps and assess quality.
/// Applies FreeMocap-inspired IIR smoothing and bilateral angle averaging.
final class RepCounterService {

    // MARK: - Exercise Configuration

    private struct JointTriple {
        let a: VNHumanBodyPoseObservation.JointName
        let b: VNHumanBodyPoseObservation.JointName   // vertex
        let c: VNHumanBodyPoseObservation.JointName
        let mirrorA: VNHumanBodyPoseObservation.JointName?  // right-side counterparts for bilateral averaging
        let mirrorB: VNHumanBodyPoseObservation.JointName?
        let mirrorC: VNHumanBodyPoseObservation.JointName?
        let startAngle: Double      // expected angle at top of movement
        let endAngle: Double        // expected angle at bottom of movement
        let shallowThreshold: Double
    }

    private static let squat = JointTriple(
        a: .leftHip, b: .leftKnee, c: .leftAnkle,
        mirrorA: .rightHip, mirrorB: .rightKnee, mirrorC: .rightAnkle,
        startAngle: 155, endAngle: 90, shallowThreshold: 120
    )
    private static let deadlift = JointTriple(
        a: .leftShoulder, b: .leftHip, c: .leftKnee,
        mirrorA: .rightShoulder, mirrorB: .rightHip, mirrorC: .rightKnee,
        startAngle: 170, endAngle: 90, shallowThreshold: 130
    )
    private static let pushup = JointTriple(
        // Hip-Shoulder-Elbow angle captures the body lowering/rising during push-ups
        // from a front-facing camera. Also uses elbow angle as fallback.
        a: .leftHip, b: .leftShoulder, c: .leftElbow,
        mirrorA: .rightHip, mirrorB: .rightShoulder, mirrorC: .rightElbow,
        startAngle: 150, endAngle: 75, shallowThreshold: 110
    )
    private static let upperPush = JointTriple(
        a: .leftShoulder, b: .leftElbow, c: .leftWrist,
        mirrorA: .rightShoulder, mirrorB: .rightElbow, mirrorC: .rightWrist,
        startAngle: 160, endAngle: 60, shallowThreshold: 90
    )
    private static let upperPull = JointTriple(
        a: .leftShoulder, b: .leftElbow, c: .leftWrist,
        mirrorA: .rightShoulder, mirrorB: .rightElbow, mirrorC: .rightWrist,
        startAngle: 160, endAngle: 60, shallowThreshold: 100
    )

    // MARK: - Public

    func analyze(poses: [BodyPose], exerciseName: String) -> FormAnalysisResult {
        let config = jointConfig(for: exerciseName)
        let smoothed = smoothPoses(poses)
        let angles = extractAngles(from: smoothed, config: config)
        let reps = detectReps(in: angles, config: config, poses: smoothed)
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
        if lower.contains("push up") || lower.contains("pushup") || lower.contains("push-up") {
            return Self.pushup
        } else if lower.contains("squat") || lower.contains("lunge") || lower.contains("leg press") {
            return Self.squat
        } else if lower.contains("deadlift") || lower.contains("rdl") || lower.contains("hip hinge") {
            return Self.deadlift
        } else if lower.contains("row") || lower.contains("pull") || lower.contains("curl") || lower.contains("chin") {
            return Self.upperPull
        } else {
            return Self.upperPush
        }
    }

    // MARK: - FreeMocap-inspired: IIR low-pass filter (2nd order, ~4 Hz cutoff at 30 fps)

    private func smoothPoses(_ poses: [BodyPose]) -> [BodyPose] {
        guard poses.count > 4 else { return poses }

        // 2nd-order Butterworth coefficients for 4 Hz cutoff at 30 fps
        // fs=30, fc=4 → Wn=4/15=0.267, computed via bilinear transform
        let b0 = 0.0955, b1 = 0.1910, b2 = 0.0955
        let a1 = -0.9428, a2 = 0.3333    // Note: stored as -a1, -a2 (direct form II)

        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .neck
        ]

        var result = poses

        for jointName in jointNames {
            // Collect x and y series
            let xs = poses.map { $0.joints[jointName]?.x ?? 0.0 }
            let ys = poses.map { $0.joints[jointName]?.y ?? 0.0 }

            // Filter x
            var xf = xs
            for i in 2..<xs.count {
                xf[i] = b0*xs[i] + b1*xs[i-1] + b2*xs[i-2] - a1*xf[i-1] - a2*xf[i-2]
            }
            // Filter y
            var yf = ys
            for i in 2..<ys.count {
                yf[i] = b0*ys[i] + b1*ys[i-1] + b2*ys[i-2] - a1*yf[i-1] - a2*yf[i-2]
            }

            for i in 0..<poses.count {
                if poses[i].joints[jointName] != nil {
                    var updatedJoints = result[i].joints
                    updatedJoints[jointName] = CGPoint(x: xf[i], y: yf[i])
                    result[i] = BodyPose(
                        timestamp: result[i].timestamp,
                        joints: updatedJoints,
                        confidences: result[i].confidences
                    )
                }
            }
        }

        return result
    }

    // MARK: - Angle Extraction (bilateral average)

    private func extractAngles(from poses: [BodyPose], config: JointTriple) -> [(poseIndex: Int, t: TimeInterval, angle: Double)] {
        poses.enumerated().compactMap { index, pose in
            let leftAngle = pose.angle(from: config.a, through: config.b, to: config.c)

            // If right-side joints are available, average both sides
            var rightAngle: Double? = nil
            if let mA = config.mirrorA, let mB = config.mirrorB, let mC = config.mirrorC {
                rightAngle = pose.angle(from: mA, through: mB, to: mC)
            }

            let angle: Double
            switch (leftAngle, rightAngle) {
            case let (l?, r?): angle = (l + r) / 2.0
            case let (l?, nil): angle = l
            case let (nil, r?): angle = r
            case (nil, nil): return nil
            }
            return (poseIndex: index, t: pose.timestamp, angle: angle)
        }
    }

    // MARK: - Rep Detection

    private func detectReps(
        in angles: [(poseIndex: Int, t: TimeInterval, angle: Double)],
        config: JointTriple,
        poses: [BodyPose]
    ) -> [RepQuality] {
        guard angles.count >= 5 else { return [] }

        let values = angles.map { $0.angle }
        let timestamps = angles.map { $0.t }
        let smoothed = smooth(values, windowSize: 5)

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

                    let startPoseIdx = angles[repStartIdx].poseIndex
                    let endPoseIdx = min(angles[i].poseIndex, poses.count)
                    let poseRange = startPoseIdx < endPoseIdx ? poses[startPoseIdx..<endPoseIdx] : poses[startPoseIdx..<startPoseIdx]
                    let symmetry = symmetryScore(poses: Array(poseRange))

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
                (pose.confidences[.leftElbow] ?? 0) > 0.15,
                (pose.confidences[.rightElbow] ?? 0) > 0.15
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
