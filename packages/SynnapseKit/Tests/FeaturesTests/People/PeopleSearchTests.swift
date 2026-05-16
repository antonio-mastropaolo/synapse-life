import Foundation
import Testing
@testable import Models
@testable import Features

/// Pure-function tests for [[PeopleSearch]]. Search must be diacritic-
/// insensitive, last-name-first ordered, and exact matches must outrank
/// substring matches.
@Suite("PeopleSearch (diacritic-insensitive, last-name-first)")
struct PeopleSearchTests {

    private func person(_ identity: String, _ name: String) -> Person {
        Person(
            identity: identity, displayName: name,
            importanceWeight: 0.5, autoBoost: 0.0, effectiveWeight: 0.5,
            blacklisted: false, notes: nil,
            totalMessages: 0, firstSeen: nil, lastSeen: nil,
            distinctThreads: 0, awaitingMyReply: 0, openActions: 0,
            sources: [], avgImportance: 0.0,
            avatarURL: nil, avatarStatus: nil, kind: .person
        )
    }

    @Test
    func emptyQueryReturnsAllPreservingInputOrder() {
        let input = [
            person("a@x.io", "Antonio Mastropaolo"),
            person("b@x.io", "Jacqulyn Ledger")
        ]
        let out = PeopleSearch.search(input, query: "")
        #expect(out.map(\.identity) == ["a@x.io", "b@x.io"])
    }

    @Test
    func diacriticInsensitiveMatchByLastName() {
        // The user's literal display name in our address book carries the
        // diacritical mark `Mastropáolo` (the dictionary form). Operators
        // type their searches without the diacritic.
        let input = [
            person("antonio@x.io", "antonio mastropáolo"),
            person("jules@x.io", "jules ferré"),
            person("smith@x.io", "John Smith")
        ]
        let q = "mastropaolo"
        let out = PeopleSearch.search(input, query: q)
        #expect(out.first?.identity == "antonio@x.io")
    }

    @Test
    func diacriticMatchAlsoWorksInReverseDirection() {
        // Operator's keyboard layout has the diacritic — the source data
        // doesn't. Either direction must hit.
        let input = [
            person("antonio@x.io", "Antonio Mastropaolo")
        ]
        let out = PeopleSearch.search(input, query: "mastropáolo")
        #expect(out.first?.identity == "antonio@x.io")
    }

    @Test
    func lastNameBeatsFirstNameWhenSubstringIsAmbiguous() {
        // Both "Jacqulyn Ledger" and "John Jacqulyn-Test" contain "jac" in
        // their name. The one where it lives in the LAST name comes first.
        let input = [
            person("jt@x.io", "John Jacqulyn-Test"),
            person("jl@x.io", "Jacqulyn Ledger")
        ]
        let out = PeopleSearch.search(input, query: "jac")
        // Both match. Last-name match (Jacqulyn-Test's last name contains
        // "jac" too — but Ledger's name `Jacqulyn` is the first name; here we
        // assert that order favors the row whose LAST token starts with the
        // query first, then the row whose first token starts with it.
        // John Jacqulyn-Test → last name "Jacqulyn-Test" starts with "jac".
        #expect(out.first?.identity == "jt@x.io")
    }

    @Test
    func exactDisplayNameMatchBeatsSubstring() {
        let input = [
            person("a@x.io", "Antonio Mastropaolo Junior"),
            person("b@x.io", "Antonio Mastropaolo")
        ]
        let out = PeopleSearch.search(input, query: "Antonio Mastropaolo")
        #expect(out.first?.identity == "b@x.io")
    }

    @Test
    func fullNameQueryMatchesBothFirstAndLast() {
        let input = [
            person("am@x.io", "Antonio Mastropáolo"),
            person("zz@x.io", "Zeta Zulu")
        ]
        let out = PeopleSearch.search(input, query: "antonio mastropaolo")
        #expect(out.map(\.identity) == ["am@x.io"])
    }

    @Test
    func identitySubstringMatchesAsFallback() {
        // Operator searches by the email handle, not display name.
        let input = [
            person("jled@wm.edu", "Jacqulyn Ledger"),
            person("amastropaolo@wm.edu", "Antonio Mastropaolo")
        ]
        let out = PeopleSearch.search(input, query: "jled")
        #expect(out.first?.identity == "jled@wm.edu")
    }

    @Test
    func nonMatchingQueryReturnsEmpty() {
        let input = [person("a@x.io", "Antonio M.")]
        #expect(PeopleSearch.search(input, query: "xyzzy").isEmpty)
    }

    @Test
    func caseInsensitiveByDefault() {
        let input = [person("a@x.io", "Antonio Mastropaolo")]
        let out = PeopleSearch.search(input, query: "ANTONIO")
        #expect(out.count == 1)
    }

    @Test
    func sortStableForEqualScores() {
        // Two equally-good substring matches: order must be preserved.
        let a = person("a@x.io", "Albert First")
        let b = person("b@x.io", "Albert Second")
        let out = PeopleSearch.search([a, b], query: "albert")
        #expect(out.map(\.identity) == ["a@x.io", "b@x.io"])
    }
}
