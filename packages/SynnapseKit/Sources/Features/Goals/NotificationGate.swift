import Foundation
import UserNotifications

/// Permission + scheduling helper around `UNUserNotificationCenter`.
/// Two responsibilities:
///
///   1. Lazy permission. The first call to `requestIfNeeded()` after
///      the user has demonstrated intent (e.g. tapped "Apply as
///      goal") prompts; subsequent calls are no-ops.
///   2. Idempotent recurring reminder. Schedules a Sunday 11am local
///      "time to check your goals" reminder once per app lifetime;
///      reschedules are de-duped by identifier.
///
/// All entry points are `async` because the underlying APIs are too.
public actor NotificationGate {
    public static let shared = NotificationGate()

    public enum PermissionState: String, Sendable {
        case unknown, granted, denied
    }

    private var hasRequested = false
    private var hasScheduledWeekly = false

    public init() {}

    public func requestIfNeeded() async -> PermissionState {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            if hasRequested { return .unknown }
            hasRequested = true
            do {
                let ok = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                return ok ? .granted : .denied
            } catch {
                return .unknown
            }
        @unknown default:
            return .unknown
        }
    }

    /// Schedule a one-shot notification fired ~1s from now. Used by
    /// the evaluator to surface a summary right after results land.
    public func postWeeklySummary(hitCount: Int, totalCount: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Weekly goals check-in"
        content.body  = "\(hitCount) of \(totalCount) goals hit this week. Open Synapse to see what shifted."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(
            identifier: "synnapse.goals.weekly.summary.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(req)
    }

    /// One-shot summary fired after a proactive-feed refresh surfaced new or
    /// changed signals. The nightly background task calls this so the user
    /// learns about an upcoming bill / anomaly without opening the app.
    public func postProactiveSummary(newCount: Int) async {
        guard newCount > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "New in your inbox"
        let noun = newCount == 1 ? "insight" : "insights"
        content.body = "\(newCount) new \(noun) — a bill, a new subscription, or unusual spending. Open Synapse to review."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(
            identifier: "synnapse.proactive.summary.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(req)
    }

    /// Idempotent: schedules the recurring Sunday-11am reminder once
    /// per app lifetime. Identifier-based de-duping means re-calls
    /// are safe.
    public func scheduleRecurringWeeklyReminderIfNeeded() async {
        guard hasScheduledWeekly == false else { return }
        hasScheduledWeekly = true

        let content = UNMutableNotificationContent()
        content.title = "Goals check-in"
        content.body  = "It's Sunday — open Synapse to see how your weekly goals landed."
        content.sound = .default

        var trigger = DateComponents()
        trigger.weekday = 1            // Sunday
        trigger.hour = 11
        trigger.minute = 0
        let cal = UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)

        let req = UNNotificationRequest(
            identifier: "synnapse.goals.weekly.reminder",
            content: content,
            trigger: cal
        )
        try? await UNUserNotificationCenter.current().add(req)
    }
}
