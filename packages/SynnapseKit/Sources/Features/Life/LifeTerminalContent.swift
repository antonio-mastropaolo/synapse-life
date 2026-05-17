import SwiftUI
import DesignSystem
import Models

/// The text layer of the LIFE terminal.
///
/// This is what the user actually reads. The shader plate sits behind it
/// (or the Canvas flat ink, in Reduce Motion). The content view is the
/// same regardless of render path so the terminal never paints "orange
/// only" — even with zero entries the boot banner, system stats line, and
/// empty-state footer are always present.
///
/// Composition (top to bottom):
///   - Boot banner (4 lines, bright phosphor)
///   - blank separator
///   - day-banded entry buffer (reducer output)
///   - blank separator
///   - empty-state footer (dim phosphor, only when buffer is empty)
///   - prompt line with blinking cursor
///   - system stats line (dim phosphor, updates every second)
@MainActor
struct LifeTerminalContent: View {

    let entries: [LifeEntry]
    let tokens: LifeIdentityTokens
    let viewport: CGSize
    let reduceMotion: Bool
    let launchedAt: Date
    let serverContractLive: Bool

    /// Test seam: when set, the stats line freezes at this instant and
    /// the cursor block paints in its on-phase rather than animating.
    /// Snapshot tests inject a fixed instant so the output is byte-
    /// stable. Production leaves this `nil` and the TimelineViews drive
    /// the live values.
    var frozenInstant: Date? = nil

    var body: some View {
        let banner = LifeBootBanner.lines(
            version: LifeBootBanner.currentVersion,
            viewport: viewport,
            refreshHz: 60,
            entryCount: entries.count,
            serverContractLive: serverContractLive
        )
        let bodyLines = LifeReducer.linesFromEntries(entries, columns: 120)
        let isEmpty = entries.isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Boot banner — always rendered in bright phosphor.
                ForEach(banner.indices, id: \.self) { i in
                    phosphorLine(banner[i], dim: false)
                }

                // Visual separator. A blank line in monospace = one row of ink.
                phosphorLine(" ", dim: false)

                // Entry buffer (day-banded). Empty when entries empty —
                // the banner + footer + cursor still make the terminal
                // read as a real screen.
                ForEach(bodyLines) { line in
                    phosphorLine(
                        line.text,
                        dim: line.role == .daySeparator
                    )
                }

                if isEmpty {
                    phosphorLine(" ", dim: false)
                    phosphorLine(LifeBootBanner.unwiredFooter, dim: true)
                }

                // Prompt + cursor. The cursor is a full-cell block that
                // blinks at ~2 Hz when motion is allowed; in Reduce
                // Motion (or under a frozen instant) we paint a static
                // block.
                HStack(spacing: 0) {
                    Text("synapse$ ")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.phosphorBright.color)
                    LifeCursorBlock(
                        color: tokens.phosphorBright.color,
                        reduceMotion: reduceMotion || frozenInstant != nil
                    )
                }
                .padding(.top, 2)

                // System stats — the "this terminal is alive" line.
                // Frozen instant short-circuits the TimelineView so
                // snapshot tests render deterministically.
                if let frozen = frozenInstant {
                    statsLine(now: frozen)
                } else if reduceMotion {
                    statsLine(now: Date())
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        statsLine(now: context.date)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LIFE terminal feed")
    }

    private func phosphorLine(_ text: String, dim: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(dim ? tokens.phosphorDim.color : tokens.phosphorBright.color)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsLine(now: Date) -> some View {
        let snap = LifeSystemStats.snapshot(
            now: now,
            launchedAt: launchedAt,
            physicalMemoryBytes: Int64(ProcessInfo.processInfo.physicalMemory)
        )
        return phosphorLine(LifeSystemStats.formattedLine(snap), dim: true)
    }
}

/// The blinking cursor block. Solid bright-phosphor cell that toggles
/// opacity at ~2 Hz; in Reduce Motion it stays solid.
private struct LifeCursorBlock: View {
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            block(opacity: 1.0)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                // Alternate full ↔ dim each half-second. The dim phase
                // dips to 0.15 rather than 0 so the cursor never reads
                // as "gone" — it pulses, not disappears.
                let onPhase = Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                block(opacity: onPhase ? 1.0 : 0.15)
            }
        }
    }

    private func block(opacity: Double) -> some View {
        // ~one monospace cell at 13pt SF Mono: ≈ 7.8pt advance × 15pt line.
        // We don't measure — we paint a block that visually reads as a
        // single character cell.
        Rectangle()
            .fill(color)
            .frame(width: 8, height: 15)
            .opacity(opacity)
    }
}
