import Foundation
import Observation
import Models

/// A streaming Ask viewmodel that routes through `IntelligenceRouter`
/// (Apple Intelligence on-device or server fallback) and surfaces
/// citation chips as the answer arrives. Parallel to
/// `CommandBarViewModel` — the host can pick either depending on
/// whether it wants the Copilot-style command surface (with
/// suggestions) or the dedicated Ask sheet (richer answer + chips).
@MainActor
@Observable
public final class IntelligenceAskViewModel {
    public private(set) var streamingAnswer: String = ""
    public private(set) var isStreaming: Bool = false
    public private(set) var lastError: String?
    public private(set) var citations: [AskCitation] = []
    public private(set) var route: IntelligenceRoute

    public var query: String = ""

    private let router: IntelligenceRouter
    private let contextProvider: @MainActor () -> AskContext
    private var activeTask: Task<Void, Never>?

    public init(
        router: IntelligenceRouter,
        contextProvider: @escaping @MainActor () -> AskContext
    ) {
        self.router = router
        self.route = router.route
        self.contextProvider = contextProvider
    }

    public func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let snapshot = contextProvider()
        streamingAnswer = ""
        lastError = nil
        isStreaming = true
        // Citations are computed up-front from the snapshot — they
        // don't depend on what the model says, so they appear next to
        // the answer as soon as the first token lands.
        citations = AskCitationsExtractor.extract(question: trimmed, context: snapshot)
        let stream = router.stream(prompt: trimmed, context: snapshot)
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            do {
                for try await delta in stream {
                    if Task.isCancelled { break }
                    self?.handle(delta: delta)
                    if case .done = delta { break }
                }
                self?.finish()
            } catch {
                self?.fail(error: error)
            }
        }
    }

    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
    }

    private func handle(delta: IntelligenceDelta) {
        switch delta {
        case .text(let s): streamingAnswer += s
        case .done:        break
        case .error(let m): lastError = m
        }
    }

    private func finish() {
        isStreaming = false
        activeTask = nil
    }

    private func fail(error: Error) {
        if error is CancellationError {
            isStreaming = false
            return
        }
        lastError = String(describing: error)
        isStreaming = false
    }

    public func injectForSnapshots(answer: String, citations: [AskCitation], isStreaming: Bool) {
        self.streamingAnswer = answer
        self.citations = citations
        self.isStreaming = isStreaming
    }
}
