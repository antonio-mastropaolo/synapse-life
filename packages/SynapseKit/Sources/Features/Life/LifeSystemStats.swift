import Foundation

/// Live "the terminal is alive" stats line.
///
/// The provider is clock-injected so tests never depend on the wall clock
/// or `ProcessInfo.processStartTime`. The view layer wires the real values
/// in via a `TimelineView(.periodic)` that ticks once per second.
public struct LifeSystemStats: Sendable, Equatable {

    public let now: Date
    public let uptimeSeconds: Int
    public let physicalMemoryGiB: Double

    public init(now: Date, uptimeSeconds: Int, physicalMemoryGiB: Double) {
        self.now = now
        self.uptimeSeconds = uptimeSeconds
        self.physicalMemoryGiB = physicalMemoryGiB
    }

    /// Build a snapshot from raw inputs. Pure: takes the current instant,
    /// the launch instant, and the device's physical memory in bytes;
    /// returns the rendered struct. The view's `TimelineView` invokes this
    /// once per second with the live values.
    public static func snapshot(
        now: Date,
        launchedAt: Date,
        physicalMemoryBytes: Int64
    ) -> LifeSystemStats {
        let raw = now.timeIntervalSince(launchedAt)
        // Sub-second or negative clock skew clamps to zero. A negative
        // uptime would render as `up -0:0:01` which looks broken.
        let uptime = raw < 1 ? 0 : Int(raw.rounded(.down))
        let gib = Double(physicalMemoryBytes) / (1024 * 1024 * 1024)
        // Round to one decimal so the column doesn't dance every tick.
        let gibRounded = (gib * 10).rounded() / 10
        return LifeSystemStats(
            now: now,
            uptimeSeconds: uptime,
            physicalMemoryGiB: gibRounded
        )
    }

    /// Render the single-line representation that the terminal paints.
    /// Format: `[YYYY-MM-DD HH:MM:SS UTC] up HH:MM:SS · mem N.N GiB`.
    /// UTC on purpose — local time would make snapshot tests flaky and
    /// the terminal aesthetic is server-room, not desk-clock.
    public static func formattedLine(_ stats: LifeSystemStats) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: stats.now)
        let up = formatUptime(stats.uptimeSeconds)
        let mem = String(format: "%.1f", stats.physicalMemoryGiB)
        return "[\(stamp) UTC] up \(up) · mem \(mem) GiB"
    }

    private static func formatUptime(_ seconds: Int) -> String {
        let s = seconds % 60
        let m = (seconds / 60) % 60
        let h = seconds / 3600
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
