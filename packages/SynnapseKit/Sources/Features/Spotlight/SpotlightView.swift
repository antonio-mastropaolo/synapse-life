import SwiftUI
import Models
import DesignSystem

/// Cross-platform Spotlight surface — iOS-primary, also valid on iPad and
/// (in compact form) on Mac when not using the `NSPanel` shell.
///
/// On iPhone: `NavigationStack` with `.searchable` on the parent. Results
/// land in a `List`; rows are 3-line abstract cards. Tapping a row pushes a
/// detail view.
///
/// On iPad regular: same view tree but wrapped in `NavigationSplitView` for
/// a sidebar + detail layout. Compact iPad collapses to the iPhone variant
/// automatically via `horizontalSizeClass`.
@MainActor
public struct SpotlightView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @Bindable private var viewModel: SpotlightViewModel
    @State private var scopeSelection: SpotlightScope = .all

    public init(viewModel: SpotlightViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        #if os(iOS)
        Group {
            if sizeClass == .regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.refresh()
            }
        }
        #else
        stackLayout
            .task {
                if case .idle = viewModel.state {
                    await viewModel.refresh()
                }
            }
        #endif
    }

    private var stackLayout: some View {
        NavigationStack {
            resultsContent
                .navigationTitle("Spotlight")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .searchable(
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.setQuery($0) }
                    ),
                    prompt: "Search picks, papers, venues"
                )
                .searchScopes($scopeSelection) {
                    ForEach(SpotlightScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue.capitalized).tag(scope)
                    }
                }
                .refreshable { await viewModel.refresh() }
        }
    }

    #if os(iOS)
    private var splitLayout: some View {
        NavigationSplitView {
            resultsContent
                .navigationTitle("Spotlight")
                .searchable(
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.setQuery($0) }
                    ),
                    prompt: "Search"
                )
                .searchScopes($scopeSelection) {
                    ForEach(SpotlightScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue.capitalized).tag(scope)
                    }
                }
                .refreshable { await viewModel.refresh() }
        } detail: {
            if let item = viewModel.selected {
                SpotlightDetail(item: item)
            } else {
                emptyDetail
            }
        }
    }

    private var emptyDetail: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack {
            Spacer()
            Text("Select a pick")
                .font(.system(size: 14))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.background.color)
    }
    #endif

    @ViewBuilder
    private var resultsContent: some View {
        let tokens = theme.tokens(for: scheme)
        switch viewModel.state {
        case .idle, .loading:
            ZStack {
                tokens.surface.color
                ProgressView()
                    .tint(tokens.foregroundSecondary.color)
            }
            .accessibilityIdentifier("spotlight.loading")
        case .empty:
            ZStack {
                tokens.surface.color
                VStack(spacing: 6) {
                    Text("No results")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("Refine the query, or run a discover pass.")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
            }
            .accessibilityIdentifier("spotlight.empty")
        case .results(let items):
            List(items) { item in
                NavigationLink(value: item) {
                    SpotlightRow(item: item)
                }
                .listRowBackground(tokens.surface.color)
            }
            .scrollContentBackground(.hidden)
            .background(tokens.background.color)
            .navigationDestination(for: SpotlightItem.self) { item in
                SpotlightDetail(item: item)
                    .onAppear { viewModel.select(item) }
            }
        case .error(let message):
            ZStack {
                tokens.surface.color
                VStack(spacing: 8) {
                    Text("Couldn't load picks")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .accessibilityIdentifier("spotlight.error")
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
        let raw = item.summary ?? item.message.subject
        let formatted = (try? SpotlightAbstractFormatter.format(title: title, raw: raw))
            ?? FormattedAbstract(lines: [title, raw, ""], wordCount: 0, containsTitle: true)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let venue = item.topCandidate()?.venueTag {
                    Text(venue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.accent.color)
                }
                Text(item.status.uppercased())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
            }
            SpotlightAbstractCardView(title: title, abstract: formatted)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct SpotlightDetail: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let item: SpotlightItem

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let title = item.topCandidate()?.title ?? item.summary ?? item.message.subject
        let raw = item.summary ?? item.message.subject
        let formatted = (try? SpotlightAbstractFormatter.format(title: title, raw: raw))
            ?? FormattedAbstract(lines: [title, raw, ""], wordCount: 0, containsTitle: true)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    if let venue = item.topCandidate()?.venueTag {
                        Text(venue)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tokens.accent.color)
                    }
                }
                SpotlightAbstractCardView(title: title, abstract: formatted)
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(tokens.background.color)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
