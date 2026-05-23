import SwiftUI
import DesignSystem
import Models
import Networking

/// The LIFE Terminal screen.
///
/// Reads the LIFE token set from the environment theme, derives the
/// `LifeAccessibilityEnvironment` from system-supplied environment values,
/// asks the view model which render path to use, and composes either the
/// Metal-backed amber phosphor view or the Canvas fallback under a
/// monospaced text layer.
@MainActor
public struct LifeTerminalView: View {

    @Bindable public var viewModel: LifeViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    #if os(iOS)
    @Environment(\.legibilityWeight) private var legibility
    #endif

    /// Snapshot-only seam. When non-nil, the system-stats line and the
    /// cursor block freeze at this instant so the rendered output is
    /// byte-deterministic. Production never passes this; the
    /// TimelineViews drive the live values.
    let frozenInstant: Date?

    public init(viewModel: LifeViewModel) {
        self.viewModel = viewModel
        self.frozenInstant = nil
    }

    /// Snapshot-test init. Mirrors the pattern used by
    /// `LifeViewModel.injectStateForSnapshots(_:)` — surfaces a clean
    /// hook for tests without polluting the production API.
    public init(viewModel: LifeViewModel, frozenInstantForSnapshots: Date) {
        self.viewModel = viewModel
        self.frozenInstant = frozenInstantForSnapshots
    }

    public var body: some View {
        let tokens = theme.tokens(for: colorScheme)
        let life = tokens.life ?? LifeIdentityTokens(
            phosphorBright: tokens.foregroundPrimary,
            phosphorDim: tokens.foregroundSecondary,
            terminalInk: tokens.background
        )
        let access = LifeAccessibilityEnvironment(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            // Increase Contrast doesn't have a first-party SwiftUI key on
            // every platform; we read it via legibilityWeight on iOS and
            // ignore it on macOS in M6 (the macOS path uses .colorScheme
            // contrast preferences in a M9 polish pass).
            increaseContrast: false
        )

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Background plate. The shader path runs Metal underneath
                // the text; the Canvas fallback path paints flat ink
                // (still under the same text overlay so the boot banner +
                // stats line are present in both modes).
                switch viewModel.currentRenderPath {
                case .shader:
                    shaderBackground(life: life, access: access)
                case .canvasFallback:
                    life.terminalInk.color.ignoresSafeArea()
                }

                // Content overlay. The same view in both render paths —
                // boot banner, system stats, entries, empty-state footer,
                // and prompt cursor. This is what makes the terminal read
                // as alive instead of "orange backplate only".
                LifeTerminalContent(
                    entries: bufferEntries(),
                    tokens: life,
                    viewport: geo.size,
                    reduceMotion: reduceMotion,
                    launchedAt: viewModel.launchedAt,
                    serverContractLive: viewModel.serverContractLive,
                    frozenInstant: frozenInstant
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(life.terminalInk.color.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            viewModel.updateRenderPath(accessibility: access)
            if case .idle = viewModel.state {
                await viewModel.refresh()
            }
        }
        .onChange(of: reduceMotion) { _, _ in
            viewModel.updateRenderPath(accessibility: access)
        }
        .accessibilityElement(children: .contain)
    }

    /// Real entries from the view model. Returns `[]` when idle/loading/
    /// error/empty — the content layer renders its own banner, stats
    /// line, and empty-state footer, so we do not need to inject a
    /// synthetic boot row here. (Past bug: returning a fake `[LifeEntry]`
    /// with a single `.boot` row caused the text layer to render only one
    /// glyph, making the screen look like a pure-orange Metal plate.)
    private func bufferEntries() -> [LifeEntry] {
        if case .ready(let entries) = viewModel.state { return entries }
        return []
    }

    @ViewBuilder
    private func shaderBackground(
        life: LifeIdentityTokens,
        access: LifeAccessibilityEnvironment
    ) -> some View {
        #if canImport(MetalKit)
        LifeTerminalViewMetal(tokens: life, accessibility: access)
            .ignoresSafeArea()
        #else
        life.terminalInk.color.ignoresSafeArea()
        #endif
    }
}

/// Scene wrapper used by the macOS app shell so the LIFE window can own
/// its own LifeViewModel rather than sharing one with the rest of the
/// app — the terminal is single-window, single-state.
@MainActor
public struct LifeTerminalScene: View {

    @State private var viewModel: LifeViewModel

    public init(api: LifeAPI) {
        self._viewModel = State(initialValue: LifeViewModel(api: api))
    }

    public var body: some View {
        LifeTerminalView(viewModel: viewModel)
            .identity(.terminalAmber)
    }
}
