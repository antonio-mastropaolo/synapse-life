import SwiftUI
import Models
import DesignSystem

#if os(macOS)

/// Spotlight panel — macOS-only in M2. iPhone/iPad surface lands in M3.
/// Stateless on purpose: callers (the panel controller or the view model
/// owner) pass in the resolved state. The wrapping `SpotlightPanelScene`
/// binds this to a `SpotlightViewModel`.
@MainActor
public struct SpotlightPanelView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    private let state: SpotlightState
    private let selected: SpotlightItem?
    private let query: String
    private let onQueryChange: (String) -> Void
    private let onSelect: (SpotlightItem) -> Void

    public init(
        state: SpotlightState,
        selected: SpotlightItem?,
        query: String,
        onQueryChange: @escaping (String) -> Void = { _ in },
        onSelect: @escaping (SpotlightItem) -> Void = { _ in }
    ) {
        self.state = state
        self.selected = selected
        self.query = query
        self.onQueryChange = onQueryChange
        self.onSelect = onSelect
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        VStack(spacing: 0) {
            searchBar(tokens: tokens)
            Divider().background(tokens.foregroundSecondary.color.opacity(0.2))
            HSplitView {
                resultsList(tokens: tokens)
                    .frame(minWidth: 260, idealWidth: 320)
                detail(tokens: tokens)
                    .frame(minWidth: 340)
            }
        }
        .background(tokens.background.color)
        .accessibilityElement(children: .contain)
    }

    private func searchBar(tokens: TokenSet) -> some View {
        let queryBinding = Binding<String>(
            get: { query },
            set: { newValue in onQueryChange(newValue) }
        )
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(tokens.foregroundSecondary.color)
            TextField("Search picks, papers, venues", text: queryBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .accessibilityIdentifier("spotlight.search")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func resultsList(tokens: TokenSet) -> some View {
        switch state {
        case .idle, .loading:
            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .tint(tokens.foregroundSecondary.color)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.surface.color)
        case .empty:
            VStack(spacing: 6) {
                Spacer()
                Text("No results")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("Refine the query, or run a discover pass.")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.surface.color)
        case .results(let items):
            List(selection: Binding<SpotlightItem?>(
                get: { selected },
                set: { if let v = $0 { onSelect(v) } }
            )) {
                ForEach(items, id: \.self) { item in
                    SpotlightRow(item: item)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .background(tokens.surface.color)
        case .error(let message):
            VStack(spacing: 6) {
                Spacer()
                Text("Couldn't load picks")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.surface.color)
        }
    }

    @ViewBuilder
    private func detail(tokens: TokenSet) -> some View {
        if let item = selected {
            SpotlightDetailView(item: item)
                .background(tokens.background.color)
        } else {
            VStack {
                Spacer()
                Text("Select a pick")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.background.color)
        }
    }
}

private struct SpotlightRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let item: SpotlightItem

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let title = item.topCandidate()?.title ?? item.summary ?? item.message.subject
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let venue = item.topCandidate()?.venueTag {
                    Text(venue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.accent.color)
                }
                Text(item.status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SpotlightDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let item: SpotlightItem

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let title = item.topCandidate()?.title ?? item.summary ?? item.message.subject
        let raw = item.summary ?? item.message.subject
        let formatted = (try? SpotlightAbstractFormatter.format(title: title, raw: raw))
            ?? FormattedAbstract(lines: [title, raw, ""], wordCount: 0, containsTitle: true)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                if let venue = item.topCandidate()?.venueTag {
                    Text(venue)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.accent.color)
                }
            }
            SpotlightAbstractCardView(title: title, abstract: formatted)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#endif
