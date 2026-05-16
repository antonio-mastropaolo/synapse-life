import SwiftUI
import Models
import DesignSystem

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Right-pane / detail-screen view used by both `ApprovalsFlatView` and
/// `ApprovalsTreeView`. Displays the inspector payload computed by either
/// view model. By design there is NO submit / save-for-later / cancel button
/// here — see memory `feedback_workday_no_terminal_clicks`. The visible note
/// at the bottom of the inspector documents that constraint to the user.
@MainActor
public struct ApprovalsInspector: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    private let payload: ApprovalInspectorPayload

    public init(payload: ApprovalInspectorPayload) {
        self.payload = payload
    }

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(tokens: tokens)
                Divider().background(tokens.foregroundSecondary.color.opacity(0.2))
                totals(tokens: tokens)
                receipts(tokens: tokens)
                if payload.workdayURL != nil {
                    workdayDeeplink(tokens: tokens)
                }
                Spacer(minLength: 12)
                readOnlyNote(tokens: tokens)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(tokens.background.color)
        .accessibilityElement(children: .contain)
    }

    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(payload.approval.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(payload.approval.approver)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                statusBadge(tokens: tokens)
            }
        }
    }

    private func statusBadge(tokens: TokenSet) -> some View {
        let raw = payload.status.rawValue
        return Text(raw.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tokens.accent.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tokens.accent.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func totals(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedTotal())
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text(payload.currency ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
            Text("\(payload.receiptsAttached.count) receipt(s) attached")
                .font(.system(size: 11))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    @ViewBuilder
    private func receipts(tokens: TokenSet) -> some View {
        if payload.receiptsAttached.isEmpty {
            Text("No receipts attached yet.")
                .font(.system(size: 12))
                .foregroundStyle(tokens.foregroundSecondary.color)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Receipts")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tokens.foregroundSecondary.color)
                ForEach(payload.receiptsAttached) { receipt in
                    HStack(alignment: .firstTextBaseline) {
                        Text(receipt.vendor)
                            .font(.system(size: 13))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                        Spacer()
                        Text(receipt.date)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(tokens.foregroundSecondary.color)
                        Text(formattedReceiptAmount(receipt))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(tokens.foregroundPrimary.color)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func workdayDeeplink(tokens: TokenSet) -> some View {
        if let url = payload.workdayURL {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open in Workday")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(tokens.accent.color)
            }
            .accessibilityIdentifier("approvals.inspector.workday")
        }
    }

    private func readOnlyNote(tokens: TokenSet) -> some View {
        Text("Submit, Save, and Cancel must be performed in Workday. This app is read-only for those actions.")
            .font(.system(size: 11))
            .foregroundStyle(tokens.foregroundSecondary.color)
            .multilineTextAlignment(.leading)
            .accessibilityIdentifier("approvals.inspector.readonly-note")
    }

    private func formattedTotal() -> String {
        guard let value = payload.totalAmount else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    private func formattedReceiptAmount(_ receipt: Receipt) -> String {
        guard let value = receipt.amount else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }
}
