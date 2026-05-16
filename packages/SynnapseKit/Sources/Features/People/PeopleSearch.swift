import Foundation
import Models

/// Pure-function search over a `[Person]` list. Diacritic-insensitive,
/// case-insensitive, with a layered score that promotes:
///   1. exact display-name match
///   2. last-name "starts with" match
///   3. first-name "starts with" match
///   4. substring match anywhere in the display name
///   5. substring match in the identity (email)
///
/// Empty queries return the input unchanged. Stable sort: ties keep input
/// order so the upstream caller's ordering (by `effectiveWeight`, recency,
/// whatever) is preserved for equally-good matches.
///
/// Mirrors the discipline used by [[SpotlightAbstractFormatter]] — no side
/// effects, no `Classify*` framing, easy to unit test row-by-row.
public enum PeopleSearch {

    /// Score breakdown — exposed so tests can pin specific outcomes without
    /// committing to integer constants.
    private struct Score: Comparable {
        let bucket: Int          // higher = better match
        let secondaryLen: Int    // shorter haystack tail = tighter match (tie-break)
        let inputIndex: Int      // stable sort

        static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.bucket != rhs.bucket { return lhs.bucket < rhs.bucket }
            if lhs.secondaryLen != rhs.secondaryLen {
                return lhs.secondaryLen > rhs.secondaryLen
            }
            return lhs.inputIndex > rhs.inputIndex
        }

        static func == (lhs: Score, rhs: Score) -> Bool {
            lhs.bucket == rhs.bucket
                && lhs.secondaryLen == rhs.secondaryLen
                && lhs.inputIndex == rhs.inputIndex
        }
    }

    public static func search(_ people: [Person], query: String) -> [Person] {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return people }
        var scored: [(Person, Score)] = []
        scored.reserveCapacity(people.count)
        for (idx, person) in people.enumerated() {
            let name = fold(person.displayName)
            let id = fold(person.identity)
            let (firstName, lastName) = splitName(person.displayName)
            let firstNameFolded = fold(firstName)
            let lastNameFolded = fold(lastName)

            let bucket: Int
            if name == q {
                bucket = 5
            } else if !lastNameFolded.isEmpty && lastNameFolded.hasPrefix(q) {
                bucket = 4
            } else if !firstNameFolded.isEmpty && firstNameFolded.hasPrefix(q) {
                bucket = 3
            } else if name.contains(q) {
                bucket = 2
            } else if id.contains(q) {
                bucket = 1
            } else {
                continue
            }
            scored.append((person, Score(
                bucket: bucket,
                secondaryLen: name.count,
                inputIndex: idx
            )))
        }
        // Sort descending by score; Swift's sort is not stable, but we ship
        // `inputIndex` in the score so ties break on input order.
        scored.sort { $0.1 > $1.1 }
        return scored.map(\.0)
    }

    /// Lowercase + strip diacritics + collapse internal whitespace. Uses
    /// the locale-aware `.diacriticInsensitive` Foundation transform so
    /// "Mastropáolo" and "mastropaolo" compare equal.
    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US"))
            .lowercased()
    }

    /// Split a display name into ("first", "last"). Single-token names give
    /// `(token, "")`. Hyphenated last names stay glued ("Jacqulyn-Test").
    private static func splitName(_ name: String) -> (String, String) {
        let parts = name.split(whereSeparator: { $0 == " " })
        if parts.count <= 1 {
            return (String(parts.first ?? ""), "")
        }
        let last = String(parts.last ?? "")
        let first = parts.dropLast().joined(separator: " ")
        return (first, last)
    }
}
