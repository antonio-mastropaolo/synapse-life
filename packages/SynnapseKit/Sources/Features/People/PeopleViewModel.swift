import Foundation
import Observation
import Models
import Networking

public enum PeopleState: Sendable, Equatable {
    case idle
    case loading
    case results([Person])
    case empty
    case error(String)
}

/// View model for the People surface. Holds the current state machine,
/// search text + debounced application, and the currently selected person
/// (drives the dossier sheet on iOS / the inspector pane on macOS).
@MainActor
@Observable
public final class PeopleViewModel {

    public private(set) var state: PeopleState = .idle
    public private(set) var people: [Person] = []
    public var selected: Person?
    public private(set) var searchText: String = ""
    public private(set) var visiblePeople: [Person] = []
    public private(set) var lastDossier: PersonDossier?
    public private(set) var dossierError: String?

    private let api: PeopleAPI
    private let debounce: Duration
    private var debounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    /// Monotonic epoch used to discard stale debounced writes. Every
    /// `queueSearch` call bumps this; only the task that owns the bumped
    /// value is allowed to apply its result. Cancellation is cooperative in
    /// Swift, so `Task.cancel()` alone is not a reliable guard.
    private var searchEpoch: UInt64 = 0

    public init(api: PeopleAPI, debounce: Duration = .milliseconds(120)) {
        self.api = api
        self.debounce = debounce
    }

    public func refresh() async {
        fetchTask?.cancel()
        await runFetch()
    }

    public func select(_ person: Person) {
        selected = person
    }

    public func clearSelection() {
        selected = nil
        lastDossier = nil
        dossierError = nil
    }

    /// Synchronous pure-function search — exposed so tests can pin matching
    /// without going through the debouncer.
    public func applySearch(_ query: String) -> [Person] {
        PeopleSearch.search(people, query: query)
    }

    /// Searchable-binding entry point. Each keystroke calls this; the
    /// debounce window collapses bursts into a single `visiblePeople` write.
    public func queueSearch(_ query: String) {
        searchText = query
        searchEpoch &+= 1
        let epoch = searchEpoch
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard let self else { return }
            await self.applyDebouncedSearch(query, epoch: epoch)
        }
    }

    /// Apply a debounced search query, but only if no fresher `queueSearch`
    /// call has bumped the epoch since this task was kicked off.
    private func applyDebouncedSearch(_ query: String, epoch: UInt64) {
        guard epoch == searchEpoch else { return }
        visiblePeople = applySearch(query)
    }

    /// Fetch the dossier for the currently selected person. Folds the result
    /// into `lastDossier` and any error into `dossierError`.
    public func loadDossier(for identity: String) async {
        dossierError = nil
        do {
            lastDossier = try await api.dossier(for: identity)
        } catch {
            dossierError = String(describing: error)
        }
    }

    /// Deterministic state for snapshot tests / previews.
    public func injectForSnapshots(state: PeopleState, people: [Person]) {
        self.state = state
        self.people = people
        self.visiblePeople = people
    }

    private func runFetch() async {
        state = .loading
        do {
            let response = try await api.list(ifNoneMatch: nil)
            if Task.isCancelled { return }
            if let people = response.people {
                self.people = people
                self.visiblePeople = people
            }
            state = people.isEmpty ? .empty : .results(people)
        } catch is CancellationError {
            return
        } catch {
            state = .error(String(describing: error))
        }
    }
}
