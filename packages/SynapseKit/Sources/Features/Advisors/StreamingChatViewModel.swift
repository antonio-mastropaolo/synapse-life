import Foundation
import Observation
import Models
import Networking

/// Drives one advisor chat thread. Owns the `messages` array the view
/// renders, including the **in-flight** assistant message whose `content`
/// mutates as deltas arrive. The view model is `@MainActor`-isolated so
/// SwiftUI sees consistent snapshots without locks; the underlying
/// `AsyncThrowingStream<ChatDelta, Error>` runs on a detached Task that
/// hops back to the main actor for each yield.
@MainActor
@Observable
public final class StreamingChatViewModel {

    public private(set) var messages: [ChatMessage] = []
    public private(set) var threadId: String?
    public private(set) var isStreaming: Bool = false
    public private(set) var lastError: String?

    public let advisor: Advisor
    public var composer: String = ""

    private let api: AdvisorsAPI
    private var activeTask: Task<Void, Never>?

    public init(api: AdvisorsAPI, advisor: Advisor) {
        self.api = api
        self.advisor = advisor
        self.threadId = advisor.lastThreadId
    }

    /// Send the composer's contents as a user message and begin streaming
    /// the assistant reply. No-op if a stream is already in flight (the
    /// view disables send while `isStreaming`).
    public func send() async {
        let trimmed = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        composer = ""
        let userMsg = ChatMessage(role: .user, content: trimmed)
        messages.append(userMsg)
        await beginStream(userMessage: trimmed)
    }

    /// Cancel any in-flight stream. Called by the view's `.onDisappear`
    /// so background tasks don't keep buffering after the user navigates
    /// away.
    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
        // Mark the trailing assistant message (if any is mid-stream) as
        // finalized so the caret stops blinking.
        if let last = messages.last, last.isStreaming {
            var updated = last
            updated.isStreaming = false
            messages[messages.count - 1] = updated
        }
    }

    private func beginStream(userMessage: String) async {
        let pending = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(pending)
        let pendingIndex = messages.count - 1
        isStreaming = true
        lastError = nil
        let stream = api.streamChat(
            advisorId: advisor.id,
            userMessage: userMessage,
            threadId: threadId
        )
        activeTask = Task { [weak self] in
            do {
                for try await delta in stream {
                    if Task.isCancelled { break }
                    await self?.apply(delta: delta, at: pendingIndex)
                    if case .done = delta { break }
                    if case .error = delta { break }
                }
                await self?.finalize(at: pendingIndex)
            } catch {
                await self?.surface(error: error, at: pendingIndex)
            }
        }
    }

    private func apply(delta: ChatDelta, at index: Int) {
        guard messages.indices.contains(index) else { return }
        switch delta {
        case .text(let chunk):
            var msg = messages[index]
            msg.content += chunk
            messages[index] = msg
        case .done(let newThreadId):
            if let newThreadId { self.threadId = newThreadId }
        case .error(let message):
            lastError = message
        }
    }

    private func finalize(at index: Int) {
        if messages.indices.contains(index) {
            var msg = messages[index]
            msg.isStreaming = false
            messages[index] = msg
        }
        isStreaming = false
        activeTask = nil
    }

    private func surface(error: Error, at index: Int) {
        // Cancellation is expected when the view disappears — don't
        // paint that as a failure.
        if let api = error as? APIError, api == .cancelled {
            finalize(at: index)
            return
        }
        if error is CancellationError {
            finalize(at: index)
            return
        }
        lastError = String(describing: error)
        finalize(at: index)
    }

    // MARK: - Test seams

    /// Replace the message list and threadId for snapshot rendering. The
    /// view will paint the result deterministically.
    public func injectForSnapshots(messages: [ChatMessage], isStreaming: Bool = false) {
        self.messages = messages
        self.isStreaming = isStreaming
    }
}
