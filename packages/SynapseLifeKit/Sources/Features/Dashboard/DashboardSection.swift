import Foundation

/// One date bucket in the Dashboard inbox.
///
/// Copilot groups its review queue by calendar day with headers like
/// "May 15th". We keep the projection pure (a `[DashboardSection]`)
/// so the view's only job is rendering. The header `title` is computed
/// at projection time using the view model's calendar/locale; the view
/// never re-formats dates per row.
public struct DashboardSection: Sendable, Hashable, Identifiable {

    /// Stable identifier: start-of-day for the bucket. Matches the
    /// ordering the view renders sections in and survives entries
    /// being toggled in/out of the inbox.
    public let day: Date

    /// Display string for the section header. Pre-formatted (e.g.
    /// "May 15th") so the view does not own the date-format choice.
    public let title: String

    /// Entries in this bucket, newest-first within the day.
    public let entries: [DashboardEntry]

    public init(day: Date, title: String, entries: [DashboardEntry]) {
        self.day = day
        self.title = title
        self.entries = entries
    }

    public var id: Date { day }
}
