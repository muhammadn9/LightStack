import AVFoundation

/// Everything one recorded set produced: the analysis, the raw pose track and the movie.
struct FormSessionResult: Identifiable {
    let id = UUID()
    let exerciseName: String
    let analysis: FormAnalysis
    let track: PoseTrack
    /// nil in UI tests or if recording failed.
    let videoURL: URL?
    let cameraPosition: AVCaptureDevice.Position
}
