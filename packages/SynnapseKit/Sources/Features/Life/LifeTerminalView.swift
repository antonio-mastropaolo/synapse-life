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

    public init(viewModel: LifeViewModel) {
        self.viewModel = viewModel
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

        let lines = LifeReducer.linesFromEntries(currentEntries(), columns: 120)

        ZStack(alignment: .topLeading) {
            // Background plate. When the shader path is live we layer
            // the amber phosphor under the SwiftUI text. When the
            // fallback path is live we paint the flat ink and let the
            // Canvas fallback render the body.
            switch viewModel.currentRenderPath {
            case .shader:
                shaderBackground(life: life, access: access)
                terminalText(lines: lines, life: life)
            case .canvasFallback:
                LifeTerminalViewCanvas(lines: lines, tokens: life)
            }
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

    private func currentEntries() -> [LifeEntry] {
        if case .ready(let entries) = viewModel.state { return entries }
        // While idle/loading, show the boot line so the terminal is never
        // visually empty — a black rectangle would imply a broken render.
        return [LifeEntry(
            id: "boot",
            timestamp: Date(),
            kind: .boot,
            text: "SYNAPSE LIFE TERMINAL — awaiting feed"
        )]
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

    private func terminalText(lines: [TerminalLine], life: LifeIdentityTokens) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(
                            line.role == .daySeparator
                                ? life.phosphorDim.color
                                : life.phosphorBright.color
                        )
                        .shadow(color: life.phosphorBright.color.opacity(0.35), radius: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Compositing: drawingGroup lets the shader's bloom and the text's
        // soft phosphor shadow blend through a single Metal pass rather
        // than every glyph being its own offscreen.
        .drawingGroup(opaque: false)
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
