import SwiftUI
import DesignSystem
import Models

/// LIFE terminal fallback render path.
///
/// Used when (a) the host has no Metal device, (b) the Metal pipeline
/// fails to build, or (c) `accessibilityReduceMotion` is on. Renders the
/// same `[TerminalLine]` body in the strict 3-color palette using a
/// SwiftUI `Canvas` — no animation, no bloom, no scanlines.
struct LifeTerminalViewCanvas: View {
    let lines: [TerminalLine]
    let tokens: LifeIdentityTokens

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                tokens.terminalInk.color.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            TerminalLineView(line: line, tokens: tokens)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LIFE terminal feed")
    }
}

private struct TerminalLineView: View {
    let line: TerminalLine
    let tokens: LifeIdentityTokens

    var body: some View {
        // Day separators paint in dim phosphor; entry heads and wraps
        // paint in bright. The reducer has already done the work of
        // computing the exact text — we just color it.
        let color = (line.role == .daySeparator)
            ? tokens.phosphorDim.color
            : tokens.phosphorBright.color
        Text(line.text)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
