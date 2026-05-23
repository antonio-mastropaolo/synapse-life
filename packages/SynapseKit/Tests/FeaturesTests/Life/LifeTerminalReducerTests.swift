import Foundation
import Testing
@testable import Models
@testable import Features

private func entry(
    _ id: String,
    _ secondsSinceEpoch: TimeInterval,
    _ kind: LifeEntryKind,
    _ text: String
) -> LifeEntry {
    LifeEntry(
        id: id,
        timestamp: Date(timeIntervalSince1970: secondsSinceEpoch),
        kind: kind,
        text: text
    )
}

// Epoch anchors (all UTC):
//   2026-05-16 14:00:00 = 1_778_940_000
//   2026-05-16 14:01:00 = 1_778_940_060
//   2026-05-16 14:03:00 = 1_778_940_180
//   2026-05-15 23:50:00 = 1_778_889_000
//   2026-05-16 00:10:00 = 1_778_890_200

@Suite("LifeTerminalReducer")
struct LifeTerminalReducerTests {

    @Test
    func ordersNewestAtBottom() {
        // Three entries in non-chronological input order. The reducer uses
        // a UTC calendar by default so this assertion does not race the
        // test host's local zone.
        let entries: [LifeEntry] = [
            entry("c", 1_778_940_180, .transaction, "C"),
            entry("a", 1_778_940_000, .transaction, "A"),
            entry("b", 1_778_940_060, .transaction, "B")
        ]
        let lines = LifeReducer.linesFromEntries(entries, columns: 80)
        let heads = lines.filter { $0.role == .entryHead }
        // Bottom is newest, top is oldest.
        #expect(heads.map(\.entryId) == ["a", "b", "c"])
    }

    @Test
    func insertsDayBandBetweenDays() {
        // 2026-05-15 23:50Z and 2026-05-16 00:10Z — different UTC days.
        let entries: [LifeEntry] = [
            entry("late",    1_778_889_000, .transaction, "Late night charge"),
            entry("morning", 1_778_890_200, .transaction, "Morning charge")
        ]
        let lines = LifeReducer.linesFromEntries(entries, columns: 80)
        let separators = lines.filter { $0.role == .daySeparator }
        #expect(separators.count == 1)
        // The separator names the *new* day.
        #expect(separators.first?.text.contains("2026-05-16") == true)
        // Ordering: late entry, separator, morning entry.
        #expect(lines.map(\.role) == [.entryHead, .daySeparator, .entryHead])
    }

    @Test
    func wrapsLongEntriesPreservingIndent() {
        let body = "abcdefghij " + String(repeating: "longword ", count: 6)
        let lines = LifeReducer.linesFromEntries(
            [entry("e", 1_778_940_000, .insight, body)],
            columns: 40
        )
        let heads = lines.filter { $0.role == .entryHead }
        let wraps = lines.filter { $0.role == .entryWrap }
        #expect(heads.count == 1)
        #expect(wraps.count >= 1)
        // Wrap lines start with an indent block (timestamp/glyph columns blanked).
        for w in wraps {
            #expect(w.text.hasPrefix("        "))
        }
        // Every line must fit within the column budget.
        for line in lines {
            #expect(line.text.count <= 40)
        }
    }

    @Test
    func emptyInputProducesNoLines() {
        #expect(LifeReducer.linesFromEntries([], columns: 80).isEmpty)
    }

    @Test
    func viewportFiltersOutOfRangeEntries() {
        let entries: [LifeEntry] = [
            entry("old", 1_778_800_000, .transaction, "old"),
            entry("in",  1_778_940_000, .transaction, "in window"),
            entry("new", 1_779_100_000, .transaction, "future")
        ]
        let viewport = LifeReducer.Viewport(
            start: Date(timeIntervalSince1970: 1_778_900_000),
            end:   Date(timeIntervalSince1970: 1_779_000_000),
            now:   Date(timeIntervalSince1970: 1_778_940_000)
        )
        let lines = LifeReducer.linesFromEntries(entries, viewport: viewport, columns: 80)
        let heads = lines.filter { $0.role == .entryHead }
        #expect(heads.count == 1)
        #expect(heads.first?.entryId == "in")
    }

    @Test
    func headLineHasTimestampAndGlyph() {
        let lines = LifeReducer.linesFromEntries(
            [entry("e", 1_778_940_000, .transaction, "Whole Foods")],
            columns: 80
        )
        let head = lines.first
        #expect(head?.text.hasPrefix("14:00 $ Whole Foods") == true)
    }
}
