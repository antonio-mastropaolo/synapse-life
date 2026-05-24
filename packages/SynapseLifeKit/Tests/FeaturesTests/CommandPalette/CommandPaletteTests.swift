import Foundation
import Testing
@testable import Features

@MainActor
@Suite("CommandPalette / fuzzyMatch")
struct CommandPaletteFuzzyMatchTests {

    @Test func emptyQueryReturnsZeroScore() {
        let r = fuzzyMatch(query: "", against: "Dashboard")
        #expect(r != nil)
        #expect(r?.score == 0)
        #expect(r?.indices.isEmpty == true)
    }

    @Test func emptyCandidateRejectsNonEmptyQuery() {
        #expect(fuzzyMatch(query: "ab", against: "") == nil)
    }

    @Test func exactPrefixMatchScoresHighestPath() {
        let prefix    = fuzzyMatch(query: "dash", against: "Dashboard")
        let scattered = fuzzyMatch(query: "dah",  against: "Dashboard")
        let nonPrefix = fuzzyMatch(query: "ash",  against: "Dashboard")
        #expect(prefix    != nil)
        #expect(scattered != nil)
        #expect(nonPrefix != nil)
        // Start-of-string + contiguous run beats scattered + non-prefix.
        #expect((prefix?.score ?? 0) > (scattered?.score ?? 0))
        #expect((prefix?.score ?? 0) > (nonPrefix?.score ?? 0))
    }

    @Test func returnsMatchedIndicesInOrder() {
        let r = fuzzyMatch(query: "dsb", against: "Dashboard")
        #expect(r != nil)
        let indices = r?.indices ?? []
        // Indices must be strictly ascending.
        for i in 1..<indices.count {
            #expect(indices[i] > indices[i - 1])
        }
    }

    @Test func caseInsensitive() {
        let lower = fuzzyMatch(query: "DASH", against: "Dashboard")
        let upper = fuzzyMatch(query: "dash", against: "DASHBOARD")
        #expect(lower != nil)
        #expect(upper != nil)
    }

    @Test func rejectsWhenCharsMissing() {
        #expect(fuzzyMatch(query: "xyz", against: "Dashboard") == nil)
        #expect(fuzzyMatch(query: "dax", against: "Dashboard") == nil)
    }
}

@MainActor
@Suite("CommandPalette / view model")
struct CommandPaletteViewModelTests {

    @Test func defaultItemsCoverCanonicalSidebarSurfaces() {
        let vm = CommandPaletteViewModel()
        let titles = vm.items.map(\.title)
        #expect(titles.contains("Dashboard"))
        #expect(titles.contains("Transactions"))
        #expect(titles.contains("Accounts"))
        #expect(titles.contains("Investments"))
        #expect(titles.contains("Advisors"))
        #expect(titles.contains("Activity"))
        #expect(titles.contains("Forecast"))
    }

    @Test func emptyQueryReturnsItemsInDeclaredOrder() {
        let vm = CommandPaletteViewModel()
        #expect(vm.filtered.map(\.id) == vm.items.map(\.id))
    }

    @Test func filteringRanksPrefixHigherThanScattered() {
        let vm = CommandPaletteViewModel()
        vm.query = "fo"
        let ids = vm.filtered.map(\.id)
        // "Forecast" prefix-matches; "Goals" does not match "fo" at
        // all, but several subtitles do. Forecast must lead.
        #expect(ids.first == "forecast")
    }

    @Test func filteringDropsItemsWithoutAMatch() {
        let vm = CommandPaletteViewModel()
        vm.query = "xqz"
        #expect(vm.filtered.isEmpty)
    }

    @Test func highlightNavigationWrapsAround() {
        let vm = CommandPaletteViewModel()
        vm.query = ""
        let n = vm.filtered.count
        #expect(n > 0)
        vm.highlightedIndex = 0
        vm.highlightPrevious()
        #expect(vm.highlightedIndex == n - 1)
        vm.highlightNext()
        #expect(vm.highlightedIndex == 0)
        vm.highlightNext()
        #expect(vm.highlightedIndex == 1)
    }

    @Test func highlightedItemTracksFilteredList() {
        let vm = CommandPaletteViewModel()
        vm.query = "dash"
        let first = vm.filtered.first
        #expect(first?.id == "dashboard")
        #expect(vm.highlightedItem?.id == first?.id)
    }

    @Test func resetClearsQueryAndHighlight() {
        let vm = CommandPaletteViewModel()
        vm.query = "for"
        vm.highlightedIndex = 3
        vm.reset()
        #expect(vm.query.isEmpty)
        #expect(vm.highlightedIndex == 0)
    }

    @Test func filteringHonorsSubtitleHitsAtLowerWeight() {
        // "inbox" appears in the Dashboard subtitle. A query of "inbox"
        // should still surface Dashboard rather than dropping it.
        let vm = CommandPaletteViewModel()
        vm.query = "inbox"
        let ids = vm.filtered.map(\.id)
        #expect(ids.contains("dashboard"))
    }
}
