import Foundation
import Testing
@testable import Features

/// `LifeSystemStats` is the data the live stats line reads from each
/// second. The provider is clock-injected so tests never touch the wall
/// clock — past failures in this codebase have come from tests that
/// depended on `Date()` and broke at midnight UTC.
@Suite("LifeSystemStats")
struct LifeSystemStatsTests {

    /// Anchor: 2026-05-17 12:34:56 UTC = 1_779_021_296.
    private let anchor = Date(timeIntervalSince1970: 1_779_021_296)

    @Test
    func snapshotCarriesInjectedNow() {
        let stats = LifeSystemStats.snapshot(
            now: anchor,
            launchedAt: anchor.addingTimeInterval(-3600),
            physicalMemoryBytes: 17_179_869_184  // 16 GiB
        )
        #expect(stats.now == anchor)
    }

    @Test
    func uptimeIsDifferenceBetweenNowAndLaunch() {
        let stats = LifeSystemStats.snapshot(
            now: anchor,
            launchedAt: anchor.addingTimeInterval(-125),
            physicalMemoryBytes: 17_179_869_184
        )
        #expect(stats.uptimeSeconds == 125)
    }

    @Test
    func memoryReportedInGibibytesRounded() {
        // 16 GiB → 16.0; 17.5 GiB → 17.5; round to one decimal.
        let stats = LifeSystemStats.snapshot(
            now: anchor,
            launchedAt: anchor,
            physicalMemoryBytes: Int64(17.5 * 1024 * 1024 * 1024)
        )
        #expect(stats.physicalMemoryGiB == 17.5)
    }

    @Test
    func renderedLineUsesUTCDateAndTime() {
        // The live stats line is a single row of monospaced text. It must
        // be deterministic for the same inputs so we can snapshot it.
        let stats = LifeSystemStats.snapshot(
            now: anchor,
            launchedAt: anchor.addingTimeInterval(-3661),  // 1h 1m 1s
            physicalMemoryBytes: 17_179_869_184  // 16 GiB
        )
        let line = LifeSystemStats.formattedLine(stats)
        // Format: "[YYYY-MM-DD HH:MM:SS UTC] up 01:01:01 · mem 16.0 GiB"
        #expect(line == "[2026-05-17 12:34:56 UTC] up 01:01:01 · mem 16.0 GiB")
    }

    @Test
    func uptimeBelowOneSecondClampsToZero() {
        // Negative or sub-second differences should report 00:00:00 rather
        // than a negative or NaN value. Defensive: clock skew on first
        // render can push `launchedAt` past `now` by a few microseconds.
        let stats = LifeSystemStats.snapshot(
            now: anchor,
            launchedAt: anchor.addingTimeInterval(0.5),
            physicalMemoryBytes: 17_179_869_184
        )
        #expect(stats.uptimeSeconds == 0)
        let line = LifeSystemStats.formattedLine(stats)
        #expect(line.contains("up 00:00:00"))
    }

    @Test
    func uptimeOverADayFormatsAsHoursNotDays() {
        // We never roll into a "days" segment — the terminal is a live
        // session indicator, not a server-uptime display. 25h is 25:00:00.
        let stats = LifeSystemStats.snapshot(
            now: anchor,
            launchedAt: anchor.addingTimeInterval(-25 * 3600),
            physicalMemoryBytes: 17_179_869_184
        )
        let line = LifeSystemStats.formattedLine(stats)
        #expect(line.contains("up 25:00:00"))
    }
}
