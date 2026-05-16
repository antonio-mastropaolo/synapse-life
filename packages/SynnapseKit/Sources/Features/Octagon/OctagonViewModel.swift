import Foundation
import Observation
import Models
import Networking

public enum OctagonListState: Sendable, Equatable {
    case idle
    case loading
    case ready([MembershipCard])
    case empty
    case error(String)
}

/// Drives the Octagon surface — recurring memberships down the left side
/// and a per-vendor inspector panel on the right (macOS) / bottom sheet
/// (iOS). Vendor intel is fetched lazily when a row is selected; the
/// inspector keeps its own state machine so the list never re-renders
/// while a brief is loading.
@MainActor
@Observable
public final class OctagonViewModel {
    public private(set) var state: OctagonListState = .idle
    public private(set) var inspector: InspectorState = .closed
    public var selectedVendor: String?
    /// Paging — toggled to `true` once `loadMore()` confirms no further
    /// cursor was returned.
    public private(set) var reachedEnd: Bool = false

    public enum InspectorState: Sendable, Equatable {
        case closed
        case loading(vendor: String)
        case ready(OctagonVendor)
        case error(vendor: String, message: String)
    }

    private let api: OctagonAPI
    private var cursor: String?
    /// Per-vendor cache — never invalidated within the session; the
    /// server already caches 24h.
    private var briefCache: [String: OctagonVendor] = [:]
    private var inspectorTask: Task<Void, Never>?

    public init(api: OctagonAPI) {
        self.api = api
    }

    public func refresh() async {
        state = .loading
        cursor = nil
        reachedEnd = false
        do {
            let response = try await api.memberships(cursor: nil)
            cursor = response.nextCursor
            reachedEnd = response.nextCursor == nil
            state = response.memberships.isEmpty
                ? .empty
                : .ready(response.memberships)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func loadMore() async {
        guard !reachedEnd else { return }
        guard let cursor else {
            reachedEnd = true
            return
        }
        do {
            let response = try await api.memberships(cursor: cursor)
            let existing: [MembershipCard]
            if case .ready(let rows) = state {
                existing = rows
            } else {
                existing = []
            }
            let merged = existing + response.memberships
            self.cursor = response.nextCursor
            self.reachedEnd = response.nextCursor == nil
            state = merged.isEmpty ? .empty : .ready(merged)
        } catch {
            // Pagination failures are non-fatal — keep what we have and
            // let the user retry on the next scroll-tail trigger.
        }
    }

    public func select(vendor: String?) {
        selectedVendor = vendor
        guard let vendor else {
            inspectorTask?.cancel()
            inspectorTask = nil
            inspector = .closed
            return
        }
        if let cached = briefCache[vendor] {
            inspector = .ready(cached)
            return
        }
        inspector = .loading(vendor: vendor)
        inspectorTask?.cancel()
        let api = self.api
        inspectorTask = Task { [weak self] in
            do {
                let brief = try await api.brief(vendor: vendor)
                if Task.isCancelled { return }
                await self?.applyBrief(brief, for: vendor)
            } catch {
                if Task.isCancelled { return }
                await self?.applyBriefError(vendor: vendor, error: error)
            }
        }
    }

    private func applyBrief(_ brief: OctagonVendor, for vendor: String) {
        // Cache by **selection key**, not by the brief's vendor name —
        // the server may normalize "Whole Foods" → "Whole Foods Market"
        // and we still want a subsequent select for "Whole Foods" to
        // resolve from cache.
        briefCache[vendor] = brief
        // Only paint the brief if it's still the active selection. The
        // user may have moved on while the brief was in flight.
        if selectedVendor == vendor {
            inspector = .ready(brief)
        }
    }

    private func applyBriefError(vendor: String, error: Error) {
        if selectedVendor == vendor {
            inspector = .error(vendor: vendor, message: String(describing: error))
        }
    }

    public var memberships: [MembershipCard] {
        if case .ready(let rows) = state { return rows }
        return []
    }

    // MARK: - Test seams

    public func injectForSnapshots(
        state: OctagonListState,
        inspector: InspectorState = .closed,
        selectedVendor: String? = nil
    ) {
        self.state = state
        self.inspector = inspector
        self.selectedVendor = selectedVendor
    }
}
