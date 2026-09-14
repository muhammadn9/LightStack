import Foundation
import UserNotifications
import os

/// Manages local notifications for rest timer alerts.
final class NotificationService {

    static let restTimerCategoryId = "REST_TIMER"
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "org.lightstack.app", category: "NotificationService")

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                self.logger.error("Permission error: \(error)")
            }
        }
    }

    /// Schedule a notification to fire when 10 seconds remain in the rest period.
    /// Requests permission contextually on first use (no-op once status is determined).
    func scheduleRestTimerAlert(exerciseName: String, totalRestSeconds: Int) {
        let notifEnabled = UserDefaults.standard.object(forKey: "restTimerNotificationsEnabled") as? Bool ?? true
        guard notifEnabled else { return }
        let alertAt = totalRestSeconds - 10
        guard alertAt > 0 else { return }

        // Request permission contextually (no-op if already determined)
        requestPermission()

        // Schedule with stable identifier (system replaces existing with same ID)
        cancelPendingRestAlerts()

        let content = UNMutableNotificationContent()
        content.title = "Rest Almost Over"
        content.body = "10 seconds left on your rest for \(exerciseName). Get ready!"
        content.sound = .default
        content.categoryIdentifier = Self.restTimerCategoryId

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(alertAt), repeats: false)
        let request = UNNotificationRequest(identifier: "rest-timer-alert", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                self.logger.error("Schedule error: \(error)")
            }
        }
    }

    func cancelPendingRestAlerts() {
        center.removePendingNotificationRequests(withIdentifiers: ["rest-timer-alert"])
    }
}
