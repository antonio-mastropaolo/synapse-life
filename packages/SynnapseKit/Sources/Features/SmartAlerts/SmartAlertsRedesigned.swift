import SwiftUI
import DesignSystem
import Models

/// Rich redesign of the Smart Alerts surface, modeled on the
/// vocabulary established by `RecurringsRedesigned`. Five stacked
/// visual layers:
///
/// 1. **Hero summary** — title, total open count, severity-grouped
///    tiny counters (Critical / Warning / Info badges).
/// 2. **Filter chips** — All / Open / Snoozed / Dismissed / By
///    severity. Same chip style as `RecurringsRedesigned.filterChips`.
/// 3. **Alert cards** — vertical list with severity color stripe,
///    icon, headline, body, relative timestamp, and trailing
///    Snooze / Dismiss / Open actions.
/// 4. **AI suggested rules** — 3 tile grid (132pt uniform height)
///    proposing new rules. Each tile carries a `+ Add rule` button.
/// 5. **Rules management** — collapsible. Existing enabled rules
///    with toggle switches and a `+ New rule` affordance.
///
/// Snooze / dismiss state is held locally — the current
/// `SmartAlertsViewModel` does not expose those mutators yet, so we
/// keep the UI honest by tagging local snooze/dismiss buckets and
/// surfacing a SAMPLE chip when we fall back to canned data.
@MainActor
public struct SmartAlertsRedesigned: View {

    @Bindable private var viewModel: SmartAlertsViewModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var filter: AlertFilter = .all
    /// Local snooze ledger keyed by fired-alert id. The VM does not
    /// persist snooze state, so this lives in the view until the
    /// engine grows the contract.
    @State private var snoozedUntil: [String: Date] = [:]
    /// Local dismiss ledger keyed by fired-alert id. Same caveat as
    /// `snoozedUntil`.
    @State private var dismissedIds: Set<String> = []
    @State private var rulesExpanded: Bool = false

    public init(viewModel: SmartAlertsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header(tokens: tokens)
                filterChips(tokens: tokens)
                alertList(tokens: tokens)
                suggestedRules(tokens: tokens)
                rulesManagement(tokens: tokens)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("intelligence.smartAlerts.redesigned")
    }

    // MARK: - Hero

    private func header(tokens: TokenSet) -> some View {
        let stats = severityBreakdown
        return VStack(alignment: .leading, spacing: 10) {
            Text("Smart alerts")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                summaryTile(
                    label: "Open",
                    value: "\(openAlerts.count)",
                    tokens: tokens
                )
                summaryTile(
                    label: "Snoozed",
                    value: "\(snoozedAlerts.count)",
                    tokens: tokens
                )
                summaryTile(
                    label: "Dismissed",
                    value: "\(dismissedAlerts.count)",
                    tokens: tokens
                )
                Spacer()
                severityBadges(stats: stats)
            }
            if isUsingSampleData {
                sampleChip
            }
        }
    }

    private func summaryTile(label: String, value: String, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
        }
    }

    private func severityBadges(stats: SeverityBreakdown) -> some View {
        HStack(spacing: 8) {
            severityCounter(label: "Critical", count: stats.alert, color: Self.severityCritical)
            severityCounter(label: "Warning", count: stats.warning, color: Self.severityWarning)
            severityCounter(label: "Info", count: stats.info, color: Self.severityInfo)
        }
    }

    private func severityCounter(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Filter chips

    private enum AlertFilter: String, CaseIterable, Identifiable {
        case all, open, snoozed, dismissed, critical, warning, info
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:       return "All"
            case .open:      return "Open"
            case .snoozed:   return "Snoozed"
            case .dismissed: return "Dismissed"
            case .critical:  return "Critical"
            case .warning:   return "Warning"
            case .info:      return "Info"
            }
        }
    }

    private func filterChips(tokens: TokenSet) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AlertFilter.allCases) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.label.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(filter == f
                                ? Color.white
                                : tokens.foregroundSecondary.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(filter == f
                                        ? Self.severityWarning
                                        : tokens.foregroundSecondary.color.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Alert list

    private func alertList(tokens: TokenSet) -> some View {
        let rows = filteredAlerts
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ALERT FEED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                Text("\(rows.count) shown")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            if rows.isEmpty {
                emptyAlerts(tokens: tokens)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        alertCard(row, tokens: tokens)
                    }
                }
            }
        }
    }

    private func emptyAlerts(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.34, green: 0.78, blue: 0.50))
            Text(filter == .all
                 ? "No alerts in the current window. Synapse will surface them here as they fire."
                 : "Nothing matches this filter.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.05))
        )
    }

    private func alertCard(_ row: AlertRow, tokens: TokenSet) -> some View {
        let tint = severityColor(row.fired.severity)
        let bucket = bucket(for: row.fired)
        return HStack(alignment: .top, spacing: 0) {
            // Severity stripe.
            Rectangle()
                .fill(tint)
                .frame(width: 4)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: severityIcon(row.fired.severity))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(tint.opacity(0.15))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.fired.headline)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        if bucket == .snoozed {
                            statePill(label: "Snoozed", color: Self.severityInfo)
                        } else if bucket == .dismissed {
                            statePill(label: "Dismissed", color: tokens.foregroundSecondary.color)
                        }
                    }
                    Text(row.fired.body)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        Text(formatRelative(row.fired.firedAt))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                        if let until = snoozedUntil[row.fired.id], until > Date() {
                            Text("· until \(formatShort(until))")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(Self.severityInfo)
                        }
                    }
                }
                Spacer(minLength: 8)
                alertActions(for: row, tokens: tokens)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(minHeight: 88)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(bucket == .dismissed ? 0.55 : 1.0)
    }

    private func statePill(label: String, color: Color) -> some View {
        Text(label.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(0.18))
            )
    }

    @ViewBuilder
    private func alertActions(for row: AlertRow, tokens: TokenSet) -> some View {
        HStack(spacing: 6) {
            Menu {
                Button("Snooze 1 hour")   { snooze(row.fired, hours: 1) }
                Button("Snooze 24 hours") { snooze(row.fired, hours: 24) }
                Button("Snooze 1 week")   { snooze(row.fired, hours: 24 * 7) }
                Divider()
                Button("Snooze forever")  { snooze(row.fired, hours: nil) }
                if snoozedUntil[row.fired.id] != nil {
                    Divider()
                    Button("Un-snooze")    { snoozedUntil[row.fired.id] = nil }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Snooze")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Self.severityInfo)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Self.severityInfo.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                if dismissedIds.contains(row.fired.id) {
                    dismissedIds.remove(row.fired.id)
                } else {
                    dismissedIds.insert(row.fired.id)
                }
            } label: {
                Text(dismissedIds.contains(row.fired.id) ? "Restore" : "Dismiss")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(tokens.foregroundSecondary.color.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)

            if row.fired.subjectId != nil {
                Button {
                    // Deep-link target is owned by the host; no-op here.
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(tokens.foregroundSecondary.color.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - AI suggested rules

    private func suggestedRules(tokens: TokenSet) -> some View {
        let cols = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        let tiles = suggestionTiles
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Self.severityWarning)
                Text("AI SUGGESTED RULES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                Spacer()
                if isUsingSampleSuggestions {
                    sampleChip
                }
            }
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(tiles) { tile in
                    suggestionTile(tile, tokens: tokens)
                }
            }
        }
    }

    private struct SuggestionTile: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let tone: Color
        /// nil when the tile is canned sample copy; the rule the VM
        /// will install when the user taps `+ Add rule`.
        let rule: AlertRule?
    }

    private func suggestionTile(_ tile: SuggestionTile, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: tile.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tile.tone)
                Text(tile.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
                Spacer()
            }
            Text(tile.detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                if let rule = tile.rule {
                    viewModel.add(rule)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Add rule")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(tile.tone)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tile.tone.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .disabled(tile.rule == nil)
            .opacity(tile.rule == nil ? 0.55 : 1.0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundSecondary.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tile.tone.opacity(0.30), lineWidth: 1)
        )
    }

    private var suggestionTiles: [SuggestionTile] {
        let vmTiles = viewModel.suggestions.prefix(3).map { rule -> SuggestionTile in
            SuggestionTile(
                icon: icon(for: rule.kind),
                title: shortTitle(for: rule.kind),
                detail: rule.kind.label,
                tone: tone(for: rule.kind),
                rule: rule
            )
        }
        if vmTiles.count == 3 { return Array(vmTiles) }
        return Array((vmTiles + sampleSuggestionTiles).prefix(3))
    }

    private var sampleSuggestionTiles: [SuggestionTile] {
        [
            SuggestionTile(
                icon: "fork.knife",
                title: "Restaurants cap",
                detail: "Alert when restaurants exceed $200 in a single week. Catches takeout drift early.",
                tone: Self.severityWarning,
                rule: AlertRule(
                    id: "sample-restaurants-200",
                    kind: .unusualSpend(categoryLabel: "Restaurants", dailyThreshold: 200),
                    enabled: false,
                    isAISuggested: true
                )
            ),
            SuggestionTile(
                icon: "arrow.up.right.circle.fill",
                title: "Subscription rise",
                detail: "Alert when a known subscription charges more than its trailing median.",
                tone: Self.severityCritical,
                rule: nil
            ),
            SuggestionTile(
                icon: "creditcard.trianglebadge.exclamationmark",
                title: "Big transaction",
                detail: "Alert on any single transaction above $300 so you can dispute or confirm immediately.",
                tone: Self.severityInfo,
                rule: AlertRule(
                    id: "sample-big-txn-300",
                    kind: .unusualSpend(categoryLabel: nil, dailyThreshold: 300),
                    enabled: false,
                    isAISuggested: true
                )
            )
        ]
    }

    private var isUsingSampleSuggestions: Bool {
        viewModel.suggestions.count < 3
    }

    // MARK: - Rules management

    private func rulesManagement(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                rulesExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: rulesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text("Your rules")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text("\(viewModel.rules.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tokens.foregroundSecondary.color.opacity(0.12))
                        )
                    Spacer()
                    Text("\(enabledRulesCount) enabled")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if rulesExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    newRuleAffordance(tokens: tokens)
                    Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                    if viewModel.rules.isEmpty {
                        Text("No rules yet. Add one above or accept an AI suggestion.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    } else {
                        ForEach(viewModel.rules) { rule in
                            ruleManagementRow(rule, tokens: tokens)
                            if rule.id != viewModel.rules.last?.id {
                                Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                            }
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func newRuleAffordance(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Self.severityWarning)
            Text("New rule")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Compose a custom alert — balance, recurring, or category spike.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tokens.foregroundSecondary.color)
                .lineLimit(1)
            Spacer()
            Menu {
                Button("Balance low: checking < $500") {
                    viewModel.add(
                        AlertRule(
                            id: UUID().uuidString,
                            kind: .balanceLow(accountKind: .checking, threshold: 500)
                        )
                    )
                }
                Button("Balance low: savings < $1,000") {
                    viewModel.add(
                        AlertRule(
                            id: UUID().uuidString,
                            kind: .balanceLow(accountKind: .savings, threshold: 1_000)
                        )
                    )
                }
                Button("New recurring detected") {
                    viewModel.add(
                        AlertRule(
                            id: UUID().uuidString,
                            kind: .newRecurring
                        )
                    )
                }
                Button("Any single day > $300") {
                    viewModel.add(
                        AlertRule(
                            id: UUID().uuidString,
                            kind: .unusualSpend(categoryLabel: nil, dailyThreshold: 300)
                        )
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Add")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Self.severityWarning)
                )
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func ruleManagementRow(_ rule: AlertRule, tokens: TokenSet) -> some View {
        let tint = tone(for: rule.kind)
        return HStack(spacing: 12) {
            Image(systemName: icon(for: rule.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tint.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(shortTitle(for: rule.kind))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    if rule.isAISuggested {
                        Text("AI")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(Self.severityWarning)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Self.severityWarning.opacity(0.15))
                            )
                    }
                }
                Text(rule.kind.label)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { viewModel.setEnabled(rule.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            Button {
                viewModel.remove(rule.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(tokens.foregroundSecondary.color.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var enabledRulesCount: Int {
        viewModel.rules.filter(\.enabled).count
    }

    // MARK: - Sample chip

    private var sampleChip: some View {
        Text("SAMPLE")
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
            )
    }

    // MARK: - Snooze / dismiss bookkeeping
    //
    // The VM does not yet expose snooze or dismiss persistence. We
    // hold both as view-local state and surface a SAMPLE chip on the
    // suggestion grid when the engine returns fewer than three.

    private enum AlertBucket { case open, snoozed, dismissed }

    private func bucket(for fired: FiredAlert) -> AlertBucket {
        if dismissedIds.contains(fired.id) { return .dismissed }
        if let until = snoozedUntil[fired.id] {
            // `until == .distantFuture` represents "snooze forever".
            if until > Date() { return .snoozed }
        }
        return .open
    }

    private func snooze(_ fired: FiredAlert, hours: Int?) {
        if let hours {
            snoozedUntil[fired.id] = Date().addingTimeInterval(TimeInterval(hours) * 3600)
        } else {
            snoozedUntil[fired.id] = .distantFuture
        }
        // Snooze always implies un-dismiss.
        dismissedIds.remove(fired.id)
    }

    // MARK: - Source data
    //
    // If the engine has not fired anything yet, fall back to a small
    // sample bundle so the surface looks alive in screenshots and
    // empty-account flows. We tag this with the SAMPLE chip so it is
    // never confused with real data.

    private struct AlertRow: Identifiable {
        let fired: FiredAlert
        var id: String { fired.id }
    }

    private var isUsingSampleData: Bool {
        viewModel.firedAlerts.isEmpty
    }

    private var allAlerts: [AlertRow] {
        let source = viewModel.firedAlerts.isEmpty ? sampleFired : viewModel.firedAlerts
        return source.map(AlertRow.init)
    }

    private var openAlerts: [AlertRow] {
        allAlerts.filter { bucket(for: $0.fired) == .open }
    }

    private var snoozedAlerts: [AlertRow] {
        allAlerts.filter { bucket(for: $0.fired) == .snoozed }
    }

    private var dismissedAlerts: [AlertRow] {
        allAlerts.filter { bucket(for: $0.fired) == .dismissed }
    }

    private var filteredAlerts: [AlertRow] {
        let base: [AlertRow]
        switch filter {
        case .all:       base = allAlerts
        case .open:      base = openAlerts
        case .snoozed:   base = snoozedAlerts
        case .dismissed: base = dismissedAlerts
        case .critical:  base = allAlerts.filter { $0.fired.severity == .alert }
        case .warning:   base = allAlerts.filter { $0.fired.severity == .warning }
        case .info:      base = allAlerts.filter { $0.fired.severity == .info }
        }
        return base.sorted { $0.fired.firedAt > $1.fired.firedAt }
    }

    private struct SeverityBreakdown {
        var alert: Int = 0
        var warning: Int = 0
        var info: Int = 0
    }

    private var severityBreakdown: SeverityBreakdown {
        var out = SeverityBreakdown()
        for row in openAlerts {
            switch row.fired.severity {
            case .alert:   out.alert += 1
            case .warning: out.warning += 1
            case .info:    out.info += 1
            }
        }
        return out
    }

    private var sampleFired: [FiredAlert] {
        let now = Date()
        return [
            FiredAlert(
                id: "sample-1",
                ruleId: "sample-rule-1",
                firedAt: now.addingTimeInterval(-2 * 3600),
                subjectId: "txn-sample-1",
                headline: "Checking balance below $500",
                body: "Primary Checking is at $412.18. Consider transferring from Savings before the rent ACH clears Friday.",
                severity: .alert
            ),
            FiredAlert(
                id: "sample-2",
                ruleId: "sample-rule-2",
                firedAt: now.addingTimeInterval(-9 * 3600),
                subjectId: "merchant-sample-1",
                headline: "New recurring detected: Notion",
                body: "Notion charged $10 on a monthly cadence — looks like a fresh subscription not seen in the last 90 days.",
                severity: .info
            ),
            FiredAlert(
                id: "sample-3",
                ruleId: "sample-rule-3",
                firedAt: now.addingTimeInterval(-26 * 3600),
                subjectId: "txn-sample-3",
                headline: "Restaurants spend > $200 today",
                body: "Three Doordash charges plus one in-person tab pushed today's restaurants total to $237.40.",
                severity: .warning
            ),
            FiredAlert(
                id: "sample-4",
                ruleId: "sample-rule-4",
                firedAt: now.addingTimeInterval(-48 * 3600),
                subjectId: nil,
                headline: "Single transaction over $300",
                body: "United Airlines billed $612.30 — review and confirm if this matches your travel plans.",
                severity: .warning
            )
        ]
    }

    // MARK: - Severity helpers

    static let severityCritical = Color(red: 0.94, green: 0.33, blue: 0.56)
    static let severityWarning  = Color(red: 1.00, green: 0.69, blue: 0.22)
    static let severityInfo     = Color(red: 0.27, green: 0.83, blue: 0.89)

    private func severityColor(_ severity: FiredAlert.Severity) -> Color {
        switch severity {
        case .alert:   return Self.severityCritical
        case .warning: return Self.severityWarning
        case .info:    return Self.severityInfo
        }
    }

    private func severityIcon(_ severity: FiredAlert.Severity) -> String {
        switch severity {
        case .alert:   return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    private func icon(for kind: AlertRule.Kind) -> String {
        switch kind {
        case .balanceLow:    return "banknote"
        case .newRecurring:  return "arrow.triangle.2.circlepath"
        case .unusualSpend:  return "chart.line.uptrend.xyaxis"
        }
    }

    private func tone(for kind: AlertRule.Kind) -> Color {
        switch kind {
        case .balanceLow:    return Self.severityCritical
        case .newRecurring:  return Self.severityInfo
        case .unusualSpend:  return Self.severityWarning
        }
    }

    private func shortTitle(for kind: AlertRule.Kind) -> String {
        switch kind {
        case .balanceLow(let acct, _):
            return "\(acct.rawValue.capitalized) balance"
        case .newRecurring:
            return "New recurring"
        case .unusualSpend(let cat, _):
            return cat == nil ? "Any spike" : "\(cat ?? "") spike"
        }
    }

    // MARK: - Formatters

    private func formatRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatShort(_ date: Date) -> String {
        if date == .distantFuture { return "forever" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMM d, h:mma"
        return df.string(from: date)
    }
}
