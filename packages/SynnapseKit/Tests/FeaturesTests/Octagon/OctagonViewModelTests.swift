import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

private func sampleMembership(id: String, vendor: String, monthly: Double) -> MembershipCard {
    MembershipCard(
        id: id,
        vendor: vendor,
        averageAmount: Decimal(string: String(monthly)) ?? Decimal(monthly),
        cadence: .monthly,
        nextPredictedAt: nil,
        lastSeenAt: nil,
        confidence: 0.95,
        status: .active
    )
}

private func sampleBrief(vendor: String) -> OctagonVendor {
    OctagonVendor(
        vendor: vendor,
        legalName: "\(vendor) Inc.",
        status: "private",
        yearFounded: 2020,
        employees: 250,
        hq: .init(city: "Cupertino", stateProvince: "CA", country: "US"),
        primaryIndustry: "Internet",
        verticals: ["consumer"],
        competitors: ["Foo", "Bar"],
        lastValuationUsdM: Decimal(1_500),
        lastValuationAt: nil,
        lastFinancing: .init(type: "Series B", sizeUsdM: Decimal(120), asOf: nil),
        vcRaisedUsdM: Decimal(300),
        revenueUsdM: Decimal(60),
        ceo: .init(name: "Founder X", email: nil),
        octagonUpdatedAt: nil
    )
}

@MainActor
@Suite("OctagonViewModel")
struct OctagonViewModelTests {

    @Test func startsIdleAndTransitionsToReady() async {
        let api = MockOctagonAPI()
        await api.setMemberships([
            sampleMembership(id: "m1", vendor: "Netflix", monthly: 15.49),
            sampleMembership(id: "m2", vendor: "Spotify", monthly: 10.99)
        ])
        let vm = OctagonViewModel(api: api)
        if case .idle = vm.state {} else {
            Issue.record("expected idle initial state")
        }
        await vm.refresh()
        if case .ready(let rows) = vm.state {
            #expect(rows.count == 2)
        } else {
            Issue.record("expected ready, got \(vm.state)")
        }
        #expect(vm.reachedEnd == true)
    }

    @Test func emptyResponseSurfacesEmptyState() async {
        let api = MockOctagonAPI()
        await api.setMemberships([])
        let vm = OctagonViewModel(api: api)
        await vm.refresh()
        if case .empty = vm.state {} else {
            Issue.record("expected empty, got \(vm.state)")
        }
    }

    @Test func loadMoreFollowsCursor() async {
        let api = MockOctagonAPI()
        await api.setMemberships(
            [sampleMembership(id: "m1", vendor: "A", monthly: 1)],
            nextCursor: "c2"
        )
        let vm = OctagonViewModel(api: api)
        await vm.refresh()
        #expect(vm.reachedEnd == false)
        // Second page lands when load-more fires.
        await api.setMemberships([
            sampleMembership(id: "m2", vendor: "B", monthly: 2)
        ])
        await vm.loadMore()
        if case .ready(let rows) = vm.state {
            #expect(rows.count == 2)
        } else {
            Issue.record("expected merged ready, got \(vm.state)")
        }
        #expect(vm.reachedEnd == true)
    }

    @Test func selectVendorOpensInspectorAndCachesBrief() async {
        let api = MockOctagonAPI()
        await api.setMemberships([sampleMembership(id: "m1", vendor: "Netflix", monthly: 1)])
        await api.setBrief(sampleBrief(vendor: "Netflix"))
        let vm = OctagonViewModel(api: api)
        await vm.refresh()
        vm.select(vendor: "Netflix")
        // Inspector flips to loading immediately, then to ready.
        if case .loading(let v) = vm.inspector {
            #expect(v == "Netflix")
        } else {
            Issue.record("expected loading, got \(vm.inspector)")
        }
        try? await waitFor(timeout: .seconds(1)) {
            if case .ready = vm.inspector { return true }
            return false
        }
        if case .ready(let brief) = vm.inspector {
            #expect(brief.vendor == "Netflix")
        } else {
            Issue.record("expected ready inspector, got \(vm.inspector)")
        }
        let firstCount = await api.briefCallCount
        // Re-selecting the same vendor must NOT issue another fetch.
        vm.select(vendor: nil)
        vm.select(vendor: "Netflix")
        try? await waitFor(timeout: .milliseconds(200)) {
            if case .ready = vm.inspector { return true }
            return false
        }
        let secondCount = await api.briefCallCount
        #expect(secondCount == firstCount)
    }

    @Test func selectNilClosesInspectorAndCancelsInflight() async {
        let api = MockOctagonAPI()
        await api.setBrief(sampleBrief(vendor: "X"))
        let vm = OctagonViewModel(api: api)
        vm.select(vendor: "X")
        vm.select(vendor: nil)
        if case .closed = vm.inspector {} else {
            Issue.record("expected closed, got \(vm.inspector)")
        }
    }

    @Test func selectionDuringInflightFetchIsRespectedOnLanding() async {
        let api = MockOctagonAPI()
        // Brief resolves but selection has changed by then.
        await api.setBrief(sampleBrief(vendor: "Netflix"))
        let vm = OctagonViewModel(api: api)
        vm.select(vendor: "Netflix")
        vm.select(vendor: "Spotify")  // user moved on
        try? await waitFor(timeout: .seconds(1)) {
            if case .loading = vm.inspector { return true }
            return false
        }
        // Inspector should be in loading-Spotify or already failed
        // (since mock returns Netflix brief regardless). Either way it
        // must NOT show Netflix's brief.
        if case .ready(let brief) = vm.inspector {
            #expect(brief.vendor != "Netflix")
        }
    }
}

@MainActor
private func waitFor(timeout: Duration, predicate: @escaping () async -> Bool) async throws {
    let start = ContinuousClock().now
    while ContinuousClock().now - start < timeout {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
}
