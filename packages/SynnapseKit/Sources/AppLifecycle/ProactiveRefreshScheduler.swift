import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// Schedules the periodic proactive-feed refresh on each platform's native
/// background facility — `BGTaskScheduler` on iOS, `NSBackgroundActivityScheduler`
/// on macOS. The actual work (analyzer → store → notification) lives in the
/// `handler` closure the shell supplies (wired to `AppCore.runScheduledRefresh`
/// plus a `NotificationGate` post); this type only owns the registration and
/// the recurrence cadence so the platform glue stays out of `AppCore`.
///
/// iOS note: `register` must run before the app finishes launching, so the
/// shell calls it from the `App` value's first `.task`. `submit` is also called
/// when the app backgrounds. Background execution can only be confirmed on a
/// device / simulator with the debugger `_simulateLaunchForTaskWithIdentifier`
/// hook — it is out of reach of `swift test`.
@MainActor
public final class ProactiveRefreshScheduler {

    /// Matches the `BGTaskSchedulerPermittedIdentifiers` entry in the iOS
    /// Info.plist and the `NSBackgroundActivityScheduler` identifier on macOS.
    public static let taskIdentifier = "tech.synnapse.refresh.proactive"

    /// Twelve hours — the cadence the substrate plan pinned for transaction /
    /// insight refresh.
    public static let interval: TimeInterval = 12 * 3600

    private var registered = false
    #if os(macOS)
    private var activity: NSBackgroundActivityScheduler?
    #endif

    public init() {}

    /// Register the platform task with a handler that runs the refresh. Safe to
    /// call more than once; only the first call wires the scheduler.
    public func register(handler: @escaping @Sendable () async -> Void) {
        guard !registered else { return }
        registered = true

        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            // Re-arm the next run before doing work so a crash mid-task can't
            // strand the schedule.
            Self.submitNext()
            let work = Task {
                await handler()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        Self.submitNext()
        #elseif os(macOS)
        let activity = NSBackgroundActivityScheduler(identifier: Self.taskIdentifier)
        activity.repeats = true
        activity.interval = Self.interval
        activity.qualityOfService = .utility
        activity.schedule { completion in
            Task {
                await handler()
                completion(.finished)
            }
        }
        self.activity = activity
        #endif
    }

    /// iOS only: submit the next app-refresh request. Called on registration and
    /// again from the task handler so the cadence keeps rolling.
    public static func submitNext() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}
