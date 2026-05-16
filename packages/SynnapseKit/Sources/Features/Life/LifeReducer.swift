import Foundation
import Models

/// One rendered line in the terminal.
///
/// The reducer turns `[LifeEntry]` into `[TerminalLine]`. Each line is the
/// exact text that should land on a single row of the monospaced grid plus
/// the styling kind that lets the renderer paint glyphs in `phosphorBright`
/// and body text in either `phosphorBright` or `phosphorDim` depending on
/// the role.
public struct TerminalLine: Sendable, Equatable, Identifiable {
    public let id: String
    public let role: Role
    public let text: String
    public let entryId: String?

    public init(id: String, role: Role, text: String, entryId: String?) {
        self.id = id
        self.role = role
        self.text = text
        self.entryId = entryId
    }

    public enum Role: String, Sendable, Equatable {
        /// Day separator between two adjacent days. Renders in `phosphorDim`.
        case daySeparator
        /// First (or only) line of an entry — includes the `HH:mm prefix glyph` block.
        case entryHead
        /// Continuation line of a wrapped entry — body indentation preserved.
        case entryWrap
    }
}

public enum LifeReducer {

    /// Format used for the per-line timestamp prefix.
    public static let timestampPrefixLength: Int = 5 // "HH:mm"

    /// Visible date range. The reducer keeps only entries whose timestamp
    /// falls inside the range, exclusive of `end` — terminal-style "show me
    /// the day". Pass `.distantPast ..< .distantFuture` to render everything.
    public struct Viewport: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public let now: Date

        public init(start: Date, end: Date, now: Date) {
            self.start = start
            self.end = end
            self.now = now
        }

        public static func all(now: Date = Date()) -> Viewport {
            Viewport(start: .distantPast, end: .distantFuture, now: now)
        }
    }

    /// Pure: `linesFromEntries(_:viewport:columns:)`.
    ///
    /// Ordering: newest-at-bottom (terminal style — new lines scroll up,
    /// matching the `timeline-day-bands.png` reference in the repo state).
    /// Day separators are inserted between every pair of adjacent days,
    /// with the date written as `── YYYY-MM-DD ──`.
    /// Wrapping: long entry bodies wrap to subsequent `.entryWrap` lines
    /// with their indentation preserved (timestamp/glyph columns blanked
    /// out so the body stays in a single visual column).
    public static func linesFromEntries(
        _ entries: [LifeEntry],
        viewport: Viewport = .all(),
        columns: Int = 80,
        calendar: Calendar = .gregorian(utc: true)
    ) -> [TerminalLine] {
        let filtered = entries.filter {
            $0.timestamp >= viewport.start && $0.timestamp < viewport.end
        }
        let sorted = filtered.sorted { $0.timestamp < $1.timestamp }

        // Width budget for the body. Prefix is "HH:mm G " = 5 + 1 + 1 + 1 = 8 chars.
        let prefixWidth = timestampPrefixLength + 1 + 1 + 1
        let bodyWidth = max(columns - prefixWidth, 16)
        let indent = String(repeating: " ", count: prefixWidth)

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "HH:mm"
        timestampFormatter.calendar = calendar
        timestampFormatter.timeZone = calendar.timeZone

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone

        var lines: [TerminalLine] = []
        var lastDay: DateComponents?

        for entry in sorted {
            let day = calendar.dateComponents([.year, .month, .day], from: entry.timestamp)
            if let last = lastDay, last != day {
                let dayText = dayFormatter.string(from: entry.timestamp)
                lines.append(TerminalLine(
                    id: "sep-\(dayText)",
                    role: .daySeparator,
                    text: "── \(dayText) ──",
                    entryId: nil
                ))
            }
            lastDay = day

            let ts = timestampFormatter.string(from: entry.timestamp)
            let head = "\(ts) \(entry.kind.glyph) "
            let wrapped = wrap(entry.text, width: bodyWidth)
            for (i, chunk) in wrapped.enumerated() {
                if i == 0 {
                    lines.append(TerminalLine(
                        id: "\(entry.id)-0",
                        role: .entryHead,
                        text: head + chunk,
                        entryId: entry.id
                    ))
                } else {
                    lines.append(TerminalLine(
                        id: "\(entry.id)-\(i)",
                        role: .entryWrap,
                        text: indent + chunk,
                        entryId: entry.id
                    ))
                }
            }
        }
        return lines
    }

    /// Word-wraps text into `width`-column chunks. Words longer than `width`
    /// are hard-broken so the column grid is never violated.
    static func wrap(_ text: String, width: Int) -> [String] {
        guard width > 0 else { return [text] }
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count <= width {
                current = candidate
                continue
            }
            if !current.isEmpty {
                lines.append(current)
                current = ""
            }
            // Word alone exceeds the width — hard break.
            var w = String(word)
            while w.count > width {
                let head = String(w.prefix(width))
                lines.append(head)
                w = String(w.dropFirst(width))
            }
            current = w
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }
}

extension Calendar {
    public static func gregorian(utc: Bool) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        if utc, let tz = TimeZone(identifier: "UTC") {
            c.timeZone = tz
        }
        return c
    }
}
