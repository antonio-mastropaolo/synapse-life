import SwiftUI
import DesignSystem
import Models

/// Per-transaction detail. Pushed from the Transactions list row.
/// Renders the canonical fields of a `Models.Transaction` in a vertical
/// label/value stack with the amount as a large monospaced hero.
@MainActor
struct TransactionDetailView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    let transaction: Models.Transaction

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        let isInflow = (transaction.amount ?? .zero) > .zero
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                    Text(Self.fullDateFormatter.string(from: transaction.date))
                        .font(tokens.tickerFont(size: 12))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Amount")
                        .font(tokens.tickerFont(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.foregroundSecondary.color)
                    Text((transaction.amount ?? 0).formatted(.currency(code: transaction.currency)))
                        .font(.system(size: 38, weight: .medium, design: .monospaced))
                        .foregroundStyle(isInflow ? tokens.gainAccent.color : tokens.foregroundPrimary.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(tokens.surface.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 10) {
                    if let acct = transaction.accountName {
                        DetailRow(label: "Account", value: acct)
                    }
                    DetailRow(label: "Category",
                              value: transaction.category.displayLabel)
                    DetailRow(label: "Currency", value: transaction.currency)
                    DetailRow(label: "Status",
                              value: transaction.pending ? "Pending" : "Posted")
                }
                .padding(16)
                .background(tokens.surface.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(tokens.background.color.ignoresSafeArea())
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateStyle = .full
        return f
    }()
}

private struct DetailRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    let label: String
    let value: String
    var body: some View {
        let tokens = theme.tokens(for: scheme)
        HStack {
            Text(label)
                .font(tokens.tickerFont(size: 11, weight: .semibold))
                .foregroundStyle(tokens.foregroundSecondary.color)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.foregroundPrimary.color)
                .multilineTextAlignment(.trailing)
        }
    }
}
