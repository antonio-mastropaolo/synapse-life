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

    private let api: LifeAPI

    public init(api: LifeAPI) {
        self.api = api
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
