import SwiftUI
import Models
import DesignSystem

/// Sectioned, glass-language activity feed. Top-of-screen filter chips,
/// day-grouped rows, kind-aware leading glyph and severity stripe.
/// The shell wires `onOpenRoute` to its router; the view itself stays
/// router-agnostic.
@MainActor
public struct ActivityView: View {

    @Bindable private var viewModel: ActivityViewModel
    private var onOpenRoute: ((ActivityRoute) -> Void)?

    public init(
        viewModel: ActivityViewModel,
        onOpenRoute: ((ActivityRoute) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onOpenRoute = onOpenRoute
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                header
                filterBar
                content
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("activity.scroll")
        .task { if case .idle = viewModel.state { await viewModel.load() } }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text("Activity")
                .font(.system(size: 28, weight: .semibold))
            Text("Everything that touched your money — transactions, bills, anomalies, and weekly digests.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(ActivityFilter.allCases, id: \.self) { f in
                    chip(for: f)
                }
            }
        }
        .accessibilityIdentifier("activity.filters")
    }

    private func chip(for filter: ActivityFilter) -> some View {
        let selected = viewModel.selected == filter
        return Button {
            viewModel.select(filter)
        } label: {
            Text(filter.label)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            selected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                            lineWidth: DS.Stroke.hairline
                        )
                )
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.85))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.filter.\(filter.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            placeholderCard(systemImage: "clock.arrow.circlepath", title: "Loading activity…")
        case .error(let message):
            placeholderCard(systemImage: "exclamationmark.triangle", title: "Couldn't load activity", detail: message)
        case .ready(let buckets):
            if buckets.isEmpty {
                placeholderCard(
                    systemImage: "tray",
                    title: "No activity yet",
                    detail: "Nothing matches this filter. Try a different category, or check back after the next refresh."
                )
            } else {
                ForEach(buckets) { bucket in
                    section(bucket: bucket)
                }
            }
        }
    }

    private func placeholderCard(systemImage: String, title: String, detail: String? = nil) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(radius: DS.Radius.card, padding: DS.Spacing.lg)
    }

    private func section(bucket: ActivityComposer.DayBucket) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(sectionTitle(for: bucket.day))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.leading, DS.Spacing.xs)

            VStack(spacing: DS.Spacing.xs) {
                ForEach(bucket.entries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    private func row(for entry: LifeEntry) -> some View {
        Button {
            if let route = ActivityViewModel.route(for: entry) {
                onOpenRoute?(route)
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                glyph(for: entry.kind)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    if let detail = secondaryText(for: entry) {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DS.Spacing.xs)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeText(for: entry.timestamp))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    severityChip(for: entry)
                }
            }
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.md)
            .background(
                DS.Surface.card,
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: DS.Stroke.hairline)
            )
            .elevation(DS.Elevation.card)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.row.\(entry.id)")
        .accessibilityLabel(Text("\(entry.text), \(timeText(for: entry.timestamp))"))
    }

    private func glyph(for kind: LifeEntryKind) -> some View {
        let (symbol, tint) = symbolAndTint(for: kind)
        return ZStack {
            Circle()
                .fill(tint.opacity(0.16))
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func symbolAndTint(for kind: LifeEntryKind) -> (String, Color) {
        switch kind {
        case .transaction: return ("creditcard.fill",                        Color.primary.opacity(0.7))
        case .bill:        return ("calendar.badge.exclamationmark",         Color.orange)
        case .insight:     return ("sparkles",                               Color.accentColor)
        case .digest:      return ("doc.text",                               Color.accentColor)
        case .streak:      return ("flame.fill",                             Color.green)
        case .warning:     return ("exclamationmark.triangle.fill",          Color.red)
        case .boot:        return ("power",                                  Color.secondary)
        case .unknown:     return ("circle",                                 Color.secondary)
        }
    }

    private func secondaryText(for entry: LifeEntry) -> String? {
        if let body = entry.metadata?["body"] { return body }
        if let category = entry.metadata?["category"] { return category }
        if let merchant = entry.metadata?["merchant"] { return merchant }
        return nil
    }

    @ViewBuilder
    private func severityChip(for entry: LifeEntry) -> some View {
        if let raw = entry.metadata?["severity"], let sev = ProactiveSignal.Severity(rawValue: raw),
           sev != .info {
            Text(sev.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(severityColor(sev))
                .background(
                    Capsule(style: .continuous)
                        .fill(severityColor(sev).opacity(0.15))
                )
        }
    }

    private func severityColor(_ s: ProactiveSignal.Severity) -> Color {
        switch s {
        case .info:    return .secondary
        case .warning: return .orange
        case .alert:   return .red
        }
    }

    // MARK: - Date formatters

    private func sectionTitle(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = cal.isDate(day, equalTo: Date(), toGranularity: .year) ? "EEEE, MMM d" : "EEEE, MMM d, yyyy"
        return df.string(from: day)
    }

    private func timeText(for d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "h:mm a"
        return df.string(from: d)
    }
}
