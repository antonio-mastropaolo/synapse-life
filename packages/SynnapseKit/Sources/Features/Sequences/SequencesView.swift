import SwiftUI
import Models
import Networking
import DesignSystem

/// Top-level Sequences view. macOS pairs a `Table` of sequences with an
/// inspector panel for the stage editor; iOS uses a `NavigationStack` with
/// a list and a pushed editor.
///
/// Per M9 hard constraint: the native client DISPLAYS sequences and EDITS
/// drafts. There is no send action — the outbound queue runs on the server.
@MainActor
public struct SequencesView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: SequencesViewModel

    public init(viewModel: SequencesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        #if os(macOS)
        macLayout
            .task {
                if case .idle = viewModel.state { await viewModel.refresh() }
            }
        #else
        iosLayout
            .task {
                if case .idle = viewModel.state { await viewModel.refresh() }
            }
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return NavigationSplitView {
            filtersSidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            sequencesTable
                .navigationSplitViewColumnWidth(min: 360, ideal: 480)
                .navigationTitle("Sequences")
        } detail: {
            stageInspector
                .background(tokens.background.color)
        }
        .background(tokens.background.color)
    }

    private var filtersSidebar: some View {
        let tokens = theme.tokens(for: scheme)
        return List {
            Section("Status") {
                ForEach(SequencesStatusFilter.allCases, id: \.self) { filter in
                    Button {
                        Task { await viewModel.setStatusFilter(filter) }
                    } label: {
                        HStack {
                            Image(systemName: icon(for: filter))
                                .frame(width: 18)
                            Text(filter.rawValue.capitalized)
                            Spacer()
                            if viewModel.statusFilter == filter {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(tokens.accent.color)
                            }
                        }
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Filter by \(filter.rawValue)")
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 28)
                }
            }
        }
        .listStyle(.sidebar)
        .background(tokens.surface.color)
    }

    private var sequencesTable: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading sequences")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                emptyState
            case .results(let rows):
                Table(rows, selection: Binding(
                    get: { viewModel.selected?.id },
                    set: { id in
                        if let id, let row = rows.first(where: { $0.id == id }) {
                            viewModel.select(row)
                        }
                    }
                )) {
                    TableColumn("Lead") { row in
                        Text(row.leadDisplay)
                            .font(.system(.body, design: .default, weight: .medium))
                    }
                    TableColumn("Subject") { row in
                        Text(row.subject)
                            .lineLimit(1)
                    }
                    TableColumn("Touch") { row in
                        Text("\(row.currentTouch) / \(row.stages.count)")
                            .monospacedDigit()
                    }
                    .width(60)
                    TableColumn("Next") { row in
                        Text(SequenceFormatters.due(row.nextDueAt))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(120)
                    TableColumn("Status") { row in
                        StatusPill(status: row.status)
                    }
                    .width(110)
                }
            case .error(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("Couldn't load sequences").font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func icon(for filter: SequencesStatusFilter) -> String {
        switch filter {
        case .active:    return "paperplane"
        case .paused:    return "pause.circle"
        case .replied:   return "bubble.left.and.bubble.right"
        case .completed: return "checkmark.seal"
        case .all:       return "tray.full"
        }
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        NavigationStack {
            sequencesList
                .navigationTitle("Sequences")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
                            ForEach(SequencesStatusFilter.allCases, id: \.self) { filter in
                                Button {
                                    Task { await viewModel.setStatusFilter(filter) }
                                } label: {
                                    HStack {
                                        Text(filter.rawValue.capitalized)
                                        if viewModel.statusFilter == filter {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        .accessibilityLabel("Filter sequences")
                    }
                }
                .navigationDestination(for: Sequence.self) { sequence in
                    SequenceStageEditorScreen(viewModel: viewModel, sequence: sequence)
                }
        }
    }

    private var sequencesList: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                emptyState
            case .results(let rows):
                List(rows) { row in
                    NavigationLink(value: row) {
                        SequenceRowView(sequence: row)
                            .frame(minHeight: 56)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(accessibilityLabel(for: row))
                    }
                }
                .listStyle(.insetGrouped)
            case .error(let message):
                Text(message)
                    .padding()
                    .foregroundStyle(.secondary)
            }
        }
    }
    #endif

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No sequences")
                .font(.headline)
            Text("Enroll a lead from /advisors to start a cadence.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No sequences")
    }

    private var stageInspector: some View {
        Group {
            if let selected = viewModel.selected {
                SequenceStageEditor(viewModel: viewModel, sequence: selected)
            } else {
                Text("Select a sequence")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func accessibilityLabel(for sequence: Sequence) -> String {
        let due = SequenceFormatters.due(sequence.nextDueAt)
        return "\(sequence.leadDisplay), \(sequence.subject), touch \(sequence.currentTouch) of \(sequence.stages.count), \(due), \(sequence.status.rawValue)"
    }
}

// MARK: - Row

@MainActor
private struct SequenceRowView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let sequence: Sequence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sequence.leadDisplay)
                    .font(.system(.body, weight: .semibold))
                Spacer()
                StatusPill(status: sequence.status)
            }
            Text(sequence.subject)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("Touch \(sequence.currentTouch) / \(sequence.stages.count)", systemImage: "paperplane")
                    .labelStyle(.titleAndIcon)
                Text(SequenceFormatters.due(sequence.nextDueAt))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status pill

@MainActor
struct StatusPill: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let status: SequenceStatus

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let bg = colorFor(status, tokens: tokens)
        return Text(status.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
            .monospaced()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(bg.opacity(0.18))
                    .overlay(Capsule().strokeBorder(bg.opacity(0.55), lineWidth: 0.5))
            )
            .foregroundStyle(bg)
            .accessibilityLabel("Status \(status.rawValue)")
    }

    private func colorFor(_ status: SequenceStatus, tokens: TokenSet) -> Color {
        switch status {
        case .active:    return tokens.gainAccent.color
        case .paused:    return tokens.accent.color
        case .replied:   return tokens.accent.color
        case .completed: return tokens.foregroundSecondary.color
        case .unknown:   return tokens.foregroundSecondary.color
        }
    }
}

// MARK: - iOS stage editor screen wrapper

#if os(iOS)
@MainActor
private struct SequenceStageEditorScreen: View {
    @Bindable var viewModel: SequencesViewModel
    let sequence: Sequence

    var body: some View {
        SequenceStageEditor(viewModel: viewModel, sequence: sequence)
            .navigationTitle(sequence.leadDisplay)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.select(sequence) }
    }
}
#endif

// MARK: - Stage editor

@MainActor
struct SequenceStageEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable var viewModel: SequencesViewModel
    let sequence: Sequence

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let stageId = viewModel.selectedStageId ?? sequence.activeStage?.id ?? sequence.stages.first?.id ?? ""

        return VStack(spacing: 0) {
            stagePicker
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    leadHeader
                    subjectField(stageId: stageId)
                    bodyField(stageId: stageId)
                    saveStatusRow(stageId: stageId)
                    sendNoticeBox
                }
                .padding(16)
            }
        }
        .background(tokens.background.color)
    }

    private var leadHeader: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 4) {
            Text(sequence.leadDisplay)
                .font(.system(.title3, weight: .semibold))
            Text(sequence.leadEmail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                StatusPill(status: sequence.status)
                Text("Touch \(sequence.currentTouch) of \(sequence.stages.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Divider().overlay(tokens.foregroundSecondary.color.opacity(0.3))
        }
    }

    private var stagePicker: some View {
        Picker("Stage", selection: Binding(
            get: { viewModel.selectedStageId ?? sequence.stages.first?.id ?? "" },
            set: { viewModel.selectStage(id: $0) }
        )) {
            ForEach(sequence.stages) { stage in
                Text("\(stage.touchNumber)").tag(stage.id)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Select stage")
    }

    private func subjectField(stageId: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subject").font(.caption).foregroundStyle(.secondary)
            TextField("Subject", text: Binding(
                get: { viewModel.draftSubject(forStage: stageId) },
                set: { viewModel.updateDraftSubject(stageId: stageId, value: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Stage subject")
            .frame(minHeight: 44)
        }
    }

    private func bodyField(stageId: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { viewModel.draftBody(forStage: stageId) },
                set: { viewModel.updateDraftBody(stageId: stageId, value: $0) }
            ))
            .frame(minHeight: 180)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
            .accessibilityLabel("Stage body")
        }
    }

    private func saveStatusRow(stageId: String) -> some View {
        let state = viewModel.draftSaveState(forStage: stageId)
        return HStack(spacing: 6) {
            switch state {
            case .clean:
                Image(systemName: "circle.dotted")
                Text("No unsaved changes").font(.caption)
            case .dirty:
                Image(systemName: "pencil.circle")
                Text("Editing…").font(.caption)
            case .saving:
                ProgressView().controlSize(.small)
                Text("Saving draft…").font(.caption)
            case .saved:
                Image(systemName: "checkmark.circle")
                Text("Draft saved").font(.caption)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                Text("Save failed — \(message)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var sendNoticeBox: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(alignment: .leading, spacing: 4) {
            Label("Sending happens server-side", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
            Text("This screen only edits drafts. The cold-email tick worker (POST /api/sequences/tick) is the only path that puts an email on the wire.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tokens.surface.color)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sending happens server-side. This screen only edits drafts.")
    }
}

// MARK: - Formatters

enum SequenceFormatters {
    static func due(_ date: Date?) -> String {
        guard let date else { return "—" }
        let delta = date.timeIntervalSinceNow
        let abs = Swift.abs(delta)
        let days = Int(abs / 86400)
        let hours = Int((abs.truncatingRemainder(dividingBy: 86400)) / 3600)
        if delta < 0 {
            if days > 0 { return "overdue \(days)d \(hours)h" }
            return "overdue \(hours)h"
        }
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h" }
        return "due now"
    }
}
