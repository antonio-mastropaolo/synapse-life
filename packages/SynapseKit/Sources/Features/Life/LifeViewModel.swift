import Foundation
import Observation
import SwiftUI
import Models
import Networking
import DesignSystem

public enum LifeState: Sendable, Equatable {
    case idle
    case loading
    case ready([LifeEntry])
    case error(String)
}

@MainActor
@Observable
public final class LifeViewModel {
    public private(set) var state: LifeState = .idle
    /// Whether the user is scroll-anchored at the tail of the buffer.
    /// `true` means new entries auto-scroll into view; `false` means the
    /// user is reading scrollback and we should not move their viewport.
    public var anchoredToTail: Bool = true
    public private(set) var currentRenderPath: LifeRenderPath = .shader

    /// Instant the view model was constructed. The system-stats line uses
    /// this as the "since app launch" anchor — stable for the lifetime of
    /// the LIFE scene, deterministic when injected via the snapshot seam.
    public let launchedAt: Date

    /// Whether the synapse-v2 server has stood up `/api/life/entries`.
    /// Surfaces to the boot banner so the closing line reads "feed online"
    /// only when both the contract is live AND the buffer is non-empty.
    public var serverContractLive: Bool

    private let api: LifeAPI

    public init(api: LifeAPI, launchedAt: Date = Date(), serverContractLive: Bool = false) {
        self.api = api
        self.launchedAt = launchedAt
        // If the API knows the server contract isn't live, mirror it
        // here so the boot banner doesn't lie about feed status. Callers
        // can still override via the parameter.
        if let live = api as? LiveLifeAPI {
            self.serverContractLive = live.serverContractLive
        } else {
            self.serverContractLive = serverContractLive
        }
    }

    public func updateRenderPath(accessibility: LifeAccessibilityEnvironment) {
        // Reduce Motion is the only flag that drops the shader path
        // entirely. Reduce Transparency and Increase Contrast suppress
        // effects inside the shader but keep the Metal path live —
        // they're rendering decisions, not rendering-path decisions.
        currentRenderPath = accessibility.reduceMotion ? .canvasFallback : .shader
    }

    public func refresh() async {
        state = .loading
        do {
            let response = try await api.entries(cursor: nil)
            state = .ready(response.entries)
        } catch {
            state = .error(String(describing: error))
        }
    }

    /// Appends new entries to the buffer. Preserves the user's scroll
    /// anchor: if `anchoredToTail` is `true`, the new entries are
    /// concatenated and the caller is expected to scroll to the bottom;
    /// if `false`, the entries are still appended but the caller must
    /// hold the viewport in place.
    public func append(_ newEntries: [LifeEntry]) {
        guard !newEntries.isEmpty else { return }
        switch state {
        case .ready(let existing):
            state = .ready(existing + newEntries)
        case .idle, .loading, .error:
            state = .ready(newEntries)
        }
    }

    /// Test-only seam for snapshot tests, mirroring the pattern used by
    /// `SpotlightViewModel.injectStateForSnapshots(_:)`.
    public func injectStateForSnapshots(_ state: LifeState) {
        self.state = state
    }
}
