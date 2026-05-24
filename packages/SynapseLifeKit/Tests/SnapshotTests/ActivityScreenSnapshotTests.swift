import Foundation
import SwiftUI
import Testing
import SnapshotTesting
@testable import Models
@testable import Features
@testable import DesignSystem

#if os(macOS)
import AppKit

@Suite("ActivityScreenSnapshot")
@MainActor
struct ActivityScreenSnapshotTests {

    private let now = Date(timeIntervalSince1970: 1_716_120_000)

    private func tx(_ id: String, daysAgo: Int, merchant: String, category: String = "food") -> Models.Transaction {
        Models.Transaction(
            id: id,
            accountId: "acc",
            accountName: "Checking",
            amount: -12,
            currency: "USD",
            date: Date(timeInterval: TimeInterval(-daysAgo) * 86_400, since: now),
            name: merchant,
            merchantName: merchant,
            category: .knownCategory(category),
            subcategory: nil,
            pending: false
        )
    }

    private func bill(_ id: String, merchant: String, daysAhead: Int) -> Recurring {
        Recurring(
            id: id,
            merchant: merchant,
            category: "subscriptions",
            medianAmount: 9.99,
            cadenceDays: 30,
            lastSeen: Date(timeInterval: -30 * 86_400, since: now),
            predictedNext: Date(timeInterval: TimeInterval(daysAhead) * 86_400, since: now),
            occurrenceCount: 4,
            confidence: 0.9,
            transactionIds: [],
            isIncome: false
        )
    }

    private func signal(_ id: String, kind: ProactiveSignal.Kind, headline: String, severity: ProactiveSignal.Severity) -> ProactiveSignal {
        ProactiveSignal(
            id: id,
            kind: kind,
            headline: headline,
            body: "Detected via the proactive analyzer.",
            subjectId: nil,
            date: now,
            severity: severity
        )
    }

    private func populatedVM() -> ActivityViewModel {
        let snap = ActivitySnapshot(
            transactions: [
                tx("t1", daysAgo: 0, merchant: "Sample Cafe", category: "food"),
                tx("t2", daysAgo: 0, merchant: "Sample Grocery", category: "groceries"),
                tx("t3", daysAgo: 1, merchant: "Sample Transit", category: "transport"),
                tx("t4", daysAgo: 3, merchant: "Sample Bookshop", category: "shopping")
            ],
            recurrings: [
                bill("r1", merchant: "Sample Streaming", daysAhead: 2),
                bill("r2", merchant: "Sample Gym", daysAhead: 5)
            ],
            signals: [
                signal("s1", kind: .anomalousSpend, headline: "Restaurants 2.3x typical week", severity: .alert),
                signal("s2", kind: .newRecurring, headline: "New recurring detected: Sample AI Subscription", severity: .info)
            ]
        )
        let vm = ActivityViewModel(
            now: { self.now },
            source: SnapshotActivitySource(snapshot: snap)
        )
        return vm
    }

    private func emptyVM() -> ActivityViewModel {
        let snap = ActivitySnapshot(transactions: [], recurrings: [], signals: [])
        return ActivityViewModel(now: { self.now }, source: SnapshotActivitySource(snapshot: snap))
    }

    private func hostMac(_ view: some View, scheme: ColorScheme,
                         width: CGFloat = 720, height: CGFloat = 820) -> NSView {
        let host = NSHostingView(rootView: AnyView(
            view
                .frame(width: width, height: height)
                .environment(\.colorScheme, scheme)
                .identity(.default)
        ))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test func populatedLightMac() async throws {
        let vm = populatedVM()
        await vm.load()
        let view = ActivityView(viewModel: vm)
        assertSnapshot(of: hostMac(view, scheme: .light), as: .image,
                       named: "activity.populated.light.mac")
    }

    @Test func populatedDarkMac() async throws {
        let vm = populatedVM()
        await vm.load()
        let view = ActivityView(viewModel: vm)
        assertSnapshot(of: hostMac(view, scheme: .dark), as: .image,
                       named: "activity.populated.dark.mac")
    }

    @Test func emptyMac() async throws {
        let vm = emptyVM()
        await vm.load()
        let view = ActivityView(viewModel: vm)
        assertSnapshot(of: hostMac(view, scheme: .dark), as: .image,
                       named: "activity.empty.dark.mac")
    }
}

private struct SnapshotActivitySource: ActivitySource {
    let snapshot: ActivitySnapshot
    func snapshot(now: Date) async -> ActivitySnapshot { snapshot }
}

#endif
