import Foundation
import Observation
import Models

/// A frozen snapshot of the substrate sources `ActivityComposer` consumes.
/// Lifted into its own type so the view model can be driven by either the
/// live store-backed source or a closure-backed fake in tests.
public struct ActivitySnapshot: Sendable, Equatable {
    public let transactions: [Transaction]
    public let recurrings: [Recurring]
    public let signals: [ProactiveSignal]
    public let digests: [LifeEntry]

    public init(
        transactions: [Transaction],
        recurrings: [Recurring],
        signals: [ProactiveSignal],
        digests: [LifeEntry] = []
    ) {
        self.transactions = transactions
        self.recurrings = recurrings
        self.signals = signals
        self.digests = digests
    }
}

/// Pluggable producer of `ActivitySnapshot`s. The live implementation
/// lives in `AppLifecycle` (it talks to the @ModelActor stores plus
/// `LifeAPI`); the test target injects a closure-backed fake.
public protocol ActivitySource: Sendable {
    func snapshot(now: Date) async -> ActivitySnapshot
}

public enum ActivityFilter: String, Sendable, Hashable, CaseIterable {
    case all
    case transactions
    case bills
    case insights
    case warnings

    public var label: String {
        switch self {
        case .all:          return "All"
        case .transactions: return "Transactions"
        case .bills:        return "Bills"
        case .insights:     return "Insights"
        case .warnings:     return "Anomalies"
        }
    }

    func matches(_ kind: LifeEntryKind) -> Bool {
        switch self {
        case .all:          return true
        case .transactions: return kind == .transaction
        case .bills:        return kind == .bill
        case .insights:     return kind == .insight || kind == .digest || kind == .streak
        case .warnings:     return kind == .warning
        }
    }
}

/// Where a tapped entry should jump to. The shell observes this via the
/// view's `onOpenRoute` callback and resolves it into a concrete
/// navigation action — Activity itself stays decoupled from the router.
public enum ActivityRoute: Sendable, Equatable {
    case openTransaction(id: String)
    case openRecurring(id: String)
    case openSignal(id: String)
    case openInbox
}

public enum ActivityState: Sendable, Equatable {
    case idle
    case loading
    case ready([ActivityComposer.DayBucket])
    case error(String)
}

@MainActor
@Observable
public final class ActivityViewModel {

    public private(set) var state: ActivityState = .idle
    public private(set) var selected: ActivityFilter = .all
    public private(set) var lastSnapshot: ActivitySnapshot?

    private let source: ActivitySource
    private let now: @MainActor () -> Date
    private let calendar: Calendar

    public init(
        now: @escaping @MainActor () -> Date = { Date() },
        source: ActivitySource,
        calendar: Calendar = .current
    ) {
        self.now = now
        self.source = source
        self.calendar = calendar
    }

    public func load() async {
        state = .loading
        let snap = await source.snapshot(now: now())
        lastSnapshot = snap
        recompute()
    }

    public func refresh() async {
        await load()
    }

    public func select(_ filter: ActivityFilter) {
        selected = filter
        recompute()
    }

    public static func route(for entry: LifeEntry) -> ActivityRoute? {
        switch entry.kind {
        case .transaction:
            if let id = entry.metadata?["txnId"] { return .openTransaction(id: id) }
            return nil
        case .bill:
            if let id = entry.metadata?["recurringId"] { return .openRecurring(id: id) }
            if let id = entry.metadata?["subjectId"]   { return .openRecurring(id: id) }
            return nil
        case .warning:
            if let id = entry.metadata?["subjectId"], !id.isEmpty {
                return .openTransaction(id: id)
            }
            return .openInbox
        case .insight, .digest, .streak:
            return .openInbox
        case .boot, .unknown:
            return nil
        }
    }

    private func recompute() {
        guard let snap = lastSnapshot else { return }
        let composed = ActivityComposer.compose(
            transactions: snap.transactions,
            recurrings: snap.recurrings,
            signals: snap.signals,
            digests: snap.digests,
            now: now()
        )
        let filtered = composed.filter { selected.matches($0.kind) }
        state = .ready(ActivityComposer.groupByDay(filtered, calendar: calendar))
    }
}
