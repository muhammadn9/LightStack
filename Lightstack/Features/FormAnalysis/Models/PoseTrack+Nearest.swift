import Foundation

extension PoseTrack {

    /// The frame closest in time to `time`, or nil when the track is empty or the closest frame is
    /// further away than `maxGap` seconds. Frames must be in ascending time order (binary search).
    func nearestFrame(to time: TimeInterval, maxGap: TimeInterval = .infinity) -> PoseFrame? {
        guard !frames.isEmpty else { return nil }
        var low = 0, high = frames.count - 1
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].time < time { low = mid + 1 } else { high = mid }
        }
        // `low` is the first frame at or after `time`; the previous one may be closer.
        var best = frames[low]
        if low > 0, abs(frames[low - 1].time - time) <= abs(best.time - time) { best = frames[low - 1] }
        return abs(best.time - time) <= maxGap ? best : nil
    }
}
