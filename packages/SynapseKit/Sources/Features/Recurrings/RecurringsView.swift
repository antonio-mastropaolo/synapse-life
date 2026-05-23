import SwiftUI
import DesignSystem
import Models

/// Recurrings surface — every detected recurring charge across
/// every cadence bucket, grouped into Detected / Confirmed / Ignored
/// sections. The user can Confirm or Ignore each row; the choice is
/// persisted via [[RecurringStatusStore]] and survives relaunch.
///
/// On macOS we paint a trailing inspector with the last six
/// occurrences of the currently-selected merchant so the user can
/// audit a detection without leaving the surface. On iOS the
/// inspector becomes a `NavigationLink` push.
@MainActor
public struct RecurringsView: View {

    @Bindable private var viewModel: RecurringsViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var selection: String?  // recurring.id
    @State private var expandedSections: Set<String> = ["detected", "confirmed"]

    public init(viewModel: RecurringsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        let sections = viewModel.sections

        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(tokens: tokens, totalCount: viewModel.recurrings.count)
                    section(
                        id: "detected", title: "Detected",
                        rows: sections.detected,
                        tokens: tokens,
                        showActions: true
                    )
                    section(
                        id: "confirmed", title: "Confirmed",
                        rows: sections.confirmed,
                        tokens: tokens,
                        showActions: true
                    )
                    section(
                        id: "ignored", title: "Ignored",
                        rows: sections.ignored,
                        tokens: tokens,
                        showActions: true
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            #if os(macOS)
            inspectorPane(tokens: tokens)
                .frame(width: 280)
                .background(tokens.background.color.opacity(0.6))
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundStyle(tokens.foregroundPrimary.color.opacity(0.08)),
                    alignment: .leading
                )
            #endif
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("more.recurrings")
    }

    // MARK: - Header

    @ViewBuilder
    private func header(tokens: TokenSet, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECURRINGS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalCount)")
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .monospacedDigit()
                    Text("detected".uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatCurrency(viewModel.monthlyEquivalentTotal))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .monospacedDigit()
                    Text("monthly equivalent".uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Spacer()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(
        id: String,
        title: String,
        rows: [DetectedRecurring],
        tokens: TokenSet,
        showActions: Bool
    ) -> some View {
        let isExpanded = expandedSections.contains(id)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded { expandedSections.remove(id) } else { expandedSections.insert(id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text("\(title.uppercased()) · \(rows.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if rows.isEmpty {
                    Text("Nothing here yet.")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .padding(.vertical, 4)
                } else {
                    ForEach(rows) { r in
                        rowView(r, tokens: tokens, showActions: showActions)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ r: DetectedRecurring, tokens: TokenSet, showActions: Bool) -> some View {
        let isSelected = selection == r.id
        let status = viewModel.status(for: r)
        Button {
            selection = r.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tokens.category(palette(for: r.category)).opacity(0.18))
                        .frame(width: 30, height: 30)
                    Text(String(r.merchant.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tokens.category(palette(for: r.category)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(r.merchant)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                        Text(cadenceLabel(r.cadenceDays).uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(tokens.foregroundSecondary.color.opacity(0.12))
                            )
                            .foregroundStyle(tokens.foregroundSecondary.color)
                    }
                    Text("Last \(formatDate(r.lastSeen)) · Next \(formatDate(r.predictedNext))")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                Spacer()
                Text(formatCurrency(r.medianAmount))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                    .monospacedDigit()

                if showActions {
                    actionButtons(for: r, status: status, tokens: tokens)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? tokens.accent.color.opacity(0.10)
                          : tokens.foregroundPrimary.color.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                          ? tokens.accent.color.opacity(0.5)
                          : tokens.foregroundPrimary.color.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recurring.row.\(r.merchant.lowercased())")
    }

    @ViewBuilder
    private func actionButtons(for r: DetectedRecurring, status: RecurringStatus, tokens: TokenSet) -> some View {
        HStack(spacing: 6) {
            actionButton(
                label: status == .confirmed ? "Confirmed" : "Confirm",
                kind: .confirm,
                isActive: status == .confirmed,
                tokens: tokens
            ) {
                let next: RecurringStatus = status == .confirmed ? .detected : .confirmed
                viewModel.setStatus(next, for: r)
            }
            actionButton(
                label: status == .ignored ? "Ignored" : "Ignore",
                kind: .ignore,
                isActive: status == .ignored,
                tokens: tokens
            ) {
                let next: RecurringStatus = status == .ignored ? .detected : .ignored
                viewModel.setStatus(next, for: r)
            }
        }
    }

    private enum ActionKind { case confirm, ignore }

    /// Bridge `CategoryID` (data layer) to `TokenSet.CategoryPaletteID`
    /// (design system) so the chip color matches the rest of the
    /// product surface. Slug-driven so `.custom` rides through as
    /// `.other` rather than crashing.
    private func palette(for id: CategoryID) -> TokenSet.CategoryPaletteID {
        TokenSet.CategoryPaletteID(rawValue: id.slug) ?? .other
    }

    @ViewBuilder
    private func actionButton(
        label: String,
        kind: ActionKind,
        isActive: Bool,
        tokens: TokenSet,
        action: @escaping () -> Void
    ) -> some View {
        let color: Color = {
            switch kind {
            case .confirm: return tokens.category(.income)
            case .ignore:  return tokens.category(.loans)
            }
        }()
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(isActive ? Color.white : color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? color : color.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inspector (macOS)

    @ViewBuilder
    private func inspectorPane(tokens: TokenSet) -> some View {
        let chosen = viewModel.recurrings.first(where: { $0.id == selection })
        VStack(alignment: .leading, spacing: 12) {
            Text("OCCURRENCES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            if let r = chosen {
                Text(r.merchant)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("\(cadenceLabel(r.cadenceDays)) · \(formatCurrency(r.medianAmount)) median · \(r.occurrenceCount) seen")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Divider().padding(.vertical, 4)
                let txs = viewModel.recentOccurrences(for: r)
                if txs.isEmpty {
                    Text("No occurrence history available.")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                } else {
                    ForEach(txs) { tx in
                        HStack {
                            Text(formatDate(tx.date))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(tokens.foregroundSecondary.color)
                            Spacer()
                            Text(formatCurrency(absDecimal(tx.amount ?? 0)))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(tokens.foregroundPrimary.color)
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                Text("Select a row to inspect its occurrence history.")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    // MARK: - Formatting

    private func cadenceLabel(_ days: Int) -> String {
        switch days {
        case 7:   return "Weekly"
        case 14:  return "Bi-weekly"
        case 30:  return "Monthly"
        case 90:  return "Quarterly"
        case 365: return "Yearly"
        default:  return "\(days)d"
        }
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }
}
