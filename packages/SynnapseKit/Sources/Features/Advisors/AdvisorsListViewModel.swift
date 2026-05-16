import Foundation
import Observation
import Models
import Networking

public enum AdvisorsListState: Sendable, Equatable {
    case idle
    case loading
    case ready([Advisor])
    case error(String)
}

/// Drives the top-level Advisors list. On macOS the result feeds the
/// sidebar; on iOS it feeds the nav-stack root. The selected advisor
/// drives a `StreamingChatViewModel` lazily.
@MainActor
@Observable
public final class AdvisorsListViewModel {
    public private(set) var state: AdvisorsListState = .idle
    public var selectedAdvisorId: String?

    private let api: AdvisorsAPI

    public init(api: AdvisorsAPI) {
        self.api = api
    }

    public func refresh() async {
        state = .loading
        do {
            let advisors = try await api.list()
            state = .ready(advisors)
            // Auto-select the first advisor on macOS so the chat pane
            // isn't empty on first load. iOS leaves selection nil — the
            // nav stack opens chat on tap.
            if selectedAdvisorId == nil, let first = advisors.first {
                selectedAdvisorId = first.id
            }
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func select(advisorId: String?) {
        selectedAdvisorId = advisorId
    }

    public var advisors: [Advisor] {
        if case .ready(let list) = state { return list }
        return []
    }

    public var selectedAdvisor: Advisor? {
        guard let id = selectedAdvisorId else { return nil }
        return advisors.first(where: { $0.id == id })
    }

    public func chatViewModel(for advisor: Advisor) -> StreamingChatViewModel {
        StreamingChatViewModel(api: api, advisor: advisor)
    }

    /// Test seam — drop a deterministic state in for snapshot rendering
    /// without requiring a network round-trip.
    public func injectForSnapshots(state: AdvisorsListState, selectedAdvisorId: String? = nil) {
        self.state = state
        if let selectedAdvisorId {
            self.selectedAdvisorId = selectedAdvisorId
        }
    }
}
