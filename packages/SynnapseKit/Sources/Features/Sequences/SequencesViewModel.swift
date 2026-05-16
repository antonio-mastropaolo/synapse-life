import Foundation
import Observation
import Models
import Networking

public enum SequencesListState: Sendable, Equatable {
    case idle
    case loading
    case results([Sequence])
    case empty
    case error(String)
}

/// State for a single stage editor. The draft autosave is debounced — the
/// editor binds the live subject/body, and after `autosaveDebounce` of
/// inactivity the view model calls `upsertDraft` on the API.
public enum DraftSaveState: Sendable, Equatable {
    case clean
    case dirty
    case saving
    case saved
    case failed(String)
}

/// View model for the M9 Sequences surface. Lists sequences, exposes a
/// filter by [[SequenceStatus]], and drives the per-stage editor with a
/// debounced autosave against [[SequencesAPI]].
///
/// There is NO send action. The actual outbound queue runs on the server
/// (`POST /api/sequences/tick`). Per M9 hard constraint: "the native client
/// displays sequences and edits drafts."
@MainActor
@Observable
public final class SequencesViewModel {
    public private(set) var state: SequencesListState = .idle
    public var statusFilter: SequencesStatusFilter = .active
    public var selected: Sequence?
    public var selectedStageId: String?

    /// Local edit buffers keyed by stage id. Survive sequence re-fetches so
    /// the editor doesn't lose typing when the operator scrolls away.
    public private(set) var draftSubjects: [String: String] = [:]
    public private(set) var draftBodies: [String: String] = [:]
    public private(set) var draftStates: [String: DraftSaveState] = [:]

    /// Autosave debounce. Tests inject a tiny value; production uses 600ms.
    public let autosaveDebounce: Duration

    private let api: SequencesAPI
    private var listTask: Task<Void, Never>?
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private var etag: String?

    public init(api: SequencesAPI, autosaveDebounce: Duration = .milliseconds(600)) {
        self.api = api
        self.autosaveDebounce = autosaveDebounce
    }

    public func refresh() async {
        listTask?.cancel()
        await runFetch()
    }

    public func setStatusFilter(_ filter: SequencesStatusFilter) async {
        guard statusFilter != filter else { return }
        statusFilter = filter
        await refresh()
    }

    public func select(_ sequence: Sequence) {
        selected = sequence
        selectedStageId = sequence.activeStage?.id ?? sequence.stages.first?.id
        seedDraftBuffers(for: sequence)
    }

    public func selectStage(id: String) {
        selectedStageId = id
    }

    /// Push an edit into the buffer and arm the debounced autosave for this
    /// stage. Concurrent edits on different stages save independently.
    public func updateDraftSubject(stageId: String, value: String) {
        draftSubjects[stageId] = value
        markDirty(stageId)
        scheduleSave(stageId)
    }

    public func updateDraftBody(stageId: String, value: String) {
        draftBodies[stageId] = value
        markDirty(stageId)
        scheduleSave(stageId)
    }

    /// Test seam: flush any in-flight save on the given stage. Returns once
    /// the autosave task has completed.
    public func flushPendingSave(stageId: String) async {
        if let task = saveTasks[stageId] {
            await task.value
        }
    }

    /// Test seam: deterministic state injection for snapshot tests.
    public func injectForSnapshots(state: SequencesListState, selected: Sequence?) {
        self.state = state
        if let selected {
            self.selected = selected
            self.selectedStageId = selected.activeStage?.id ?? selected.stages.first?.id
            seedDraftBuffers(for: selected)
        }
    }

    public func draftSaveState(forStage id: String) -> DraftSaveState {
        draftStates[id] ?? .clean
    }

    public func draftSubject(forStage id: String) -> String {
        if let buffered = draftSubjects[id] { return buffered }
        return selected?.stages.first { $0.id == id }?.subject ?? ""
    }

    public func draftBody(forStage id: String) -> String {
        if let buffered = draftBodies[id] { return buffered }
        return selected?.stages.first { $0.id == id }?.body ?? ""
    }

    // MARK: - Private

    private func seedDraftBuffers(for sequence: Sequence) {
        for stage in sequence.stages {
            if draftSubjects[stage.id] == nil { draftSubjects[stage.id] = stage.subject }
            if draftBodies[stage.id] == nil { draftBodies[stage.id] = stage.body }
            if draftStates[stage.id] == nil { draftStates[stage.id] = .clean }
        }
    }

    private func markDirty(_ stageId: String) {
        draftStates[stageId] = .dirty
    }

    private func scheduleSave(_ stageId: String) {
        guard let sequenceId = selected?.id else { return }
        saveTasks[stageId]?.cancel()
        let debounce = autosaveDebounce
        saveTasks[stageId] = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            guard let self else { return }
            await self.performSave(sequenceId: sequenceId, stageId: stageId)
        }
    }

    private func performSave(sequenceId: String, stageId: String) async {
        let subject = draftSubjects[stageId] ?? ""
        let body = draftBodies[stageId] ?? ""
        draftStates[stageId] = .saving
        let delta = StageDraftDelta(
            sequenceId: sequenceId,
            stageId: stageId,
            subject: subject,
            body: body
        )
        do {
            _ = try await api.upsertDraft(delta)
            if Task.isCancelled { return }
            // Only flip to .saved if the buffers haven't changed during the
            // round trip — otherwise the next debounced save will land
            // shortly and we want to stay in .dirty.
            if (draftSubjects[stageId] ?? "") == subject,
               (draftBodies[stageId] ?? "") == body {
                draftStates[stageId] = .saved
            }
        } catch is CancellationError {
            return
        } catch {
            draftStates[stageId] = .failed(String(describing: error))
        }
    }

    private func runFetch() async {
        // Stash the prior state so a 304 response can restore it. We do flip
        // to .loading so the UI can show a spinner, but if the server says
        // "nothing changed", we restore the last results instead of going
        // to .empty.
        let prior = state
        state = .loading
        do {
            let response = try await api.list(status: statusFilter, ifNoneMatch: etag)
            if Task.isCancelled { return }
            if response.notModified {
                if let newETag = response.etag { etag = newETag }
                if case .results = prior {
                    state = prior
                    return
                }
                state = .empty
                return
            }
            if let newETag = response.etag { etag = newETag }
            state = response.sequences.isEmpty ? .empty : .results(response.sequences)
        } catch is CancellationError {
            return
        } catch {
            state = .error(String(describing: error))
        }
    }
}
