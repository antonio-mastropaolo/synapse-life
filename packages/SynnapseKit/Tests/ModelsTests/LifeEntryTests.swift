import Foundation
import Testing
@testable import Models

@Suite("LifeEntry")
struct LifeEntryTests {

    @Test
    func decodesFromISOTimestamp() throws {
        let json = #"""
        {
          "id": "e1",
          "timestamp": "2026-05-16T14:03:00Z",
          "kind": "transaction",
          "text": "Whole Foods $42.18",
          "metadata": { "vendor": "Whole Foods" }
        }
        """#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(LifeEntry.self, from: json)
        #expect(entry.id == "e1")
        #expect(entry.kind == .transaction)
        #expect(entry.text == "Whole Foods $42.18")
        #expect(entry.metadata?["vendor"] == "Whole Foods")
        let expected = ISO8601DateFormatter().date(from: "2026-05-16T14:03:00Z")
        #expect(entry.timestamp == expected)
    }

    @Test
    func decodesFromEpochMilliseconds() throws {
        let json = #"""
        {
          "id": "e2",
          "timestamp": 1747407780000,
          "kind": "bill",
          "text": "Verizon due in 3 days"
        }
        """#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(LifeEntry.self, from: json)
        #expect(entry.kind == .bill)
        #expect(entry.timestamp == Date(timeIntervalSince1970: 1_747_407_780))
    }

    @Test
    func unrecognizedKindFallsBackToUnknown() throws {
        let json = #"""
        {
          "id": "e3",
          "timestamp": "2026-05-16T14:03:00Z",
          "kind": "wormhole",
          "text": "future-proof"
        }
        """#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(LifeEntry.self, from: json)
        #expect(entry.kind == .unknown)
        #expect(entry.kind.glyph == "-")
    }

    @Test
    func kindGlyphsAreStable() {
        // Locking the glyph mapping — terminal layout depends on a single
        // 1-char prefix per kind. Changing these is a visual contract break.
        #expect(LifeEntryKind.boot.glyph == "*")
        #expect(LifeEntryKind.transaction.glyph == "$")
        #expect(LifeEntryKind.bill.glyph == "!")
        #expect(LifeEntryKind.insight.glyph == ">")
        #expect(LifeEntryKind.digest.glyph == "#")
        #expect(LifeEntryKind.streak.glyph == "+")
        #expect(LifeEntryKind.warning.glyph == "?")
        #expect(LifeEntryKind.unknown.glyph == "-")
    }

    @Test
    func aliasKindsMapToCanonical() {
        #expect(LifeEntryKind(rawValue: "txn") == .transaction)
        #expect(LifeEntryKind(rawValue: "due") == .bill)
        #expect(LifeEntryKind(rawValue: "recurring") == .bill)
        #expect(LifeEntryKind(rawValue: "warn") == .warning)
        #expect(LifeEntryKind(rawValue: "alert") == .warning)
        #expect(LifeEntryKind(rawValue: "TRANSACTION") == .transaction)
    }
}
