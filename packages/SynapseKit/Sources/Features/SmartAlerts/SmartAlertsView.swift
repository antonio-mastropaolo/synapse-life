import SwiftUI
import DesignSystem
import Models

/// Minimal SwiftUI host for the Smart Alerts surface.
///
/// Added 2026-05-17 during the four-branch Copilot integration. The
/// AI++ wedge shipped `SmartAlertsViewModel` + engine without a view;
/// this is the minimum-viable surface that lives behind the
/// INTELLIGENCE sidebar row.
///
/// Three sections, matching agent 5's manifest:
///   1. Installed rules (toggle for enabled)
///   2. AI-suggested rules (chip + accept)
///   3. Recent fired alerts (tappable; jump to subjectId is left to
///      the host via `onFiredAlertTap`)
@MainActor
public struct SmartAlertsView: View {

    @Bindable private var viewModel: SmartAlertsViewModel
    private let onFiredAlertTap: (@MainActor (FiredAlert) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(
        viewModel: SmartAlertsViewModel,
        onFiredAlertTap: (@MainActor (FiredAlert) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onFiredAlertTap = onFiredAlertTap
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(tokens: tokens)
                installedSection(tokens: tokens)
                if !viewModel.suggestions.isEmpty {
                    suggestionsSection(tokens: tokens)
                }
                firedSection(tokens: tokens)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
        .accessibilityIdentifier("intelligence.smartAlerts")
    }

    // MARK: - Header

    @ViewBuilder
    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SMART ALERTS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text("Rules and recent fires")
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
        }
    }

    // MARK: - Installed rules

    @ViewBuilder
    private func installedSection(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("INSTALLED", tokens: tokens)
            if viewModel.rules.isEmpty {
                Text("No rules installed yet.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            } else {
                ForEach(viewModel.rules) { rule in
                    ruleRow(rule: rule, tokens: tokens)
                }
            }
        }
    }

    @ViewBuilder
    private func ruleRow(rule: AlertRule, tokens: TokenSet) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.kind.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                if rule.isAISuggested {
                    Text("AI SUGGESTED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(tokens.accent.color)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { viewModel.setEnabled(rule.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.foregroundPrimary.color.opacity(0.04))
        )
    }

    // MARK: - Suggestions

    @ViewBuilder
    private func suggestionsSection(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SUGGESTED", tokens: tokens)
            ForEach(viewModel.suggestions) { rule in
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(tokens.accent.color)
                    Text(rule.kind.label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Spacer()
                    Button("Accept") {
                        viewModel.add(rule)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.accent.color)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tokens.accent.color.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tokens.accent.color.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Fired

    @ViewBuilder
    private func firedSection(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("RECENT FIRES", tokens: tokens)
            if viewModel.firedAlerts.isEmpty {
                Text("No alerts have fired in the current window.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            } else {
                ForEach(viewModel.firedAlerts) { fired in
                    firedRow(fired: fired, tokens: tokens)
                }
            }
        }
    }

    @ViewBuilder
    private func firedRow(fired: FiredAlert, tokens: TokenSet) -> some View {
        Button {
            onFiredAlertTap?(fired)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(severityColor(fired.severity, tokens: tokens))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fired.headline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                        .multilineTextAlignment(.leading)
                    Text(fired.body)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.foregroundPrimary.color.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, tokens: TokenSet) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(tokens.foregroundSecondary.color)
    }

    private func severityColor(_ severity: FiredAlert.Severity, tokens: TokenSet) -> Color {
        switch severity {
        case .info:    return tokens.category(.transfers)
        case .warning: return tokens.category(.entertainment)
        case .alert:   return tokens.category(.loans)
        }
    }
}
