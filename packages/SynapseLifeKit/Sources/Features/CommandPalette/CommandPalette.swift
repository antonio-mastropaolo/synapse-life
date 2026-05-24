import Foundation
import SwiftUI
import DesignSystem

/// A surface the command palette can route the operator to. The id is
/// keyed off [[RootDestination]] for the well-known sidebar destinations
/// — the palette stays a pure routing surface and never owns content.
public struct CommandPaletteItem: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let destination: RootDestination

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        destination: RootDestination
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination
    }
}

/// Pure-function fuzzy match. `query` is matched character-by-character
/// against `candidate` in order (case-insensitive). Returns a score and
/// the matched indices on success, `nil` on miss.
///
/// Scoring favours:
///   - matches at the start of the candidate (+20),
///   - contiguous runs (+8 per consecutive matched char),
///   - matches at a word boundary (+12 — space or capital-letter start).
///
/// The score is intentionally simple — the palette has ≤ ~20 surfaces,
/// so a sub-microsecond pure function is more than fast enough.
public func fuzzyMatch(query: String, against candidate: String) -> (score: Int, indices: [Int])? {
    let q = Array(query.lowercased())
    let c = Array(candidate.lowercased())
    guard !q.isEmpty else { return (0, []) }
    guard !c.isEmpty else { return nil }

    var indices: [Int] = []
    var ci = 0
    var qi = 0
    var score = 0
    var lastMatch: Int = -2

    while qi < q.count && ci < c.count {
        if q[qi] == c[ci] {
            indices.append(ci)
            // Start-of-string bonus.
            if ci == 0 { score += 20 }
            // Word-boundary bonus: previous char is space or
            // candidate-original previous char is uppercase (we
            // compare against the original `candidate`, not the
            // lowercased copy, to detect CamelCase).
            if ci > 0 {
                let origIdx = candidate.index(candidate.startIndex, offsetBy: ci)
                let prevIdx = candidate.index(before: origIdx)
                let prev = candidate[prevIdx]
                if prev == " " || prev == "-" || prev == "_" {
                    score += 12
                } else if candidate[origIdx].isUppercase {
                    score += 8
                }
            }
            // Contiguous run bonus.
            if ci == lastMatch + 1 { score += 8 }
            lastMatch = ci
            score += 2
            qi += 1
        }
        ci += 1
    }

    guard qi == q.count else { return nil }
    return (score, indices)
}

/// View model for the command palette. Pure selection/filter logic — no
/// SwiftUI dependencies — so it can be exercised from `swift test`.
@MainActor
@Observable
public final class CommandPaletteViewModel {

    /// All items the palette knows about. Constructed by the caller
    /// (typically [[CommandPalette.defaultItems]]) so platform-specific
    /// surfaces can extend the list without touching the VM.
    public var items: [CommandPaletteItem]

    /// The operator's current query string.
    public var query: String = ""

    /// Index of the currently-highlighted match in `filtered`. Reset to
    /// 0 on every query change so the highlight always lands on the
    /// best match.
    public var highlightedIndex: Int = 0

    public init(items: [CommandPaletteItem] = CommandPalette.defaultItems) {
        self.items = items
    }

    /// Items that match the current query, sorted by descending score.
    /// An empty query returns the full list in declared order (so the
    /// palette opens to the canonical sidebar order rather than an
    /// alphabetised one).
    public var filtered: [CommandPaletteItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return items }
        let scored: [(item: CommandPaletteItem, score: Int)] = items.compactMap { item in
            let titleHit = fuzzyMatch(query: q, against: item.title)
            let subtitleHit = item.subtitle.flatMap { fuzzyMatch(query: q, against: $0) }
            // Subtitle hits weigh less than title hits so a search for
            // "ac" prefers Accounts over Activity-with-a-subtitle-that-
            // happens-to-contain-ac.
            let combined: Int? = {
                switch (titleHit, subtitleHit) {
                case (let t?, let s?): return t.score + s.score / 2
                case (let t?, nil):     return t.score
                case (nil, let s?):     return s.score / 2
                case (nil, nil):        return nil
                }
            }()
            guard let score = combined else { return nil }
            return (item, score)
        }
        return scored.sorted { $0.score > $1.score }.map(\.item)
    }

    /// Bring the highlight one row down. Wraps at the end.
    public func highlightNext() {
        let n = filtered.count
        guard n > 0 else { highlightedIndex = 0; return }
        highlightedIndex = (highlightedIndex + 1) % n
    }

    /// Bring the highlight one row up. Wraps at the start.
    public func highlightPrevious() {
        let n = filtered.count
        guard n > 0 else { highlightedIndex = 0; return }
        highlightedIndex = (highlightedIndex - 1 + n) % n
    }

    /// The item the operator would commit by pressing return.
    public var highlightedItem: CommandPaletteItem? {
        let f = filtered
        guard !f.isEmpty else { return nil }
        let idx = min(max(highlightedIndex, 0), f.count - 1)
        return f[idx]
    }

    /// Reset state for the next presentation. Call when the palette
    /// dismisses (committed or cancelled) so the next ⌘K opens with a
    /// clean slate.
    public func reset() {
        query = ""
        highlightedIndex = 0
    }
}

/// Static surface for the canonical palette items + the SwiftUI view.
public enum CommandPalette {

    /// The default set of palette items, in canonical sidebar order.
    /// Mirrors `RootDestination.canonicalOrder` so the palette never
    /// drifts away from what the sidebar actually shows.
    public static let defaultItems: [CommandPaletteItem] = [
        CommandPaletteItem(id: "dashboard",    title: "Dashboard",
                           subtitle: "Inbox of unreviewed transactions",
                           systemImage: "rectangle.grid.2x2",
                           destination: .dashboard),
        CommandPaletteItem(id: "transactions", title: "Transactions",
                           subtitle: "All activity, filterable",
                           systemImage: "arrow.left.arrow.right",
                           destination: .transactions),
        CommandPaletteItem(id: "goals",        title: "Goals",
                           subtitle: "Savings targets and weekly check-ins",
                           systemImage: "target",
                           destination: .goals),
        CommandPaletteItem(id: "accounts",     title: "Accounts",
                           subtitle: "Linked institutions and balances",
                           systemImage: "building.columns",
                           destination: .accounts),
        CommandPaletteItem(id: "investments",  title: "Investments",
                           subtitle: "Portfolios and positions",
                           systemImage: "chart.pie",
                           destination: .investments),
        CommandPaletteItem(id: "categories",   title: "Categories",
                           subtitle: "Pills and auto-categorize rules",
                           systemImage: "square.grid.3x3",
                           destination: .categories),
        CommandPaletteItem(id: "recurrings",   title: "Recurrings",
                           subtitle: "Detected recurring charges",
                           systemImage: "arrow.triangle.2.circlepath",
                           destination: .recurrings),
        CommandPaletteItem(id: "memberships",  title: "Memberships",
                           subtitle: "Subscription portfolio",
                           systemImage: "square.stack.3d.up.fill",
                           destination: .memberships),
        CommandPaletteItem(id: "activity",     title: "Activity",
                           subtitle: "Unified glass-language feed",
                           systemImage: "clock.arrow.circlepath",
                           destination: .activity),
        CommandPaletteItem(id: "advisors",     title: "Advisors",
                           subtitle: "Financial advisor agents",
                           systemImage: "person.bubble",
                           destination: .advisors),
        CommandPaletteItem(id: "digest",       title: "Digest",
                           subtitle: "Weekly briefing",
                           systemImage: "newspaper",
                           destination: .digest),
        CommandPaletteItem(id: "forecast",     title: "Forecast",
                           subtitle: "Projected balance and cash flow",
                           systemImage: "chart.line.uptrend.xyaxis",
                           destination: .forecast),
        CommandPaletteItem(id: "smartAlerts",  title: "Smart alerts",
                           subtitle: "Anomalies and proactive signals",
                           systemImage: "bell.badge",
                           destination: .smartAlerts)
    ]
}

/// SwiftUI surface for the command palette. Cross-platform: iOS gets the
/// same view (presented as a sheet from Settings or a deep link); macOS
/// is what the Cmd-K shortcut opens.
@MainActor
public struct CommandPaletteView: View {

    @Bindable var viewModel: CommandPaletteViewModel
    let onCommit: (CommandPaletteItem) -> Void
    let onDismiss: () -> Void

    @FocusState private var queryFieldFocused: Bool

    public init(
        viewModel: CommandPaletteViewModel,
        onCommit: @escaping (CommandPaletteItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onCommit = onCommit
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            queryRow
            Divider().opacity(0.4)
            resultsList
        }
        .frame(width: 560)
        .frame(maxHeight: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: DS.Stroke.hairline)
        )
        .shadow(color: .black.opacity(0.35), radius: 32, x: 0, y: 16)
        .onAppear { queryFieldFocused = true }
        .accessibilityIdentifier("command.palette.root")
    }

    // MARK: - Query

    private var queryRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)

            TextField("Jump to a surface", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
                .focused($queryFieldFocused)
                .onSubmit(commitHighlighted)
                .onChange(of: viewModel.query) { _, _ in
                    viewModel.highlightedIndex = 0
                }
                .accessibilityIdentifier("command.palette.query")

            keyHint("esc")
                .onTapGesture { onDismiss() }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm + 2)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    let items = viewModel.filtered
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { (idx, item) in
                            row(item: item, isHighlighted: idx == clampedIndex(items))
                                .id(item.id)
                                .onTapGesture { onCommit(item) }
                                .onHover { hovering in
                                    if hovering { viewModel.highlightedIndex = idx }
                                }
                        }
                    }
                }
                .padding(.vertical, DS.Spacing.xs)
            }
            .onChange(of: viewModel.highlightedIndex) { _, _ in
                if let item = viewModel.highlightedItem {
                    proxy.scrollTo(item.id, anchor: .center)
                }
            }
            .background(
                // Capture arrow keys / enter / esc. The hidden focus
                // ring is what lets keyDown bubble up from the text
                // field's surrounding hierarchy.
                KeyEventCatcher(
                    onArrowDown: viewModel.highlightNext,
                    onArrowUp:   viewModel.highlightPrevious,
                    onReturn:    commitHighlighted,
                    onEscape:    onDismiss
                )
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text("No matching surface")
                .font(.system(size: 13, weight: .semibold))
            Text("Try a different name or press esc.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(DS.Spacing.md)
        .accessibilityIdentifier("command.palette.empty")
    }

    private func row(item: CommandPaletteItem, isHighlighted: Bool) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 20)
                .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: isHighlighted ? .semibold : .regular))
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isHighlighted {
                keyHint("return")
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, DS.Spacing.xs)
        )
        .contentShape(Rectangle())
        .accessibilityIdentifier("command.palette.row.\(item.id)")
        .accessibilityAddTraits(isHighlighted ? [.isSelected, .isButton] : [.isButton])
    }

    private func keyHint(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    // MARK: - Helpers

    private func clampedIndex(_ items: [CommandPaletteItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        return min(max(viewModel.highlightedIndex, 0), items.count - 1)
    }

    private func commitHighlighted() {
        if let item = viewModel.highlightedItem {
            onCommit(item)
        }
    }
}

// MARK: - Key event catcher

/// Tiny AppKit/UIKit bridge that captures arrow keys + return + escape
/// without forcing the TextField to give up focus. SwiftUI's
/// `.keyboardShortcut` is not enough here because the text field
/// swallows arrow-key navigation before any shortcut sees it.
#if os(macOS)
private struct KeyEventCatcher: NSViewRepresentable {
    let onArrowDown: () -> Void
    let onArrowUp:   () -> Void
    let onReturn:    () -> Void
    let onEscape:    () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onArrowDown = onArrowDown
        view.onArrowUp   = onArrowUp
        view.onReturn    = onReturn
        view.onEscape    = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? CatcherView else { return }
        v.onArrowDown = onArrowDown
        v.onArrowUp   = onArrowUp
        v.onReturn    = onReturn
        v.onEscape    = onEscape
    }

    private final class CatcherView: NSView {
        var onArrowDown: (() -> Void)?
        var onArrowUp:   (() -> Void)?
        var onReturn:    (() -> Void)?
        var onEscape:    (() -> Void)?

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    switch event.keyCode {
                    case 125: self.onArrowDown?(); return nil  // down arrow
                    case 126: self.onArrowUp?();   return nil  // up arrow
                    case 36, 76: self.onReturn?(); return nil  // return / enter
                    case 53: self.onEscape?();     return nil  // escape
                    default: return event
                    }
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
    }
}
#else
private struct KeyEventCatcher: View {
    let onArrowDown: () -> Void
    let onArrowUp:   () -> Void
    let onReturn:    () -> Void
    let onEscape:    () -> Void
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}
#endif
