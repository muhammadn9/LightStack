import Foundation

/// Last session's numbers for one set, shown as grey hints in a repeat session.
struct PreviousSetHint: Codable, Equatable {
    let weightLbs: Double   // 0 = bodyweight
    let reps: Int
    let rir: Int?
}

/// One pending (not-yet-logged) set for an exercise, with editable fields.
struct PendingSetInput: Identifiable {
    var id = UUID()
    // Strength fields
    var weight: String
    var reps: String
    var rir: String
    var note: String = ""
    // Cardio fields (ignored for strength exercises)
    var duration: String = ""
    var distance: String = ""
    var incline: String = ""
    /// Last session's values for this set (repeat sessions only).
    var previous: PreviousSetHint? = nil
}

/// Ticking elapsed-time state, isolated from the view model so per-second
/// updates only redraw views that observe the clock.
final class WorkoutClock: ObservableObject {
    @Published var elapsedSeconds = 0
    @Published var isPaused = false

    var formattedElapsedTime: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
}

/// Manages active workout state: current exercises, set logging,
/// timer tracking, and workout completion.
final class ActiveWorkoutViewModel: ObservableObject {

    @Published var loggedSets: [UUID: [WorkoutSet]] = [:]
    /// Per-exercise array of pending sets (shown as individual editable rows).
    @Published var pendingSets: [UUID: [PendingSetInput]] = [:]
    /// Last session's sets per exercise id, used as hints in a repeat session.
    @Published var previousHints: [UUID: [PreviousSetHint]] = [:]
    // Legacy single-set editing fields kept for any remaining callers.
    @Published var editingWeight: [UUID: String] = [:]
    @Published var editingReps: [UUID: String] = [:]
    @Published var editingRir: [UUID: String] = [:]
    @Published var editingNote: [UUID: String] = [:]
    @Published var restTimerTargetDates: [UUID: Date] = [:]    // exerciseId → target end date
    @Published var restTimerTotalSeconds: [UUID: Int] = [:]    // exerciseId → original duration
    @Published var activeRestExerciseId: UUID? = nil

    /// Elapsed-time state. Deliberately not @Published so ticks don't invalidate observers of this view model.
    let clock = WorkoutClock()

    var elapsedSeconds: Int {
        get { clock.elapsedSeconds }
        set { clock.elapsedSeconds = newValue }
    }
    var isPaused: Bool {
        get { clock.isPaused }
        set { clock.isPaused = newValue }
    }

    private var timer: Timer?
    private var restTimerClock: Timer?

    /// Called when a rest timer starts. Parameters: exerciseName, totalRestSeconds
    var onRestTimerStart: ((String, Int) -> Void)?
    /// Called when a rest timer completes or is cancelled
    var onRestTimerCancel: (() -> Void)?

    /// Total volume (lbs × reps) across all logged sets, given the current exercise list.
    func runningVolume(exercises: [Exercise]) -> Double {
        var volume = 0.0
        for exercise in exercises {
            for s in loggedSets[exercise.id] ?? [] {
                volume += s.weightLbs * Double(s.reps)
            }
        }
        return volume
    }

    /// Fractional progress (0…1) of a rest countdown ending at `target`.
    static func restProgress(target: Date, total: Int, now: Date = Date()) -> Double {
        guard total > 0 else { return 0 }
        let remaining = max(0, target.timeIntervalSince(now))
        return min(1, max(0, (Double(total) - remaining) / Double(total)))
    }

    /// "m:ss" (or "Ns" under a minute) for the time left until `target`.
    static func restText(target: Date, now: Date = Date()) -> String {
        let remaining = max(0, Int(target.timeIntervalSince(now).rounded()))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return minutes > 0 ? "\(minutes):\(String(format: "%02d", seconds))" : "\(seconds)s"
    }

    var formattedElapsedTime: String { clock.formattedElapsedTime }

    /// Elapsed time is derived from wall-clock dates rather than counted tick by
    /// tick, so it keeps advancing while the app is in the background (iOS
    /// suspends Timers there) and catches up on return.
    private var accumulatedSeconds = 0
    private var runningSince: Date?

    func startTimer(from initialSeconds: Int = 0) {
        timer?.invalidate()
        accumulatedSeconds = initialSeconds
        runningSince = Date()
        clock.elapsedSeconds = initialSeconds
        clock.isPaused = false
        scheduleTick()
    }

    func stopTimer() {
        syncElapsed()
        accumulatedSeconds = clock.elapsedSeconds
        runningSince = nil
        timer?.invalidate()
        timer = nil
    }

    func pauseTimer() {
        syncElapsed()
        accumulatedSeconds = clock.elapsedSeconds
        runningSince = nil
        clock.isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resumeTimer() {
        runningSince = Date()
        clock.isPaused = false
        timer?.invalidate()
        scheduleTick()
    }

    /// Recompute elapsed time from the dates. Call on app foreground return.
    func syncElapsed(now: Date = Date()) {
        guard let since = runningSince else { return }
        let elapsed = accumulatedSeconds + max(0, Int(now.timeIntervalSince(since)))
        if clock.elapsedSeconds != elapsed {
            clock.elapsedSeconds = elapsed
        }
    }

    private func scheduleTick() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.syncElapsed() }
        }
    }

    func togglePause() {
        clock.isPaused ? resumeTimer() : pauseTimer()
    }

    /// Parse editing fields, create WorkoutSet, return it for logging.
    func buildSet(exerciseId: UUID) -> WorkoutSet? {
        guard let repsStr = editingReps[exerciseId],
              let reps = Int(repsStr),
              reps > 0
        else { return nil }

        let weightStr = editingWeight[exerciseId] ?? ""
        let weight: Double
        if weightStr.isEmpty || weightStr.uppercased() == "BW" {
            weight = 0.0
        } else if let w = Double(weightStr), w > 0 {
            weight = w
        } else {
            return nil
        }

        let rir = Int(editingRir[exerciseId] ?? "2") ?? 2
        let existingSets = loggedSets[exerciseId] ?? []
        let setNumber = existingSets.count + 1

        let workoutSet = WorkoutSet.create(
            exerciseId: exerciseId,
            setNumber: setNumber,
            weightLbs: weight,
            reps: reps,
            rir: rir
        )

        // Add to local state
        var sets = existingSets
        sets.append(workoutSet)
        loggedSets[exerciseId] = sets

        // Clear editing fields
        editingWeight[exerciseId] = ""
        editingReps[exerciseId] = ""
        editingRir[exerciseId] = ""
        editingNote[exerciseId] = ""

        return workoutSet
    }

    // MARK: - Prefill Targets

    /// Pre-fill input fields with AI-suggested targets for an exercise (only if empty).
    /// Also initialises the per-set pending rows via syncPendingSets.
    func prefillTargets(for exercise: Exercise) {
        if editingWeight[exercise.id]?.isEmpty ?? true {
            editingWeight[exercise.id] = prefillWeightValue(from: exercise)
        }
        if editingReps[exercise.id]?.isEmpty ?? true {
            editingReps[exercise.id] = prefillRepsValue(from: exercise)
        }
        if editingRir[exercise.id]?.isEmpty ?? true {
            editingRir[exercise.id] = prefillRirValue(from: exercise)
        }
        syncPendingSets(for: exercise)
    }

    /// Re-apply an exercise's targets to every input that has not been logged yet.
    ///
    /// Unlike `prefillTargets`, this overwrites what is already on screen. When the
    /// coach changes a target mid-session the value already there is stale by
    /// definition, and `prefillTargets` would defer to it — which is why confirming
    /// a change looked like nothing happened. Logged sets are history, left alone.
    func refreshTargets(for exercise: Exercise) {
        let weight = prefillWeightValue(from: exercise)
        let reps = prefillRepsValue(from: exercise)
        let rir = prefillRirValue(from: exercise)

        editingWeight[exercise.id] = weight
        editingReps[exercise.id] = reps
        editingRir[exercise.id] = rir

        guard exercise.trackingType != .cardio else {
            // Cardio rows carry no targets to refresh; just resize.
            syncPendingSets(for: exercise)
            return
        }

        let needed = max(0, (exercise.targetSets ?? 0) - (loggedSets[exercise.id]?.count ?? 0))
        let existing = pendingSets[exercise.id] ?? []
        pendingSets[exercise.id] = (0..<needed).map { i in
            // Rows carrying a hint keep it (and their blank text) untouched.
            if i < existing.count, existing[i].previous != nil { return existing[i] }
            return PendingSetInput(weight: weight, reps: reps, rir: rir)
        }
    }

    /// Reset legacy single-set fields after logging (carries forward last logged values).
    func resetToTargets(for exercise: Exercise) {
        if let lastSet = loggedSets[exercise.id]?.last {
            editingWeight[exercise.id] = lastSet.weightLbs == 0 ? "BW" : String(format: "%g", lastSet.weightLbs)
            editingReps[exercise.id] = String(lastSet.reps)
            editingRir[exercise.id] = lastSet.rir.map(String.init) ?? ""
            editingNote[exercise.id] = ""
        } else {
            editingWeight[exercise.id] = nil
            editingReps[exercise.id] = nil
            editingRir[exercise.id] = nil
            editingNote[exercise.id] = ""
            prefillTargets(for: exercise)
        }
    }

    func deleteSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        loggedSets[exerciseId]?.removeAll { $0.id == workoutSet.id }
    }

    // MARK: - Pending Sets (all-sets-visible model)

    /// Ensures pendingSets[exercise.id] has exactly (targetSets - loggedSets) entries,
    /// pre-filled with AI targets or last-logged values.
    func syncPendingSets(for exercise: Exercise) {
        let loggedCount = loggedSets[exercise.id]?.count ?? 0
        var targetCount = exercise.targetSets ?? 0
        let hints = exercise.trackingType == .cardio ? [] : (previousHints[exercise.id] ?? [])
        if !hints.isEmpty { targetCount = max(targetCount, hints.count) }
        let needed = max(0, targetCount - loggedCount)

        var current = pendingSets[exercise.id] ?? []

        while current.count < needed {
            let last = loggedSets[exercise.id]?.last
            if exercise.trackingType == .cardio {
                current.append(PendingSetInput(
                    weight: "",
                    reps: "",
                    rir: "",
                    duration: last?.durationSeconds.map { CardioFormatting.formatDuration($0) } ?? "",
                    distance: last?.distanceMiles.map { String(format: "%g", $0) } ?? "",
                    incline: last?.inclineLevel.map { String(format: "%g", $0) } ?? ""
                ))
            } else if let hint = hints[safe: loggedCount + current.count] {
                current.append(PendingSetInput(weight: "", reps: "", rir: "", previous: hint))
            } else {
                current.append(PendingSetInput(
                    weight: last.map { $0.weightLbs == 0 ? "BW" : String(format: "%g", $0.weightLbs) }
                        ?? prefillWeightValue(from: exercise),
                    reps: last.map { String($0.reps) } ?? prefillRepsValue(from: exercise),
                    rir: last.map { $0.rir.map(String.init) ?? "" } ?? prefillRirValue(from: exercise)
                ))
            }
        }
        if current.count > needed {
            current = Array(current.prefix(needed))
        }
        pendingSets[exercise.id] = current
    }

    /// Whether a pending set has enough to be logged as-is. Blank fields with a
    /// previous-session hint count as filled in.
    static func isReadyToLog(_ entry: PendingSetInput, trackingType: TrackingType) -> Bool {
        if trackingType == .cardio {
            return !entry.duration.isEmpty
        }
        return resolveStrength(weight: entry.weight, reps: entry.reps, rir: entry.rir,
                               previous: entry.previous) != nil
    }

    /// Resolves a strength entry to concrete values. Blank fields fall back to
    /// `previous` when present. Returns nil when the entry is not loggable.
    static func resolveStrength(weight: String, reps: String, rir: String,
                                previous: PreviousSetHint?) -> (weight: Double, reps: Int, rir: Int?)? {
        let w = weight.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = reps.trimmingCharacters(in: .whitespacesAndNewlines)
        let i = rir.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedWeight: Double
        if w.isEmpty {
            resolvedWeight = previous?.weightLbs ?? 0
        } else if w.uppercased() == "BW" {
            resolvedWeight = 0
        } else if let value = Double(w), value >= 0 {
            resolvedWeight = value
        } else {
            return nil
        }

        let resolvedReps: Int
        if r.isEmpty {
            guard let previous else { return nil }
            resolvedReps = previous.reps
        } else if let value = Int(r), value >= 0 {
            resolvedReps = value
        } else {
            return nil
        }

        let resolvedRir: Int?
        if i.isEmpty {
            resolvedRir = previous.map { $0.rir } ?? 2
        } else if let value = Int(i), value >= 0 {
            resolvedRir = value <= 10 ? value : nil
        } else {
            resolvedRir = previous.map { $0.rir } ?? 2
        }

        return (resolvedWeight, resolvedReps, resolvedRir)
    }

    /// Log the pending set at `index`, add it to loggedSets, and remove it from pendingSets.
    /// Pass the exercise so we can branch on trackingType.
    func logPendingSet(at index: Int, exerciseId: UUID, exercise: Exercise? = nil) -> WorkoutSet? {
        guard var pending = pendingSets[exerciseId], index < pending.count else { return nil }

        let entry = pending[index]
        let existingSets = loggedSets[exerciseId] ?? []
        let setNumber = existingSets.count + 1

        let workoutSet: WorkoutSet

        if exercise?.trackingType == .cardio {
            // Cardio: require duration, distance and incline are optional
            guard !entry.duration.isEmpty,
                  let durationSecs = CardioFormatting.parseDuration(entry.duration) else { return nil }
            let distance = Double(entry.distance)
            let incline = Double(entry.incline)
            workoutSet = WorkoutSet.create(
                exerciseId: exerciseId,
                setNumber: setNumber,
                weightLbs: 0,
                reps: 0,
                rir: 0,
                userFeedback: entry.note.isEmpty ? nil : entry.note,
                durationSeconds: durationSecs,
                distanceMiles: distance,
                inclineLevel: incline
            )
        } else {
            // Strength: blank fields fall back to the previous-session hint
            guard let resolved = Self.resolveStrength(
                weight: entry.weight, reps: entry.reps, rir: entry.rir, previous: entry.previous
            ) else { return nil }
            let weight = resolved.weight
            let reps = resolved.reps
            let rir = resolved.rir
            workoutSet = WorkoutSet.create(
                exerciseId: exerciseId,
                setNumber: setNumber,
                weightLbs: weight,
                reps: reps,
                rir: rir,
                userFeedback: entry.note.isEmpty ? nil : entry.note
            )
        }

        var logged = existingSets
        logged.append(workoutSet)
        loggedSets[exerciseId] = logged

        pending.remove(at: index)
        pendingSets[exerciseId] = pending

        return workoutSet
    }

    /// Delete the pending set at `index` without logging it (user skipped this set).
    func deletePendingSet(at index: Int, exerciseId: UUID) {
        guard var pending = pendingSets[exerciseId], index < pending.count else { return }
        pending.remove(at: index)
        pendingSets[exerciseId] = pending
    }

    /// Add one extra pending set pre-filled from the last logged set (or AI target).
    func addPendingSet(for exercise: Exercise) {
        let last = loggedSets[exercise.id]?.last
        let entry: PendingSetInput
        if exercise.trackingType == .cardio {
            entry = PendingSetInput(
                weight: "",
                reps: "",
                rir: "",
                duration: last?.durationSeconds.map { CardioFormatting.formatDuration($0) } ?? "",
                distance: last?.distanceMiles.map { String(format: "%g", $0) } ?? "",
                incline: last?.inclineLevel.map { String(format: "%g", $0) } ?? ""
            )
        } else {
            entry = PendingSetInput(
                weight: last.map { $0.weightLbs == 0 ? "BW" : String(format: "%g", $0.weightLbs) }
                    ?? prefillWeightValue(from: exercise),
                reps: last.map { String($0.reps) } ?? prefillRepsValue(from: exercise),
                rir: last.map { $0.rir.map(String.init) ?? "" } ?? prefillRirValue(from: exercise)
            )
        }
        pendingSets[exercise.id, default: []].append(entry)
    }

    // MARK: - Private prefill helpers

    private func prefillWeightValue(from exercise: Exercise) -> String {
        guard let cleaned = exercise.coachNoteParts.weight else { return "" }
        let upper = cleaned.uppercased()
        if upper.contains("BW") || upper.contains("BODYWEIGHT") { return "BW" }
        let parts = cleaned.components(separatedBy: " ")
        if let first = parts.first, Double(first) != nil { return first }
        return ""
    }

    private func prefillRepsValue(from exercise: Exercise) -> String {
        guard let reps = exercise.targetReps,
              let range = reps.range(of: #"\d+"#, options: .regularExpression)
        else { return "" }
        return String(reps[range])
    }

    private func prefillRirValue(from exercise: Exercise) -> String {
        guard let rir = exercise.targetRir,
              let range = rir.range(of: #"\d+"#, options: .regularExpression)
        else { return "2" }
        return String(rir[range])
    }

    // MARK: - Rest Timer

    /// Start a rest countdown timer for an exercise using a target date for background-safe accuracy.
    func startRestTimer(for exerciseId: UUID, seconds: Int, exerciseName: String = "") {
        onRestTimerCancel?()  // cancel any existing notification
        restTimerClock?.invalidate()
        restTimerClock = nil

        let targetDate = Date().addingTimeInterval(TimeInterval(seconds))
        restTimerTargetDates[exerciseId] = targetDate
        restTimerTotalSeconds[exerciseId] = seconds
        activeRestExerciseId = exerciseId

        restTimerClock = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            DispatchQueue.main.async {
                guard let target = self.restTimerTargetDates[exerciseId] else { t.invalidate(); return }
                let remaining = Int(target.timeIntervalSinceNow.rounded())
                if remaining <= 0 {
                    self.restTimerTargetDates.removeValue(forKey: exerciseId)
                    self.restTimerTotalSeconds.removeValue(forKey: exerciseId)
                    self.activeRestExerciseId = nil
                    t.invalidate()
                    self.restTimerClock = nil
                    self.onRestTimerCancel?()  // timer expired naturally
                }
            }
        }

        onRestTimerStart?(exerciseName, seconds)  // schedule new notification
    }

    /// Call on app foreground return: clears any rest timer that expired while suspended.
    func refreshRestTimers() {
        let expired = restTimerTargetDates.filter { $0.value.timeIntervalSinceNow.rounded() <= 0 }.map(\.key)
        guard !expired.isEmpty else { return }
        for id in expired {
            restTimerTargetDates.removeValue(forKey: id)
            restTimerTotalSeconds.removeValue(forKey: id)
            if activeRestExerciseId == id { activeRestExerciseId = nil }
        }
        if restTimerTargetDates.isEmpty {
            restTimerClock?.invalidate()
            restTimerClock = nil
        }
        onRestTimerCancel?()
    }

    /// Stop every rest timer and cancel its pending notification. Call when the
    /// workout ends (finish or discard) so no "rest over" alert fires afterwards.
    func cancelAllRestTimers() {
        restTimerClock?.invalidate()
        restTimerClock = nil
        restTimerTargetDates.removeAll()
        restTimerTotalSeconds.removeAll()
        activeRestExerciseId = nil
        onRestTimerCancel?()
    }

    deinit {
        stopTimer()
        restTimerClock?.invalidate()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
