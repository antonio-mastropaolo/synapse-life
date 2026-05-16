import Foundation
import Observation
import Models

public enum SpotlightState: Sendable, Equatable {
    case idle
    case loading
    case results([SpotlightItem])
    case empty
    case error(String)
}

@MainActor
@Observable
public final class SpotlightViewModel {
    public var query: String = ""
    public private(set) var state: SpotlightState = .idle
    public private(set) var selected: SpotlightItem?

    private let api: SpotlightAPI
    private let scope: SpotlightScope?
    private let debounce: Duration
    private var fetchTask: Task<Void, Never>?

    public init(
        api: SpotlightAPI,
        scope: SpotlightScope? = nil,
        debounce: Duration = .milliseconds(150)
    ) {
        self.api = api
        self.scope = scope
        self.debounce = debounce
    }

    public func setQuery(_ q: String) {
        query = q
        fetchTask?.cancel()
        fetchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
            await self?.runFetch()
        }
    }

    public func refresh() async {
        fetchTask?.cancel()
        await runFetch()
    }

    public func select(_ item: SpotlightItem) {
        selected = item
    }

    public func clearSelection() {
        selected = nil
    }

    private func runFetch() async {
        state = .loading
        do {
            let response = try await api.list(scope: scope, cursor: nil, ifNoneMatch: nil)
            if Task.isCancelled { return }
            let items = response.page?.events ?? []
            // Client-side filter for the search box. Server-side filter is a
            // M3 task once the server route grows a `q` param.
            let filtered = query.isEmpty
                ? items
                : items.filter { matches($0, query: query) }
            if filtered.isEmpty {
                state = .empty
            } else {
                state = .results(filtered)
            }
        } catch is CancellationError {
            return
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func matches(_ item: SpotlightItem, query: String) -> Bool {
        let needle = query.lowercased()
        if item.summary?.lowercased().contains(needle) == true { return true }
        if item.issueLabel?.lowercased().contains(needle) == true { return true }
        if item.message.subject.lowercased().contains(needle) { return true }
        if let top = item.topCandidate(),
           top.title.lowercased().contains(needle) { return true }
        return false
    }
}
