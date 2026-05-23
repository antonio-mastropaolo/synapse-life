import Foundation
import Observation
import Models

/// One ranked suggestion in the command bar. Three kinds:
///   - `.surface` jumps to a named surface (Personal, Transactions...).
///   - `.savedQuery` populates the field with a curated NL question.
///   - `.askAdvisor` opens the advisor and pre-fills the composer.
public struct CommandSuggestion: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case surface(SurfaceTarget)
        case savedQuery
        case askAdvisor(advisorId: String)
    }

    public enum SurfaceTarget: String, Sendable, Hashable, CaseIterable {
        case personal
        case accounts
        case transactions
        case investments
        case life
        case advisors
        case settings

        public var label: String {
            switch self {
            case .personal:     return "Personal"
            case .accounts:     return "Accounts"
            case .transactions: return "Transactions"
            case .investments:  return "Investments"
            case .life:         return "Life"
            case .advisors:     return "Advisors"
            case .settings:     return "Settings"
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let label: String
    public let subtitle: String?

    public init(id: String, kind: Kind, label: String, subtitle: String? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.subtitle = subtitle
    }
}

@MainActor
@Observable
public final class CommandBarViewModel {

    public var query: String = "" {
        didSet { recomputeSuggestions() }
    }

    public private(set) var suggestions: [CommandSuggestion] = []
    public private(set) var streamingAnswer: String = ""
    public private(set) var isStreaming: Bool = false
    public private(set) var lastError: String?
    /// Set by `submit(...)` so a host can route on Enter. Cleared on
    /// every new submit.
    public private(set) var lastDispatched: CommandSuggestion?

    public var isPresented: Bool = false

    private let askAPI: AskAPI
    private let contextProvider: @MainActor () -> AskContext
    private let advisorIds: [String]
    private(set) var activeTask: Task<Void, Never>?

    public init(
        askAPI: AskAPI,
        advisorIds: [String] = [],
        contextProvider: @escaping @MainActor () -> AskContext
    ) {
        self.askAPI = askAPI
        self.advisorIds = advisorIds
        self.contextProvider = contextProvider
        recomputeSuggestions()
    }

    public func open() {
        isPresented = true
        recomputeSuggestions()
    }

    public func close() {
        isPresented = false
        cancelStream()
    }

    public func cancelStream() {
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
    }

    /// Apply a suggestion. Host observes `lastDispatched` to actually
    /// route (the VM has no opinion about which router to call).
    public func apply(_ suggestion: CommandSuggestion) {
        lastDispatched = suggestion
    }

    /// Submit the free-text query — start the streaming Ask response.
    public func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let snapshot = contextProvider()
        streamingAnswer = ""
        lastError = nil
        isStreaming = true
        let stream = askAPI.ask(question: trimmed, context: snapshot)
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

    // MARK: - Suggestions

    public static let savedQueries: [String] = [
        "How much did I spend on coffee this month?",
        "What is my net worth right now?",
        "Show my largest expense this week",
        "How long until my checking hits zero?"
    ]

    func recomputeSuggestions() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: [CommandSuggestion] = []

        // Surface jumps — rank by prefix match.
        let surfaces = CommandSuggestion.SurfaceTarget.allCases
        for surface in surfaces {
            let label = surface.label
            if q.isEmpty || label.lowercased().hasPrefix(q) || label.lowercased().contains(q) {
                out.append(CommandSuggestion(
                    id: "surface.\(surface.rawValue)",
                    kind: .surface(surface),
                    label: "Open \(label)",
                    subtitle: "Jump to \(label)"
                ))
            }
        }

        // Saved queries.
        for (idx, sq) in Self.savedQueries.enumerated() {
            if q.isEmpty || sq.lowercased().contains(q) {
                out.append(CommandSuggestion(
                    id: "saved.\(idx)",
                    kind: .savedQuery,
                    label: sq,
                    subtitle: "Ask Synapse"
                ))
            }
        }

        // Advisor invokes when query mentions "ask".
        if q.contains("ask") {
            for adv in advisorIds {
                out.append(CommandSuggestion(
                    id: "advisor.\(adv)",
                    kind: .askAdvisor(advisorId: adv),
                    label: "Ask \(adv) advisor",
                    subtitle: "Open chat"
                ))
            }
        }

        // Cap at 5 to keep the surface tight.
        suggestions = Array(out.prefix(5))
    }

    private func handle(delta: AskDelta) {
        switch delta {
        case .text(let s): streamingAnswer += s
        case .done: break
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

    // MARK: - Test seam

    public func injectForSnapshots(answer: String, isStreaming: Bool) {
        self.streamingAnswer = answer
        self.isStreaming = isStreaming
    }
}
